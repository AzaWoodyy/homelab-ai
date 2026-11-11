import { z } from "zod";
import { listify, nullableString } from "./normalize";

const nullableStringSchema = z.preprocess(nullableString, z.string().nullable());
const stringListSchema = z.preprocess((value) => listify<string>(value).map(String), z.array(z.string()));
const logTailSchema = z.preprocess((value) => listify<string>(value).map(String), z.array(z.string()));
const nullablePositiveIntegerSchema = z.number().int().positive("Must be greater than 0").nullable();

export const sessionSchema = z.object({
  ok: z.boolean(),
  expires_at: z.string(),
  csrf_token: z.string(),
});

export const pendingApplySchema = z
  .object({
    has_pending: z.boolean().default(false),
    updated_at: nullableStringSchema.optional(),
    config_changed: z.boolean().optional(),
    models_changed: z.boolean().optional(),
    added_models: stringListSchema.optional(),
    removed_models: stringListSchema.optional(),
    required_actions: stringListSchema.optional(),
    completed_actions: stringListSchema.optional(),
    remaining_actions: stringListSchema.optional(),
  })
  .nullable();

export const jobSchema = z
  .object({
    id: nullableStringSchema.optional(),
    action: nullableStringSchema,
    status: nullableStringSchema,
    created_at: nullableStringSchema.optional(),
    started_at: nullableStringSchema.optional(),
    finished_at: nullableStringSchema.optional(),
    exit_code: z.number().nullable().optional(),
    log_path: nullableStringSchema.optional(),
    log_relative_path: nullableStringSchema.optional(),
    error: nullableStringSchema.optional(),
    log_tail: logTailSchema.default([]),
  })
  .nullable();

export const jobsSnapshotSchema = z.object({
  current: jobSchema,
  latest: jobSchema,
  history: z.preprocess((value) => listify(value), z.array(jobSchema)).default([]),
  pending_apply: pendingApplySchema,
});

export const editableConfigSchema = z.object({
  openwebui_image_tag: z.string().min(1, "Required"),
  openwebui: z.object({
    mcp_initialize_timeout: z.number().int().positive("Must be greater than 0"),
    kb_exec_enabled: z.boolean(),
    profile_image_max_data_uri_size: nullablePositiveIntegerSchema,
  }),
  voice_vision_model: z.string().min(1, "Required"),
  voice_vision_fallback_model: z.string().min(1, "Required"),
  tts: z.object({
    enabled: z.boolean(),
    default_voice: z.string(),
    fallback_voice: z.string(),
  }),
  stt: z.object({
    model: z.string().min(1, "Required"),
    language: z.string(),
    auto_update: z.boolean(),
  }),
  hermes: z.object({
    enabled: z.boolean(),
    model: z.string().min(1, "Required"),
    api_server: z.object({
      enabled: z.boolean(),
      port: z.number().int().positive("Must be greater than 0").max(65535, "Must be 65535 or lower"),
      model_name: z.string().min(1, "Required"),
    }),
    discord: z.object({
      enabled: z.boolean(),
      require_mention: z.boolean(),
      free_response_channels: z.string(),
    }),
    photon: z.object({
      enabled: z.boolean(),
      sidecar_port: z.number().int().positive("Must be greater than 0").max(65535, "Must be 65535 or lower"),
      sidecar_autostart: z.boolean(),
      require_mention: z.boolean(),
      mention_patterns: z.string(),
    }),
  }),
});

const hermesPlatformSchema = z.object({
  enabled: z.boolean(),
  configured: z.boolean(),
});

export const hermesSummarySchema = z.object({
  enabled: z.boolean(),
  cli_available: z.boolean(),
  version: nullableStringSchema,
  home: z.string(),
  model: z.string(),
  missing_config: stringListSchema.default([]),
  gateway: z.object({
    enabled: z.boolean(),
    running: z.boolean(),
    pid: z.number().nullable(),
    started_at: nullableStringSchema.optional(),
  }),
  api_server: z.object({
    enabled: z.boolean(),
    local_url: z.string(),
    reachable: z.boolean(),
    model_name: z.string(),
  }),
  platforms: z.object({
    discord: hermesPlatformSchema,
    photon: hermesPlatformSchema,
  }),
  log_tail: logTailSchema.default([]),
});

