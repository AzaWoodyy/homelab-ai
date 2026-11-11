import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { getCurrentJob, getJobHistory } from "../api/jobs";
import type { JobsSnapshot } from "../api/schemas";
import { StatusPill } from "../components/StatusPill";
import { currentOrLatestJob, formatDateTime, toneFor } from "../lib/format";

export function JobsPage({ jobs }: { jobs: JobsSnapshot }) {
  const currentQuery = useQuery({
    queryKey: ["jobs", "current"],
    queryFn: getCurrentJob,
    refetchInterval: 3_000,
  });

  const historyQuery = useQuery({
    queryKey: ["jobs", "history"],
    queryFn: getJobHistory,
    refetchInterval: 10_000,
  });

  const liveJobs = useMemo<JobsSnapshot>(
    () => ({
      current: currentQuery.data?.current ?? jobs.current,
      latest: currentQuery.data?.latest ?? jobs.latest,
      pending_apply: currentQuery.data?.pending_apply ?? jobs.pending_apply,
      history: historyQuery.data?.history ?? jobs.history,
    }),
    [currentQuery.data, historyQuery.data, jobs],
  );

  const activeJob = currentOrLatestJob(liveJobs);
  const log = activeJob?.log_tail?.length ? activeJob.log_tail.join("\n") : "No log output";

  return (
    <section className="two-column jobs-layout">
      <article className="panel">
        <header className="panel-head">
          <h2>Job log</h2>
          <StatusPill tone={toneFor(activeJob?.status)}>{activeJob?.status ?? "Idle"}</StatusPill>
        </header>
        {activeJob && (
          <div className="job-summary-grid">
            <span>Action</span>
            <strong>{activeJob.action}</strong>
            <span>Created</span>
            <strong>{formatDateTime(activeJob.created_at)}</strong>
            <span>Log</span>
            <strong>{activeJob.log_relative_path ?? "-"}</strong>
          </div>
        )}
        <pre className="log-view" aria-live="polite">
          {log}
        </pre>
      </article>
      <article className="panel">
        <header className="panel-head">
          <h2>History</h2>
          <StatusPill tone="muted">{liveJobs.history.length}</StatusPill>
        </header>
        <ol className="history-list">
          {liveJobs.history.length === 0 && <li className="muted-row">No jobs</li>}
          {liveJobs.history.slice(0, 12).map((job, index) => (
            <li key={`${job?.id ?? job?.created_at ?? index}`}>
              <div>
                <span className="status-dot" data-tone={toneFor(job?.status)} />
                <strong>{job?.action ?? "-"}</strong>
              </div>
              <span>{formatDateTime(job?.finished_at ?? job?.created_at)}</span>
              <StatusPill tone={toneFor(job?.status)}>{job?.status ?? "unknown"}</StatusPill>
            </li>
          ))}
        </ol>
      </article>
    </section>
  );
}
