import { useEffect } from "react";
import { Controller, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import * as Switch from "@radix-ui/react-switch";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { saveConfig } from "../api/config";
import { editableConfigSchema, type EditableConfig, type Summary } from "../api/schemas";
import { Button } from "../components/Button";
import { Field, TextInput } from "../components/Field";
import { StatusPill } from "../components/StatusPill";

export function ConfigPage({ summary }: { summary: Summary }) {
  const queryClient = useQueryClient();
  const form = useForm<EditableConfig>({
    resolver: zodResolver(editableConfigSchema),
    values: summary.config.editable,
    mode: "onBlur",
  });

  useEffect(() => {
    form.reset(summary.config.editable);
  }, [form, summary.config.editable]);

  const mutation = useMutation({
    mutationFn: saveConfig,
    onSuccess: (response) => {
      toast.success("Runtime config saved");
      form.reset(response.editable);
      void queryClient.invalidateQueries({ queryKey: ["summary"] });
    },
    onError: (error) => toast.error(error instanceof Error ? error.message : "Save failed"),
  });

  return (
    <section className="two-column config-layout">
      <article className="panel">
        <header className="panel-head">
          <h2>Runtime config</h2>
          <StatusPill tone={form.formState.isDirty ? "warn" : "muted"}>{form.formState.isDirty ? "Changed" : "Clean"}</StatusPill>
        </header>
        <form className="form-grid" onSubmit={form.handleSubmit((values) => mutation.mutate(values))}>
          <Field label="Open WebUI image tag" error={form.formState.errors.openwebui_image_tag?.message}>
            <TextInput {...form.register("openwebui_image_tag")} />
          </Field>
          <Field label="Voice vision model" error={form.formState.errors.voice_vision_model?.message}>
            <TextInput {...form.register("voice_vision_model")} />
          </Field>
          <Field label="Voice vision fallback" error={form.formState.errors.voice_vision_fallback_model?.message}>
            <TextInput {...form.register("voice_vision_fallback_model")} />
          </Field>

          <div className="form-section">TTS</div>
          <Controller
            control={form.control}
            name="tts.enabled"
            render={({ field }) => (
              <SwitchField label="Local TTS" checked={field.value} onCheckedChange={field.onChange} />
            )}
          />
          <Field label="Default TTS voice">
            <TextInput {...form.register("tts.default_voice")} />
          </Field>
          <Field label="Fallback TTS voice">
            <TextInput {...form.register("tts.fallback_voice")} />
          </Field>

          <div className="form-section">Whisper</div>
          <Field label="Whisper model" error={form.formState.errors.stt?.model?.message}>
            <TextInput {...form.register("stt.model")} />
          </Field>
          <Field label="Whisper language">
            <TextInput {...form.register("stt.language")} />
          </Field>
          <Controller
            control={form.control}
            name="stt.auto_update"
            render={({ field }) => (
              <SwitchField label="Whisper auto update" checked={field.value} onCheckedChange={field.onChange} />
            )}
          />

          <div className="form-actions">
            <Button type="submit" tone="primary" disabled={!form.formState.isDirty || mutation.isPending}>
              Save runtime config
            </Button>
            <Button type="button" onClick={() => form.reset(summary.config.editable)} disabled={!form.formState.isDirty}>
              Discard
            </Button>
          </div>
        </form>
      </article>

      <article className="panel">
        <header className="panel-head">
          <h2>System</h2>
          <StatusPill tone="muted">Read-only</StatusPill>
        </header>
        <dl className="readonly-grid">
          {Object.entries(summary.config.read_only).map(([key, value]) => (
            <div key={key}>
              <dt>{key}</dt>
              <dd>{value == null || value === "" ? "-" : String(value)}</dd>
            </div>
          ))}
        </dl>
      </article>
    </section>
  );
}

function SwitchField({
  label,
  checked,
  onCheckedChange,
}: {
  label: string;
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
}) {
  return (
    <label className="switch-field">
      <span>{label}</span>
      <Switch.Root className="switch-root" checked={checked} onCheckedChange={onCheckedChange}>
        <Switch.Thumb className="switch-thumb" />
      </Switch.Root>
    </label>
  );
}
