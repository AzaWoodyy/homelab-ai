import { ExternalLink } from "lucide-react";
import type { Summary } from "../api/schemas";
import { MetricCard } from "../components/MetricCard";
import { StatusPill } from "../components/StatusPill";
import { currentOrLatestJob, formatDateTime, toneFor } from "../lib/format";

export function OverviewPage({ summary }: { summary: Summary }) {
  const activeJob = currentOrLatestJob(summary.jobs);
  const configured = summary.models.configured.length;
  const installed = summary.models.installed.length;

  return (
    <div className="page-grid">
      <section className="metric-grid" aria-label="Stack status">
        <MetricCard
          title="Manager"
          state={summary.manager.running ? "Running" : "Stopped"}
          tone={summary.manager.running ? "ok" : "danger"}
          rows={[
            { label: "PID", value: summary.manager.pid },
            { label: "Local", value: summary.manager.local_url, title: summary.manager.local_url },
            { label: "Scheduled", value: summary.manager.scheduled_task_registered ? "yes" : "no" },
          ]}
        />
        <MetricCard
          title="Ollama"
          state={summary.stack.ollama.ready ? "Ready" : "Down"}
          tone={summary.stack.ollama.ready ? "ok" : "danger"}
          rows={[{ label: "Version", value: summary.stack.ollama.version }]}
        />
        <MetricCard
          title="Docker"
          state={summary.stack.docker.ready ? "Ready" : "Down"}
          tone={summary.stack.docker.ready ? "ok" : "danger"}
          rows={[{ label: "Engine", value: summary.stack.docker.ready ? "running" : "unavailable" }]}
        />
        <MetricCard
          title="Open WebUI"
          state={summary.stack.open_webui.health}
          tone={toneFor(summary.stack.open_webui.health)}
          rows={[
            { label: "Reachable", value: summary.stack.open_webui.local_reachable ? "yes" : "no" },
            { label: "Patch", value: summary.stack.open_webui.runtime_patch },
            { label: "URL", value: summary.stack.open_webui.local_url, title: summary.stack.open_webui.local_url },
          ]}
        />
        <MetricCard
          title="Local TTS"
          state={summary.stack.tts.enabled ? summary.stack.tts.health : "Disabled"}
          tone={!summary.stack.tts.enabled ? "muted" : toneFor(summary.stack.tts.health)}
          rows={[
            { label: "Enabled", value: summary.stack.tts.enabled ? "yes" : "no" },
            { label: "Reachable", value: summary.stack.tts.local_reachable ? "yes" : "no" },
          ]}
        />
        <MetricCard
          title="Models"
          state={`${installed}/${configured}`}
          tone={installed >= configured && configured > 0 ? "ok" : installed === 0 ? "warn" : "muted"}
          rows={[
            { label: "Configured", value: configured },
            { label: "Installed", value: installed },
          ]}
        />
      </section>

      <section className="two-column">
        <article className="panel">
          <header className="panel-head">
            <h2>Remote access</h2>
            <StatusPill tone={summary.tailscale.available ? "ok" : "warn"}>
              {summary.tailscale.available ? "Available" : "Unavailable"}
            </StatusPill>
          </header>
          <div className="link-list">
            <LinkRow label="Open WebUI" value={summary.tailscale.https_url} />
            <LinkRow label="Manager" value={summary.tailscale.management_remote_url} />
            <LinkRow label="Serve 443" value={summary.tailscale.open_webui?.configured_expected ? "configured" : "not configured"} />
            <LinkRow label={`Serve ${summary.manager.management_https_port}`} value={summary.tailscale.management?.configured_expected ? "configured" : "not configured"} />
          </div>
        </article>

        <article className="panel">
          <header className="panel-head">
            <h2>Current job</h2>
            <StatusPill tone={toneFor(activeJob?.status)}>{activeJob?.status ?? "Idle"}</StatusPill>
          </header>
          {activeJob ? (
            <div className="job-facts">
              <span>Action</span>
              <strong>{activeJob.action}</strong>
              <span>Started</span>
              <strong>{formatDateTime(activeJob.started_at)}</strong>
              <span>Finished</span>
              <strong>{formatDateTime(activeJob.finished_at)}</strong>
            </div>
          ) : (
            <div className="empty-state compact">Idle</div>
          )}
        </article>
      </section>
    </div>
  );
}

function LinkRow({ label, value }: { label: string; value: string | null }) {
  const isUrl = value?.startsWith("http") === true;

  return (
    <div className="link-row">
      <span>{label}</span>
      {isUrl && value ? (
        <a href={value} target="_blank" rel="noreferrer">
          {value}
          <ExternalLink size={13} />
        </a>
      ) : (
        <strong>{value ?? "-"}</strong>
      )}
    </div>
  );
}
