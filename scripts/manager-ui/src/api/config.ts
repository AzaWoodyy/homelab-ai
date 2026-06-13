import { apiJson } from "./client";
import { configResponseSchema, type ConfigResponse, type EditableConfig } from "./schemas";

export function getConfig(): Promise<ConfigResponse> {
  return apiJson("/api/config", configResponseSchema);
}

export function saveConfig(config: EditableConfig): Promise<ConfigResponse> {
  return apiJson("/api/config", configResponseSchema, {
    method: "PUT",
    body: JSON.stringify(config),
  });
}
