import { afterEach, describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { ApiError, apiJson, apiPost, apiPut, setCsrfToken } from "./client";

describe("apiJson", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    setCsrfToken(null);
  });

  it("sends the CSRF token on mutating requests", async () => {
    setCsrfToken("csrf-123");
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await apiJson("/api/config", z.object({ ok: z.boolean() }), {
      method: "PUT",
      body: "{}",
    });

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = init.headers as Headers;
    expect(headers.get("X-CSRF-Token")).toBe("csrf-123");
    expect(init.credentials).toBe("same-origin");
  });

  it("does not send CSRF on reads", async () => {
    setCsrfToken("csrf-123");
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await apiJson("/api/summary", z.object({ ok: z.boolean() }));

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = init.headers as Headers;
    expect(headers.get("X-CSRF-Token")).toBeNull();
  });

  it("centralizes JSON request bodies for mutating helpers", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await apiPost("/api/auth/login", z.object({ ok: z.boolean() }), { secret: "test-secret" });

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = init.headers as Headers;
    expect(init.method).toBe("POST");
    expect(headers.get("Content-Type")).toBe("application/json");
    expect(init.body).toBe(JSON.stringify({ secret: "test-secret" }));
  });

  it("uses the same JSON handling for PUT helpers", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ saved: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await apiPut("/api/config", z.object({ saved: z.boolean() }), { value: "updated" });

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(init.method).toBe("PUT");
    expect(init.body).toBe(JSON.stringify({ value: "updated" }));
  });

  it("turns failed JSON responses into ApiError instances", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: "forbidden", message: "Nope" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(apiJson("/api/config", z.object({ ok: z.boolean() }))).rejects.toMatchObject({
      name: "ApiError",
      message: "Nope",
      status: 403,
      code: "forbidden",
    } satisfies Partial<ApiError>);
  });
});
