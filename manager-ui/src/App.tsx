import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import * as Tooltip from "@radix-ui/react-tooltip";
import { Activity, Bot, Boxes, FileText, ListChecks, LogOut, Play, RefreshCcw, Settings, Shield } from "lucide-react";
import { toast } from "sonner";
import { ApiError } from "./api/client";
import { getSession, login, logout } from "./api/auth";
import { getSummary, refreshSummary } from "./api/summary";
import type { Summary } from "./api/schemas";
import { useJobStream } from "./hooks/useJobStream";
import { Button } from "./components/Button";
import { Field, SecretInput } from "./components/Field";
import { OverviewPage } from "./pages/OverviewPage";
import { ActionsPage } from "./pages/ActionsPage";
import { ConfigPage } from "./pages/ConfigPage";
import { ModelsPage } from "./pages/ModelsPage";
import { JobsPage } from "./pages/JobsPage";
import { AgentPage } from "./pages/AgentPage";

type Section = "overview" | "actions" | "config" | "models" | "agent" | "jobs";

const navItems: Array<{ id: Section; label: string; icon: React.ComponentType<{ size?: number }> }> = [
  { id: "overview", label: "Overview", icon: Activity },
  { id: "actions", label: "Actions", icon: Play },
  { id: "config", label: "Config", icon: Settings },
  { id: "models", label: "Models", icon: Boxes },
  { id: "agent", label: "Agent", icon: Bot },
  { id: "jobs", label: "Jobs", icon: ListChecks },
];

function isUnauthorized(error: unknown): boolean {
  return error instanceof ApiError && error.status === 401;
}

export function App() {
  const queryClient = useQueryClient();
  const [section, setSection] = useState<Section>("overview");

  const sessionQuery = useQuery({
    queryKey: ["session"],
    queryFn: getSession,
  });

  const authenticated = sessionQuery.isSuccess;

  const summaryQuery = useQuery({
    queryKey: ["summary"],
    queryFn: getSummary,
    enabled: authenticated,
    refetchInterval: (query) => {
      if (!authenticated) return false;
      const data = query.state.data as Summary | undefined;
      return data?.meta?.refresh_status === "running" ? 2_000 : 45_000;
    },
  });

  const streamState = useJobStream(authenticated);

  const refreshMutation = useMutation({
    mutationFn: refreshSummary,
    onSuccess: (nextSummary) => {
      queryClient.setQueryData(["summary"], nextSummary);

      if (nextSummary.meta?.refresh_status === "running") {
        void queryClient.invalidateQueries({ queryKey: ["summary"] });
      }
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : "Refresh failed");
    },
  });

  const logoutMutation = useMutation({
    mutationFn: logout,
    onSettled: () => {
      queryClient.clear();
    },
  });

  const refresh = () => {
    refreshMutation.mutate();
  };

  if (sessionQuery.isLoading) {
    return <BootScreen />;
  }

  if (!authenticated || isUnauthorized(sessionQuery.error)) {
    return <LoginScreen />;
  }

  const summary = summaryQuery.data;

  return (
    <Tooltip.Provider delayDuration={500} skipDelayDuration={100}>
      <div className="app-shell">
        <aside className="sidebar">
          <SectionNav current={section} onChange={setSection} />
        </aside>

        <div className="main-shell">
          <header className="topbar">
            <div className="topbar-brand">
              <span className="brand-mark" aria-hidden="true">
                <Shield size={15} />
              </span>
              <span className="brand-name">Homelab AI</span>
            </div>
            <div className="topbar-title">
              <h1>{navItems.find((item) => item.id === section)?.label}</h1>
              <div className="topbar-status-row">
                <ConnectionState state={streamState} />
                <SummaryFreshness summary={summary} />
              </div>
            </div>
            <div className="topbar-actions">
              <Tooltip.Root>
                <Tooltip.Trigger asChild>
                  <Button
                    type="button"
                    className="icon-button"
                    aria-label="Refresh"
                    onClick={refresh}
                    disabled={summaryQuery.isFetching || refreshMutation.isPending}
                    icon={<RefreshCcw size={16} />}
                  />
                </Tooltip.Trigger>
                <Tooltip.Portal>
                  <Tooltip.Content className="tooltip" sideOffset={8}>
                    Refresh
                    <Tooltip.Arrow className="tooltip-arrow" />
                  </Tooltip.Content>
                </Tooltip.Portal>
              </Tooltip.Root>
              <Button
                type="button"
                className="topbar-logout"
                aria-label="Sign out"
                onClick={() => logoutMutation.mutate()}
                icon={<LogOut size={15} />}
              >
                <span className="logout-label">Sign out</span>
              </Button>
            </div>
          </header>

          <main className="content">
            {summaryQuery.isLoading && <div className="empty-state">Loading</div>}
            {summaryQuery.error && !summary && <div className="empty-state">Summary unavailable</div>}
            {summary && (
              <>
                <PendingApplyBar summary={summary} />
                {section === "overview" && <OverviewPage summary={summary} />}
                {section === "actions" && <ActionsPage summary={summary} />}
                {section === "config" && <ConfigPage summary={summary} />}
                {section === "models" && <ModelsPage summary={summary} />}
                {section === "agent" && <AgentPage hermes={summary.stack.hermes} />}
                {section === "jobs" && <JobsPage jobs={summary.jobs} />}
              </>
            )}
          </main>
        </div>
        <nav className="mobile-nav" aria-label="Manager sections">
          <SectionNav current={section} onChange={setSection} compact />
        </nav>
      </div>
    </Tooltip.Provider>
  );
}

