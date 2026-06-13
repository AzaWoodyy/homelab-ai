import { Moon, Power, RotateCcw, ShieldAlert } from "lucide-react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { runAction, type ManagerAction } from "../api/actions";
import type { Summary } from "../api/schemas";
import { Button } from "../components/Button";
import { DangerDialog } from "../components/DangerDialog";
import { StatusPill } from "../components/StatusPill";
import { currentOrLatestJob, isJobBusy } from "../lib/format";

type ActionDef = {
  action: ManagerAction;
  label: string;
  tone?: "primary" | "soft" | "ghost" | "danger";
  confirm?: {
    title: string;
    description: string;
  };
};

const groups: Array<{ title: string; actions: ActionDef[] }> = [
  {
    title: "Stack",
    actions: [
      { action: "start", label: "Start", tone: "primary" },
      { action: "stop", label: "Stop", tone: "soft" },
      { action: "setup", label: "Run setup", tone: "soft" },
      { action: "test", label: "Healthcheck", tone: "soft" },
    ],
  },
  {
    title: "Models",
    actions: [{ action: "refresh-models", label: "Refresh models", tone: "soft" }],
  },
  {
    title: "Host power",
    actions: [
      {
        action: "sleep",
        label: "Sleep",
        tone: "soft",
        confirm: {
          title: "Sleep host",
          description: "The stack will stop before Windows enters sleep.",
        },
      },
      {
        action: "shutdown",
        label: "Shut down",
        tone: "danger",
        confirm: {
          title: "Shut down host",
          description: "The stack will stop before Windows powers off.",
        },
      },
    ],
  },
  {
    title: "Manager process",
    actions: [
      { action: "manager-restart", label: "Restart manager", tone: "ghost" },
      {
        action: "manager-stop",
        label: "Stop manager",
        tone: "danger",
        confirm: {
          title: "Stop manager",
          description: "The control surface will go offline.",
        },
      },
    ],
  },
];

export function ActionsPage({ summary }: { summary: Summary }) {
  const queryClient = useQueryClient();
  const activeJob = currentOrLatestJob(summary.jobs);
  const busy = isJobBusy(summary.jobs.current);

  const mutation = useMutation({
    mutationFn: runAction,
    onSuccess: (_, action) => {
      toast.success(`Started: ${action}`);
      void queryClient.invalidateQueries({ queryKey: ["summary"] });
    },
    onError: (error) => toast.error(error instanceof Error ? error.message : "Action failed"),
  });

  const startAction = (action: ManagerAction) => mutation.mutate(action);

  return (
    <section className="panel">
      <header className="panel-head">
        <h2>Actions</h2>
        <StatusPill tone={busy ? "warn" : "ok"}>{busy ? "Busy" : "Ready"}</StatusPill>
      </header>
      <div className="action-layout">
        {groups.map((group) => (
          <div className="action-group" key={group.title}>
            <h3>{group.title}</h3>
            <div className="action-row">
              {group.actions.map((item) => {
                const button = (
                  <Button
                    type="button"
                    key={item.action}
                    tone={item.tone ?? "ghost"}
                    disabled={busy || mutation.isPending}
                    onClick={item.confirm ? undefined : () => startAction(item.action)}
                    icon={iconForAction(item.action)}
                  >
                    {item.label}
                  </Button>
                );

                if (!item.confirm) return button;

                return (
                  <DangerDialog
                    key={item.action}
                    title={item.confirm.title}
                    description={item.confirm.description}
                    confirmLabel={item.label}
                    disabled={busy || mutation.isPending}
                    onConfirm={() => startAction(item.action)}
                  >
                    {button}
                  </DangerDialog>
                );
              })}
            </div>
          </div>
        ))}
      </div>
      {activeJob && (
        <footer className="action-footer">
          <span>{activeJob.action}</span>
          <StatusPill tone={busy ? "warn" : "muted"}>{activeJob.status ?? "unknown"}</StatusPill>
        </footer>
      )}
    </section>
  );
}

function iconForAction(action: ManagerAction) {
  if (action === "sleep") return <Moon size={15} />;
  if (action === "shutdown") return <Power size={15} />;
  if (action === "manager-restart") return <RotateCcw size={15} />;
  if (action === "manager-stop") return <ShieldAlert size={15} />;
  return undefined;
}
