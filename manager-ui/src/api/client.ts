import { z } from "zod";

let csrfToken: string | null = null;
const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly code?: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export function setCsrfToken(token: string | null): void {
  csrfToken = token;
}

function jsonRequest(method: "POST" | "PUT", body: unknown = {}): RequestInit {
  return {
    method,
    body: JSON.stringify(body),
  };
}

async function parseResponse(response: Response): Promise<unknown> {
  const contentType = response.headers.get("Content-Type") ?? "";

  if (!contentType.includes("application/json")) {
    return null;
  }

  return response.json();
}

export async function apiJson<T>(
  path: string,
  schema: z.Schema<T>,
  options: RequestInit = {},
): Promise<T> {
  const method = (options.method ?? "GET").toUpperCase();
  const headers = new Headers(options.headers);

  if (!headers.has("Content-Type") && method !== "GET" && method !== "HEAD") {
    headers.set("Content-Type", "application/json");
  }

  if (!SAFE_METHODS.has(method) && csrfToken) {
    headers.set("X-CSRF-Token", csrfToken);
  }

  const response = await fetch(path, {
    credentials: "same-origin",
    ...options,
    method,
    headers,
  });

  const body = await parseResponse(response);

  if (!response.ok) {
    const record = body && typeof body === "object" ? (body as Record<string, unknown>) : {};
    throw new ApiError(
      String(record.message ?? `Request failed (${response.status})`),
      response.status,
      record.error ? String(record.error) : undefined,
    );
  }

  return schema.parse(body);
}

export function apiGet<T>(path: string, schema: z.Schema<T>): Promise<T> {
  return apiJson(path, schema);
}

export function apiPost<T>(path: string, schema: z.Schema<T>, body?: unknown): Promise<T> {
  return apiJson(path, schema, jsonRequest("POST", body));
}

export function apiPut<T>(path: string, schema: z.Schema<T>, body?: unknown): Promise<T> {
  return apiJson(path, schema, jsonRequest("PUT", body));
}