export const configResponseSchema = z.object({
  editable: editableConfigSchema,
  read_only: z.record(z.string(), z.union([z.string(), z.number(), z.boolean(), z.null()])).default({}),
  pending_apply: pendingApplySchema.optional(),
});

const modelsResponseSchema = z.object({
  configured: stringListSchema,
  installed: stringListSchema,
  pending_apply: pendingApplySchema.optional(),
  tts_enabled: z.boolean().optional(),
});

export const modelSaveResponseSchema = modelsResponseSchema.extend({
  added_models: stringListSchema.optional(),
  removed_models: stringListSchema.optional(),
  uninstall_removed: z.boolean().optional(),
  uninstall_result: z
    .object({
      requested: z.boolean(),
      removed: stringListSchema,
      skipped: stringListSchema,
      error: nullableStringSchema,
    })
    .optional(),
});

export const summarySchema = z.object({
  manager: z.object({
    running: z.boolean(),
    pid: z.number().nullable(),
    started_at: nullableStringSchema.optional(),
    local_url: z.string(),
    local_reachable: z.boolean(),
    scheduled_task_registered: z.boolean(),
    management_https_port: z.number(),
  }),
  stack: z.object({
    ollama: z.object({
      ready: z.boolean(),
      version: nullableStringSchema,
    }),
    docker: z.object({
      ready: z.boolean(),
    }),
    open_webui: z.object({
      health: z.string(),
      local_url: z.string(),
      local_reachable: z.boolean(),
      runtime_patch: z.string(),
      whisper_cache: nullableStringSchema.optional(),
    }),
    tts: z.object({
      enabled: z.boolean(),
      health: z.string(),
      local_url: z.string(),
      local_reachable: z.boolean(),
    }),
    hermes: hermesSummarySchema,
  }),
  models: z.object({
    configured: stringListSchema,
    installed: stringListSchema,
  }),
  config: z.object({
    editable: editableConfigSchema,
    read_only: z.record(z.string(), z.union([z.string(), z.number(), z.boolean(), z.null()])).default({}),
  }),
  tailscale: z.object({
    available: z.boolean(),
    error: nullableStringSchema,
    https_url: nullableStringSchema,
    management_remote_url: nullableStringSchema,
    magic_dns_enabled: z.boolean(),
    certs_enabled: z.boolean(),
    open_webui: z
      .object({
        configured_expected: z.boolean(),
        expected_target: z.string(),
      })
      .nullable(),
    management: z
      .object({
        configured_expected: z.boolean(),
        expected_target: z.string(),
        https_port: z.number(),
      })
      .nullable(),
  }),
  jobs: jobsSnapshotSchema,
  meta: z
    .object({
      generated_at: nullableStringSchema,
      duration_ms: z.number().nullable().optional(),
      cache_age_seconds: z.number().nullable().optional(),
      refresh_status: z.enum(["idle", "running", "stale", "missing"]).or(z.string()),
      errors: stringListSchema.default([]),
    })
    .optional(),
});

export const actionResponseSchema = z.object({
  accepted: z.boolean(),
  job: z.unknown(),
});

export type Session = z.infer<typeof sessionSchema>;
export type JobsSnapshot = z.infer<typeof jobsSnapshotSchema>;
export type ManagerJob = NonNullable<z.infer<typeof jobSchema>>;
export type EditableConfig = z.infer<typeof editableConfigSchema>;
export type ConfigResponse = z.infer<typeof configResponseSchema>;
export type ModelSaveResponse = z.infer<typeof modelSaveResponseSchema>;
export type HermesSummary = z.infer<typeof hermesSummarySchema>;
export type Summary = z.infer<typeof summarySchema>;
