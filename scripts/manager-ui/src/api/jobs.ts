import { apiGet } from "./client";
import { jobsSnapshotSchema, type JobsSnapshot } from "./schemas";

export function getCurrentJob(): Promise<Pick<JobsSnapshot, "current" | "latest" | "pending_apply">> {
  return apiGet(
    "/api/jobs/current",
    jobsSnapshotSchema.pick({ current: true, latest: true, pending_apply: true }),
  );
}

export function getJobHistory(): Promise<Pick<JobsSnapshot, "history">> {
  return apiGet("/api/jobs/history", jobsSnapshotSchema.pick({ history: true }));
}
