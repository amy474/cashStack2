import type { FastifyBaseLogger } from 'fastify';

/// Where alerts go. Production posts them to ALERT_WEBHOOK_URL; the tests
/// collect them in an array.
export type AlertSink = (text: string) => Promise<void> | void;

/// Tells a person when something breaks: an app crash report arriving, or a
/// request failing in a way the server didn't expect. Each kind of problem
/// alerts once, then stays quiet for a while, so a crash loop is one message
/// rather than a thousand. Alerts never include anything about a person.
export class Alerts {
  private readonly last = new Map<string, number>();
  private readonly sink: AlertSink | undefined;
  private readonly now: () => number;
  private readonly quietMs: number;

  constructor(sink: AlertSink | undefined, now: () => number = Date.now, quietMs = 60 * 60_000) {
    this.sink = sink;
    this.now = now;
    this.quietMs = quietMs;
  }

  notify(key: string, text: string): void {
    const sink = this.sink;
    if (!sink) return;
    const at = this.now();
    const previous = this.last.get(key);
    if (previous !== undefined && at - previous < this.quietMs) return;
    if (this.last.size > 500) this.last.clear();
    this.last.set(key, at);
    void Promise.resolve()
      .then(() => sink(text))
      .catch(() => {});
  }
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
