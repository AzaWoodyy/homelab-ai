import { apiPut } from "./client";
import { configResponseSchema, type ConfigResponse, type EditableConfig } from "./schemas";

export function saveConfig(config: EditableConfig): Promise<ConfigResponse> {
  return apiPut("/api/config", configResponseSchema, config);
}
