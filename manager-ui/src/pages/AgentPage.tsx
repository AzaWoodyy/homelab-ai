import { Bot, CheckCircle2, CircleAlert, ExternalLink } from "lucide-react";
import type { ReactNode } from "react";
import type { HermesSummary } from "../api/schemas";
import { StatusPill } from "../components/StatusPill";
import { formatDateTime, toneFor } from "../lib/format";

export function AgentPage({ hermes }: { hermes: HermesSummary }) {
  return (
    <div className="page-grid">
      <section className="metric-grid" aria-label="Hermes status">
        <AgentFact title="Gateway" state={!hermes.enabled ? "Disabled" : hermes.gateway.running ? "Running" : "Stopped"} tone={!hermes.enabled ? "muted" : hermes.gateway.running ? "ok" : "warn"}>
          <Fact label="PID" value={hermes.gateway.pid} />
          <Fact label="Started" value={formatDateTime(hermes.gateway.started_at)} />
        </AgentFact>
        <AgentFact title="API server" state={hermes.api_server.reachable ? "Reachable" : hermes.api_server.enabled ? "Offline" : "Disabled"} tone={hermes.api_server.reachable ? "ok" : hermes.api_server.enabled ? "warn" : "muted"}>
          <Fact label="URL" value={hermes.api_server.local_url} href={hermes.api_server.local_url} />
          <Fact label="Model" value={hermes.api_server.model_name} />
        </AgentFact>
        <AgentFact title="Hermes CLI" state={hermes.cli_available ? "Found" : "Missing"} tone={hermes.cli_available ? "ok" : "warn"}>
          <Fact label="Version" value={hermes.version} />
          <Fact label="Home" value={hermes.home} />
        </AgentFact>
      </section>

      <section className="two-column">
        <article className="panel">
          <header className="panel-head">
            <h2>Channels</h2>
            <StatusPill tone={hermes.enabled ? "info" : "muted"}>{hermes.enabled ? hermes.model : "Disabled"}</StatusPill>
          </header>
          <div className="channel-list">
            <ChannelRow label="Discord" enabled={hermes.platforms.discord.enabled} configured={hermes.platforms.discord.configured} />
            <ChannelRow label="Photon iMessage" enabled={hermes.platforms.photon.enabled} configured={hermes.platforms.photon.configured} />
          </div>
        </article>

        <article className="panel">
          <header className="panel-head">
            <h2>Configuration</h2>
            <StatusPill tone={hermes.missing_config.length ? "warn" : "ok"}>{hermes.missing_config.length ? "Needs secrets" : "Ready"}</StatusPill>
          </header>
          {hermes.missing_config.length ? (
            <ul className="model-tags">
              {hermes.missing_config.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          ) : (
            <div className="empty-state compact">Configured</div>
          )}
        </article>
      </section>

      <section className="panel">
        <header className="panel-head">
          <h2>Gateway log</h2>
          <StatusPill tone={hermes.log_tail.length ? "muted" : "warn"}>{hermes.log_tail.length ? `${hermes.log_tail.length} lines` : "Empty"}</StatusPill>
        </header>
        <pre className="log-view">{hermes.log_tail.length ? hermes.log_tail.join("\n") : "No Hermes gateway log has been written yet."}</pre>
      </section>
    </div>
  );
}

function AgentFact({
  title,
  state,
  tone,
  children,
}: {
  title: string;
  state: string;
  tone: "ok" | "warn" | "danger" | "muted" | "info";
  children: ReactNode;
}) {
  return (
    <article className="metric-card">
      <header className="metric-head">
        <Bot size={15} />
        <h3>{title}</h3>
        <StatusPill tone={tone}>{state}</StatusPill>
      </header>
      <dl className="metric-rows">{children}</dl>
    </article>
  );
}

function Fact({ label, value, href }: { label: string; value: string | number | null | undefined; href?: string }) {
  const text = value == null || value === "" ? "-" : String(value);

  return (
    <div className="metric-row">
      <dt>{label}</dt>
      <dd title={text}>
        {href ? (
          <a href={href} target="_blank" rel="noreferrer">
            {text}
            <ExternalLink size={12} />
          </a>
        ) : (
          text
        )}
      </dd>
    </div>
  );
}

function ChannelRow({ label, enabled, configured }: { label: string; enabled: boolean; configured: boolean }) {
  const state = !enabled ? "Disabled" : configured ? "Configured" : "Needs config";

  return (
    <div className="channel-row">
      {configured ? <CheckCircle2 size={16} /> : <CircleAlert size={16} />}
      <span>{label}</span>
      <StatusPill tone={toneFor(state)}>{state}</StatusPill>
    </div>
  );
}
