import type { FastifyBaseLogger } from 'fastify';

/// Where alerts go. Production posts them to ALERT_WEBHOOK_URL; the tests
/// collect them in an array.
export type AlertSink = (text: string) => Promise<void> | void;

/// Tells a person when something breaks: an app crash report arriving, or a
/// request failing in a way the server didn't expect. Each kind of problem
/// alerts once, then stays quiet for a while, so a crash loop is one message
/// rather than a thousand. Alerts never include anything about a person.
///
/// Crash reports arrive without a token, so anyone can make up new "kinds"
/// of crash. However many kinds there are, no more than `budget` alerts go
/// out in any quiet period, so the channel can't be flooded.
export class Alerts {
  private readonly last = new Map<string, number>();
  private sent: number[] = [];
  private readonly sink: AlertSink | undefined;
  private readonly now: () => number;
  private readonly quietMs: number;
  private readonly budget: number;

  constructor(sink: AlertSink | undefined, now: () => number = Date.now, quietMs = 60 * 60_000, budget = 20) {
    this.sink = sink;
    this.now = now;
    this.quietMs = quietMs;
    this.budget = budget;
  }

  notify(key: string, text: string): void {
    const sink = this.sink;
    if (!sink) return;
    const at = this.now();
    const previous = this.last.get(key);
    if (previous !== undefined && at - previous < this.quietMs) return;
    this.sent = this.sent.filter((t) => at - t < this.quietMs);
    if (this.sent.length >= this.budget) return;
    this.sent.push(at);
    if (this.last.size > 500) this.last.clear();
    this.last.set(key, at);
    void Promise.resolve()
      .then(() => sink(text))
      .catch(() => {});
  }
}

/// Text that came from outside (a crash report's device or version, say),
/// made safe to put in an alert: wrapped as code, so Slack draws it as typed,
/// with nothing in it that could close the code span, make a link or ping the
/// channel (`<!channel>`, `<https://…|Click here>`).
export function quoted(text: string): string {
  const safe = text.replace(/[\u0000-\u001f\u007f-\u009f<>&`]/g, '').trim().slice(0, 80);
  return safe ? `\`${safe}\`` : '`?`';
}

/// A Slack-style incoming webhook: `{ "text": "…" }`.
export function webhookSink(url: string, log: FastifyBaseLogger): AlertSink {
  return async (text) => {
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ text }),
        signal: AbortSignal.timeout(5_000),
      });
      if (!res.ok) log.warn({ status: res.status }, 'alert webhook refused the alert');
    } catch (error) {
      log.warn({ err: error }, 'alert webhook unreachable');
    }
  };
}
