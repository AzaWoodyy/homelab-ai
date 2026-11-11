import { useEffect, useMemo, useState } from "react";
import * as Switch from "@radix-ui/react-switch";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { saveModels } from "../api/models";
import type { Summary } from "../api/schemas";
import { Button } from "../components/Button";
import { Field, TextArea } from "../components/Field";
import { StatusPill } from "../components/StatusPill";

export function ModelsPage({ summary }: { summary: Summary }) {
  const queryClient = useQueryClient();
  const configuredText = summary.models.configured.join("\n");
  const [text, setText] = useState(configuredText);
  const [uninstallRemoved, setUninstallRemoved] = useState(false);

  useEffect(() => {
    setText(configuredText);
    setUninstallRemoved(false);
  }, [configuredText]);

  const models = useMemo(
    () =>
      text
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean),
    [text],
  );

  const dirty = text !== configuredText || uninstallRemoved;

  const mutation = useMutation({
    mutationFn: () => saveModels(models, uninstallRemoved),
    onSuccess: (response) => {
      if (response.uninstall_result?.error) {
        toast.error(`Saved, uninstall failed: ${response.uninstall_result.error}`);
      } else if (response.uninstall_result?.removed.length) {
        toast.success(`Saved. Uninstalled ${response.uninstall_result.removed.length}`);
      } else {
        toast.success("Model list saved");
      }

      setText(response.configured.join("\n"));
      setUninstallRemoved(false);
      void queryClient.invalidateQueries({ queryKey: ["summary"] });
    },
    onError: (error) => toast.error(error instanceof Error ? error.message : "Save failed"),
  });

  return (
    <section className="two-column models-layout">
      <article className="panel">
        <header className="panel-head">
          <h2>Configured models</h2>
          <StatusPill tone={dirty ? "warn" : "muted"}>{dirty ? "Changed" : models.length}</StatusPill>
        </header>
        <form
          className="form-grid"
          onSubmit={(event) => {
            event.preventDefault();
            mutation.mutate();
          }}
        >
          <Field label="Models">
            <TextArea rows={16} value={text} onChange={(event) => setText(event.target.value)} />
          </Field>
          <label className="switch-field">
            <span>Uninstall deleted models</span>
            <Switch.Root className="switch-root" checked={uninstallRemoved} onCheckedChange={setUninstallRemoved}>
              <Switch.Thumb className="switch-thumb" />
            </Switch.Root>
          </label>
          <div className="form-actions">
            <Button type="submit" tone="primary" disabled={!dirty || mutation.isPending}>
              Save model list
            </Button>
            <Button
              type="button"
              disabled={!dirty}
              onClick={() => {
                setText(configuredText);
                setUninstallRemoved(false);
              }}
            >
              Discard
            </Button>
          </div>
        </form>
      </article>

      <article className="panel">
        <header className="panel-head">
          <h2>Installed now</h2>
          <StatusPill tone={summary.models.installed.length ? "ok" : "warn"}>{summary.models.installed.length}</StatusPill>
        </header>
        <ul className="model-tags">
          {summary.models.installed.length === 0 && <li className="empty-tag">No installed models</li>}
          {summary.models.installed.map((model) => (
            <li key={model}>{model}</li>
          ))}
        </ul>
      </article>
    </section>
  );
}
