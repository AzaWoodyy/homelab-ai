import type { ManagerJob } from "../api/schemas";

export type Tone = "ok" | "warn" | "danger" | "muted" | "info";

export function toneFor(value: unknown): Tone {
  const text = String(value ?? "").toLowerCase();

  if (["ready", "healthy", "running", "true", "ok", "live", "available"].includes(text)) return "ok";
  if (["stopped", "disabled", "unknown", "missing", "daemon-unavailable", "false", "queued"].includes(text)) return "warn";
  if (["failed", "error", "not responding", "unreachable", "exited", "dead"].includes(text)) return "danger";
  return "muted";
}

export function formatDateTime(value?: string | null): string {
  if (!value) return "-";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(date);
}

export function currentOrLatestJob(jobs: { current: ManagerJob | null; latest: ManagerJob | null }): ManagerJob | null {
  return jobs.current ?? jobs.latest;
}

export function isJobBusy(job: ManagerJob | null): boolean {
  return job ? ["queued", "running"].includes(String(job.status)) : false;
}
