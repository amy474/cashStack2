import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { quoted } from '../alerts.ts';
import { HttpError, type Ctx } from '../context.ts';

const KEEP_DAYS = 90;
const MAX_PER_REPORT = 50;
/// Reports come in without a token, so the table could otherwise be filled
/// by anyone. A real crash loop across every phone is far below this.
const MAX_PER_DAY = 2000;

/// Free text from the report. Control characters are dropped: these strings
/// are printed to a terminal by `npm run diagnostics`, where an escape
/// sequence could rewrite the screen or the clipboard.
const text = (max: number) => z.string().max(max).transform((s) => s.replace(/[\u0000-\u001f\u007f-\u009f]/g, ''));

/// The parts of MetricKit's MXDiagnosticPayload JSON the server reads. Every
/// diagnostic carries `diagnosticMetaData`; everything else is kept as sent.
const Meta = z.looseObject({
  appVersion: text(40).optional(),
  appBuildVersion: text(40).optional(),
  osVersion: text(80).optional(),
  deviceType: text(40).optional(),
  exceptionType: z.number().optional(),
  exceptionCode: z.number().optional(),
  signal: z.number().optional(),
  terminationReason: text(300).optional(),
  hangDuration: text(40).optional(),
});
const Diagnostic = z.looseObject({ diagnosticMetaData: Meta.optional() });
const list = z.array(Diagnostic).max(MAX_PER_REPORT).optional();

const Report = z.looseObject({
  crashDiagnostics: list,
  hangDiagnostics: list,
  cpuExceptionDiagnostics: list,
  diskWriteExceptionDiagnostics: list,
  appLaunchDiagnostics: list,
});

const KINDS = {
  crashDiagnostics: 'crash',
  hangDiagnostics: 'hang',
  cpuExceptionDiagnostics: 'cpu',
  diskWriteExceptionDiagnostics: 'disk_write',
  appLaunchDiagnostics: 'launch',
} as const;

/// Mach exception types MetricKit reports, by number.
const EXCEPTIONS: Record<number, string> = {
  1: 'EXC_BAD_ACCESS',
  2: 'EXC_BAD_INSTRUCTION',
  3: 'EXC_ARITHMETIC',
  5: 'EXC_SOFTWARE',
  6: 'EXC_BREAKPOINT',
  10: 'EXC_CRASH',
  11: 'EXC_RESOURCE',
  12: 'EXC_GUARD',
};
const SIGNALS: Record<number, string> = { 4: 'SIGILL', 5: 'SIGTRAP', 6: 'SIGABRT', 9: 'SIGKILL', 10: 'SIGBUS', 11: 'SIGSEGV' };

/// "EXC_BREAKPOINT (SIGTRAP)" for a Swift trap, "2.4 sec hang", and so on.
export function summarise(kind: string, meta: z.infer<typeof Meta> = {}): string {
  if (kind === 'crash') {
    const exception = meta.exceptionType !== undefined ? (EXCEPTIONS[meta.exceptionType] ?? `exception ${meta.exceptionType}`) : undefined;
    const signal = meta.signal !== undefined ? (SIGNALS[meta.signal] ?? `signal ${meta.signal}`) : undefined;
    const parts = [exception, signal && (exception ? `(${signal})` : signal)].filter(Boolean);
    if (parts.length) return parts.join(' ');
    return meta.terminationReason?.slice(0, 120) || 'crash';
  }
  if (kind === 'hang') return meta.hangDuration ? `${meta.hangDuration} hang` : 'hang';
  return { cpu: 'too much CPU', disk_write: 'too many disk writes', launch: 'slow launch' }[kind] ?? kind;
}

/// Where MetricKit's reports land. The app sends them without a token, so a
/// crash before sign-in, or in the demo, is reported too, and the report
/// isn't tied to anyone. Crashes raise an alert.
export function diagnosticsRoutes(app: FastifyInstance, ctx: Ctx) {
  app.post(
    '/v1/diagnostics',
    {
      bodyLimit: 512 * 1024,
      config: { rateLimit: { max: 20, timeWindow: '1 hour' } },
    },
    async (req, reply) => {
      const report = Report.parse(req.body);
      const rows: Array<{ kind: string; meta: z.infer<typeof Meta>; summary: string; detail: unknown }> = [];
      for (const [field, kind] of Object.entries(KINDS)) {
        for (const diagnostic of report[field as keyof typeof KINDS] ?? []) {
          const meta = diagnostic.diagnosticMetaData ?? {};
          rows.push({ kind, meta, summary: summarise(kind, meta), detail: diagnostic });
        }
      }
      if (rows.length > MAX_PER_REPORT) rows.length = MAX_PER_REPORT;

      const now = ctx.now();
      const { rows: [today] } = await ctx.db.query<{ count: string | number }>(
        'select count(*) as count from diagnostics where received_at > $1',
        [new Date(now.getTime() - 86_400_000)],
      );
      if (Number(today?.count ?? 0) + rows.length > MAX_PER_DAY) {
        ctx.alerts.notify('diagnostics:full', `CashStack API: more than ${MAX_PER_DAY} diagnostic reports in a day; turning more away until tomorrow.`);
        reply.header('Retry-After', '3600');
        throw new HttpError(429, 'rate_limited', 'Too many reports today. Try again later.');
      }

      await ctx.db.tx(async (t) => {
        for (const row of rows) {
          await t.query(
            `insert into diagnostics (kind, app_version, app_build, os_version, device_type, summary, detail, received_at)
             values ($1, $2, $3, $4, $5, $6, $7::jsonb, $8)`,
            [row.kind, row.meta.appVersion ?? null, row.meta.appBuildVersion ?? null, row.meta.osVersion ?? null,
              row.meta.deviceType ?? null, row.summary, JSON.stringify(row.detail), now],
          );
        }
        await t.query('delete from diagnostics where received_at < $1', [new Date(now.getTime() - KEEP_DAYS * 86_400_000)]);
      });

      for (const row of rows) {
        req.log.warn({ kind: row.kind, build: row.meta.appBuildVersion, summary: row.summary }, 'app diagnostic received');
        if (row.kind !== 'crash') continue;
        // Everything here but the wording is from the report, so it goes in quoted.
        const version = `${row.meta.appVersion ?? '?'} (${row.meta.appBuildVersion ?? '?'})`;
        ctx.alerts.notify(
          `crash:${row.meta.appBuildVersion}:${row.summary}`,
          `CashStack ${quoted(version)} crashed: ${quoted(row.summary)} on ${quoted(row.meta.deviceType ?? 'an iPhone')}, ${quoted(row.meta.osVersion ?? 'unknown iOS')}. \`npm run diagnostics\` has the call stack.`,
        );
      }
      return reply.code(202).send({ received: rows.length });
    },
  );
}
