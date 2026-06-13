import type { Tone } from "../lib/format";
import { StatusPill } from "./StatusPill";

type MetricRow = {
  label: string;
  value: string | number | null | undefined;
  title?: string | null;
};

type MetricCardProps = {
  title: string;
  state: string;
  tone: Tone;
  rows: MetricRow[];
};

export function MetricCard({ title, state, tone, rows }: MetricCardProps) {
  return (
    <article className="metric-card">
      <header className="metric-head">
        <span className="status-dot" data-tone={tone} />
        <h3>{title}</h3>
        <StatusPill tone={tone}>{state}</StatusPill>
      </header>
      <dl className="metric-rows">
        {rows.map((row) => (
          <div className="metric-row" key={row.label}>
            <dt>{row.label}</dt>
            <dd title={row.title ?? String(row.value ?? "")}>{row.value ?? "-"}</dd>
          </div>
        ))}
      </dl>
    </article>
  );
}
