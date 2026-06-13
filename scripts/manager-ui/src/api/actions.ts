import { apiJson } from "./client";
import { actionResponseSchema } from "./schemas";

export type ManagerAction =
  | "start"
  | "stop"
  | "setup"
  | "test"
  | "refresh-models"
  | "sleep"
  | "shutdown"
  | "manager-restart"
  | "manager-stop";

export function runAction(action: ManagerAction): Promise<{ accepted: boolean; job: unknown }> {
  return apiJson(`/api/actions/${action}`, actionResponseSchema, {
    method: "POST",
    body: "{}",
  });
}
