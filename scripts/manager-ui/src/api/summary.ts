import { apiJson } from "./client";
import { summarySchema, type Summary } from "./schemas";

export function getSummary(): Promise<Summary> {
  return apiJson("/api/summary", summarySchema);
}

export function refreshSummary(): Promise<Summary> {
  return apiJson("/api/summary/refresh", summarySchema, {
    method: "POST",
    body: "{}",
  });
}
