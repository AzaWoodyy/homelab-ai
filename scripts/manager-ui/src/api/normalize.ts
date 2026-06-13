export function listify<T = unknown>(value: unknown): T[] {
  if (Array.isArray(value)) return value as T[];
  if (value == null) return [];
  if (typeof value === "string") return value ? ([value] as T[]) : [];

  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    const numericKeys = Object.keys(record)
      .filter((key) => /^\d+$/.test(key))
      .sort((a, b) => Number(a) - Number(b));

    if (numericKeys.length > 0) {
      return numericKeys.map((key) => record[key] as T);
    }

    return Object.values(record).filter((item) => item != null) as T[];
  }

  return [value as T];
}

export function nullableString(value: unknown): string | null {
  if (value == null || value === "") return null;
  return String(value);
}
