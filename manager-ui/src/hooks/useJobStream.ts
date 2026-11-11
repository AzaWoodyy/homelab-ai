import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { jobsSnapshotSchema, type Summary } from "../api/schemas";

type StreamState = "idle" | "live" | "stale";

export function useJobStream(enabled: boolean) {
  const queryClient = useQueryClient();
  const [state, setState] = useState<StreamState>("idle");

  useEffect(() => {
    if (!enabled) {
      setState("idle");
      return undefined;
    }

    let retryTimer: number | undefined;
    let closed = false;
    let source: EventSource | null = null;

    const connect = () => {
      if (closed) return;

      source = new EventSource("/api/jobs/stream", { withCredentials: true });
      setState("live");

      source.addEventListener("update", (event) => {
        const payload = jobsSnapshotSchema.parse(JSON.parse(event.data));
        queryClient.setQueryData<Summary>(["summary"], (summary) => (summary ? { ...summary, jobs: payload } : summary));
        setState("live");
      });

      source.onerror = () => {
        source?.close();
        source = null;
        setState("stale");
        retryTimer = window.setTimeout(connect, 2000);
      };
    };

    connect();

    return () => {
      closed = true;
      if (retryTimer) window.clearTimeout(retryTimer);
      source?.close();
    };
  }, [enabled, queryClient]);

  return state;
}
