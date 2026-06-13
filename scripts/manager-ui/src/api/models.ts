import { apiJson } from "./client";
import { modelSaveResponseSchema, modelsResponseSchema, type ModelSaveResponse, type ModelsResponse } from "./schemas";

export function getModels(): Promise<ModelsResponse> {
  return apiJson("/api/models", modelsResponseSchema);
}

export function saveModels(models: string[], uninstallRemoved: boolean): Promise<ModelSaveResponse> {
  return apiJson("/api/models", modelSaveResponseSchema, {
    method: "PUT",
    body: JSON.stringify({
      models,
      uninstall_removed: uninstallRemoved,
    }),
  });
}
