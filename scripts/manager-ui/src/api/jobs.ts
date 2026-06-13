import { apiJson } from "./client";
import { jobsSnapshotSchema, type JobsSnapshot } from "./schemas";

export function getCurrentJob(): Promise<Pick<JobsSnapshot, "current" | "latest" | "pending_apply">> {
  return apiJson(
    "/api/jobs/current",
    jobsSnapshotSchema.pick({ current: true, latest: true, pending_apply: true }),
  );
}

export function getJobHistory(): Promise<Pick<JobsSnapshot, "history">> {
  return apiJson("/api/jobs/history", jobsSnapshotSchema.pick({ history: true }));
}
