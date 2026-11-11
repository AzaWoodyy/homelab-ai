import { useEffect } from "react";
import { Controller, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import * as Switch from "@radix-ui/react-switch";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { saveConfig } from "../api/config";
import { editableConfigSchema, type EditableConfig, type Summary } from "../api/schemas";
import { Button } from "../components/Button";
import { Field, NumberInput, TextInput } from "../components/Field";
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

          <div className="form-section">Open WebUI</div>
          <Field label="MCP initialize timeout (seconds)" error={form.formState.errors.openwebui?.mcp_initialize_timeout?.message}>
            <NumberInput min={1} step={1} {...form.register("openwebui.mcp_initialize_timeout", { valueAsNumber: true })} />
          </Field>
          <Controller
            control={form.control}
            name="openwebui.kb_exec_enabled"
            render={({ field }) => (
              <SwitchField label="Knowledge base exec" checked={field.value} onCheckedChange={field.onChange} />
            )}
          />
          <Field label="Profile image max data URI size (bytes)" error={form.formState.errors.openwebui?.profile_image_max_data_uri_size?.message}>
            <NumberInput
              min={1}
              step={1}
              placeholder="Unset"
              {...form.register("openwebui.profile_image_max_data_uri_size", {
                setValueAs: (value) => (value === "" ? null : Number(value)),
              })}
            />
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

          <div className="form-section">Hermes Agent</div>
          <Controller
            control={form.control}
            name="hermes.enabled"
            render={({ field }) => (
              <SwitchField label="Hermes Agent" checked={field.value} onCheckedChange={field.onChange} />
            )}
          />
          <Field label="Hermes model" error={form.formState.errors.hermes?.model?.message}>
            <TextInput {...form.register("hermes.model")} />
          </Field>
          <Controller
            control={form.control}
            name="hermes.api_server.enabled"
            render={({ field }) => (
              <SwitchField label="Hermes API server" checked={field.value} onCheckedChange={field.onChange} />
            )}
          />
          <Field label="Hermes API port" error={form.formState.errors.hermes?.api_server?.port?.message}>
            <NumberInput min={1} max={65535} step={1} {...form.register("hermes.api_server.port", { valueAsNumber: true })} />
          </Field>
          <Field label="Hermes API model name" error={form.formState.errors.hermes?.api_server?.model_name?.message}>
            <TextInput {...form.register("hermes.api_server.model_name")} />
          </Field>

          <div className="form-section">Hermes Channels</div>
          <Controller
            control={form.control}
            name="hermes.discord.enabled"
            render={({ field }) => (
              <SwitchField label="Discord" checked={field.value} onCheckedChange={field.onChange} />
            )}
          />
          <Controller
            control={form.control}
            name="hermes.discord.require_mention"
            render={({ field }) => (
              <SwitchField label="Discord require mention" checked={field.value} onCheckedChange={field.onChange} />
            )}
          />
          <Field label="Discord free-response channels">
            <TextInput {...form.register("hermes.discord.free_response_channels")} />
          </Field>
          <Controller
            control={form.control}
            name="hermes.photon.enabled"
            render={({ field }) => (
              <SwitchField label="Photon iMessage" checked={field.value} onCheckedChange={field.onChange} />
            )}
          />
          <Field label="Photon sidecar port" error={form.formState.errors.hermes?.photon?.sidecar_port?.message}>
            <NumberInput min={1} max={65535} step={1} {...form.register("hermes.photon.sidecar_port", { valueAsNumber: true })} />
          </Field>
          <Controller
            control={form.control}
            name="hermes.photon.sidecar_autostart"
            render={({ field }) => (
              <SwitchField label="Photon sidecar autostart" checked={field.value} onCheckedChange={field.onChange} />
            )}
          />
          <Controller
            control={form.control}
            name="hermes.photon.require_mention"
            render={({ field }) => (
              <SwitchField label="Photon require mention" checked={field.value} onCheckedChange={field.onChange} />
            )}
          />
          <Field label="Photon mention patterns">
            <TextInput {...form.register("hermes.photon.mention_patterns")} />
          </Field>

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
