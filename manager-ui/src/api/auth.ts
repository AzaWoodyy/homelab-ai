import { apiGet, apiPost, setCsrfToken } from "./client";
import { sessionSchema, type Session } from "./schemas";

export async function getSession(): Promise<Session> {
  const session = await apiGet("/api/auth/session", sessionSchema);
  setCsrfToken(session.csrf_token);
  return session;
}

export async function login(secret: string): Promise<Session> {
  const session = await apiPost("/api/auth/login", sessionSchema, { secret });
  setCsrfToken(session.csrf_token);
  return session;
}

export async function logout(): Promise<void> {
  await apiPost("/api/auth/logout", sessionSchema.pick({ ok: true }));
  setCsrfToken(null);
}