function SectionNav({
  current,
  onChange,
  compact = false,
}: {
  current: Section;
  onChange: (section: Section) => void;
  compact?: boolean;
}) {
  return (
    <div className={compact ? "nav-list nav-list-mobile" : "nav-list"}>
      {navItems.map((item) => {
        const Icon = item.icon;
        return (
          <button
            type="button"
            key={item.id}
            className="nav-item"
            data-active={current === item.id}
            onClick={() => onChange(item.id)}
            aria-current={current === item.id ? "page" : undefined}
          >
            <Icon size={compact ? 18 : 16} />
            <span>{item.label}</span>
          </button>
        );
      })}
    </div>
  );
}

function BootScreen() {
  return (
    <div className="boot-screen">
      <div className="spinner" aria-hidden="true" />
    </div>
  );
}

function LoginScreen() {
  const queryClient = useQueryClient();
  const [secret, setSecret] = useState("");
  const mutation = useMutation({
    mutationFn: login,
    onSuccess: (session) => {
      queryClient.setQueryData(["session"], session);
      toast.success("Signed in");
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : "Sign in failed");
    },
  });

  return (
    <main className="login-screen">
      <form
        className="login-panel"
        onSubmit={(event) => {
          event.preventDefault();
          mutation.mutate(secret);
        }}
      >
        <div className="login-brand">
          <span className="brand-mark" aria-hidden="true">
            <Shield size={15} />
          </span>
          <h1>Homelab AI</h1>
        </div>
        <Field label="Admin secret">
          <SecretInput
            autoFocus
            autoComplete="current-password"
            value={secret}
            onChange={(event) => setSecret(event.target.value)}
            required
          />
        </Field>
        <Button type="submit" tone="primary" block disabled={mutation.isPending}>
          Unlock
        </Button>
      </form>
    </main>
  );
}

function ConnectionState({ state }: { state: "idle" | "live" | "stale" }) {
  const label = state === "live" ? "Live" : state === "stale" ? "Reconnecting" : "Idle";
  return (
    <span className="connection-state">
      <span className="status-dot" data-tone={state === "live" ? "ok" : state === "stale" ? "warn" : "muted"} />
      {label}
    </span>
  );
}

function formatAge(seconds: number): string {
  if (seconds < 5) return "just now";
  if (seconds < 60) return `${seconds}s ago`;

  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;

  const hours = Math.floor(minutes / 60);
  return `${hours}h ago`;
}

function SummaryFreshness({ summary }: { summary?: Summary }) {
  const meta = summary?.meta;
  const status = meta?.refresh_status;
  const label =
    status === "running"
      ? "Refreshing"
      : typeof meta?.cache_age_seconds === "number"
        ? `Updated ${formatAge(meta.cache_age_seconds)}`
        : "Status pending";

  return (
    <span className="summary-freshness" data-state={status ?? "missing"}>
      {label}
    </span>
  );
}

function PendingApplyBar({ summary }: { summary: Summary }) {
  const pending = summary.jobs.pending_apply;
  const text = useMemo(() => {
    if (!pending?.has_pending) return "";
    const remaining = pending.remaining_actions?.length ? pending.remaining_actions.join(" -> ") : "none";
    return `Pending apply: ${remaining}`;
  }, [pending]);

  if (!pending?.has_pending) return null;

  return (
    <div className="pending-bar">
      <FileText size={16} />
      <span>{text}</span>
    </div>
  );
}
