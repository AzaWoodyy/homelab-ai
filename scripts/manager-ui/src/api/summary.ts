import { apiGet, apiPost } from "./client";
import { summarySchema, type Summary } from "./schemas";

export function getSummary(): Promise<Summary> {
  return apiGet("/api/summary", summarySchema);
}

export function refreshSummary(): Promise<Summary> {
  return apiPost("/api/summary/refresh", summarySchema);
}
