import { afterEach, describe, expect, it, vi } from "vitest";
import { setCsrfToken } from "./client";
import { refreshSummary } from "./summary";

const summaryFixture = {
  manager: {
    running: true,
    pid: 123,
    started_at: "2026-06-13T12:00:00Z",
    local_url: "http://127.0.0.1:3081",
    local_reachable: true,
    scheduled_task_registered: false,
    management_https_port: 443,
  },
  stack: {
    ollama: { ready: false, version: null },
    docker: { ready: false },
    open_webui: {
      health: "unknown",
      local_url: "http://127.0.0.1:3000",
      local_reachable: false,
      runtime_patch: "unknown",
      whisper_cache: null,
    },
    tts: {
      enabled: false,
      health: "disabled",
      local_url: "http://127.0.0.1:8000",
      local_reachable: false,
    },
    hermes: {
      enabled: false,
      cli_available: false,
      version: null,
      home: "D:\\dev\\homelab-ai\\state\\hermes",
      model: "hermes3:8b",
      missing_config: [],
      gateway: {
        enabled: true,
        running: false,
        pid: null,
        started_at: null,
      },
      api_server: {
        enabled: true,
        local_url: "http://127.0.0.1:8642",
        reachable: false,
        model_name: "Hermes Agent",
      },
      platforms: {
        discord: { enabled: true, configured: false },
        photon: { enabled: true, configured: false },
      },
      log_tail: [],
    },
  },
  models: { configured: [], installed: [] },
  config: {
    editable: {
      openwebui_image_tag: "main",
      openwebui: {
        mcp_initialize_timeout: 30,
        kb_exec_enabled: false,
        profile_image_max_data_uri_size: null,
      },
      voice_vision_model: "model-a",
      voice_vision_fallback_model: "model-b",
      tts: { enabled: false, default_voice: "alloy", fallback_voice: "verse" },
      stt: { model: "base", language: "en", auto_update: false },
      hermes: {
        enabled: false,
        model: "hermes3:8b",
        api_server: { enabled: true, port: 8642, model_name: "Hermes Agent" },
        discord: { enabled: true, require_mention: true, free_response_channels: "" },
        photon: { enabled: true, sidecar_port: 8789, sidecar_autostart: true, require_mention: false, mention_patterns: "" },
      },
    },
    read_only: {},
  },
  tailscale: {
    available: false,
    error: null,
    https_url: null,
    management_remote_url: null,
    magic_dns_enabled: false,
    certs_enabled: false,
    open_webui: null,
    management: null,
  },
  jobs: {
    current: null,
    latest: null,
    history: [],
    pending_apply: null,
  },
  meta: {
    generated_at: "2026-06-13T12:00:00Z",
    duration_ms: 4200,
    cache_age_seconds: 12,
    refresh_status: "running",
    errors: ["Docker daemon timed out."],
  },
};

describe("summary api", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    setCsrfToken(null);
  });

  it("posts explicit refresh requests and accepts summary freshness metadata", async () => {
    setCsrfToken("csrf-123");
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify(summaryFixture), {
        status: 202,
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const summary = await refreshSummary();

    const [path, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = init.headers as Headers;
    expect(path).toBe("/api/summary/refresh");
    expect(init.method).toBe("POST");
    expect(headers.get("X-CSRF-Token")).toBe("csrf-123");
    expect(summary.meta?.refresh_status).toBe("running");
    expect(summary.meta?.cache_age_seconds).toBe(12);
  });
});
