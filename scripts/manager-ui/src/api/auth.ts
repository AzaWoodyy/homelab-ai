import { apiJson, setCsrfToken } from "./client";
import { sessionSchema, type Session } from "./schemas";

export async function getSession(): Promise<Session> {
  const session = await apiJson("/api/auth/session", sessionSchema);
  setCsrfToken(session.csrf_token);
  return session;
}

export async function login(secret: string): Promise<Session> {
  const session = await apiJson(
    "/api/auth/login",
    sessionSchema,
    {
      method: "POST",
      body: JSON.stringify({ secret }),
    },
  );
  setCsrfToken(session.csrf_token);
  return session;
}

export async function logout(): Promise<void> {
  await apiJson("/api/auth/logout", sessionSchema.pick({ ok: true }), {
    method: "POST",
    body: "{}",
  });
  setCsrfToken(null);
}
