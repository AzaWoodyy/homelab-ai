import { apiPost } from "./client";
import { actionResponseSchema } from "./schemas";

export type ManagerAction =
  | "start"
  | "stop"
  | "setup"
  | "test"
  | "refresh-models"
  | "hermes-start"
  | "hermes-stop"
  | "hermes-restart"
  | "sleep"
  | "shutdown"
  | "manager-restart"
  | "manager-stop";

export function runAction(action: ManagerAction): Promise<{ accepted: boolean; job: unknown }> {
  return apiPost(`/api/actions/${action}`, actionResponseSchema);
}
