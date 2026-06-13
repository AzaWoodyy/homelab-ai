import { apiPut } from "./client";
import { modelSaveResponseSchema, type ModelSaveResponse } from "./schemas";

export function saveModels(models: string[], uninstallRemoved: boolean): Promise<ModelSaveResponse> {
  return apiPut("/api/models", modelSaveResponseSchema, {
    models,
    uninstall_removed: uninstallRemoved,
  });
}
