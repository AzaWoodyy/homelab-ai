import { afterEach, describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { apiJson, setCsrfToken } from "./client";

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
});
