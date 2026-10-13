export type DraftVersion = readonly [number, number];

export function decodeDraftVersion(value: unknown): DraftVersion | null {
  if (!Array.isArray(value) || value.length !== 2 ||
      !Number.isSafeInteger(value[0]) || value[0] <= 0 ||
      !Number.isSafeInteger(value[1]) || value[1] < 0) return null;
  return Object.freeze([value[0], value[1]]) as DraftVersion;
}

export function sameDraftVersion(left: DraftVersion | null, right: DraftVersion | null): boolean {
  return left === null || right === null ? left === right : left[0] === right[0] && left[1] === right[1];
}
