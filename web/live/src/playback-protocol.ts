export class RequestId {
  private constructor(readonly value: number) {}
  static first(): RequestId { return new RequestId(1); }
  static decode(value: unknown): RequestId | null {
    return typeof value === "number" && Number.isSafeInteger(value) && value > 0 ? new RequestId(value) : null;
  }
  next(): RequestId {
    if (this.value === Number.MAX_SAFE_INTEGER) throw new RangeError("request id exhausted");
    return new RequestId(this.value + 1);
  }
}

export type PlayerOperation = "update" | "restart" | "play" | "pause";
export type PlayState = "Empty" | "Ready" | "Playing" | "Paused" | "Ended" | "Fault";
export type PlayerSnapshot = Readonly<{
  state: PlayState;
  samplePosition: number;
  tempo: number;
  pendingCount: number;
  skippedCount: number;
}>;
export type PlayerReceipt = PlayerSnapshot & Readonly<{ id: RequestId; operation: PlayerOperation }> & (
  | Readonly<{ kind: "accepted" }>
  | Readonly<{ kind: "rejected"; restartRequired: boolean; message: string }>
);
export type WorkletMessage =
  | { kind: "ready" }
  | { kind: "receipt"; receipt: PlayerReceipt }
  | ({ kind: "status" } & PlayerSnapshot)
  | { kind: "runtime-error"; message: string }
  | { kind: "notice"; data: Readonly<Record<string, unknown>> }
  | { kind: "protocol-error"; message: string };

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function count(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}
function tempo(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0.001 && value <= 1000;
}
function operation(value: unknown): value is PlayerOperation {
  return value === "update" || value === "restart" || value === "play" || value === "pause";
}
function snapshot(value: Record<string, unknown>): PlayerSnapshot | null {
  const states: readonly PlayState[] = ["Empty", "Ready", "Playing", "Paused", "Ended", "Fault"];
  const state = count(value.state) ? states[value.state] : undefined;
  if (!state || !count(value.samplePosition) || !tempo(value.tempo) || !count(value.pendingCount) || !count(value.skippedCount)) return null;
  return { state, samplePosition: value.samplePosition, tempo: value.tempo, pendingCount: value.pendingCount, skippedCount: value.skippedCount };
}

export function decodeWorkletMessage(value: unknown): WorkletMessage {
  if (!record(value)) return { kind: "protocol-error", message: "worklet reply is not an object" };
  if (value.type === "ready") return { kind: "ready" };
  if (value.type === "error" && typeof value.message === "string") return { kind: "runtime-error", message: value.message };
  if (value.type === "player-status") {
    const view = snapshot(value);
    return view ? { kind: "status", ...view } : { kind: "protocol-error", message: "invalid player status" };
  }
  if (value.type === "player-receipt") {
    const id = RequestId.decode(value.id);
    const view = snapshot(value);
    if (!id || !view || !operation(value.operation) || typeof value.accepted !== "boolean") return { kind: "protocol-error", message: "invalid player receipt" };
    const base = { ...view, id, operation: value.operation };
    if (value.accepted) return { kind: "receipt", receipt: { ...base, kind: "accepted" } };
    if (typeof value.restartRequired !== "boolean" || typeof value.message !== "string") return { kind: "protocol-error", message: "invalid rejection receipt" };
    return { kind: "receipt", receipt: { ...base, kind: "rejected", restartRequired: value.restartRequired, message: value.message } };
  }
  // Compiled-engine diagnostics are not Player state changes.
  if (value.type === "telemetry" || value.type === "scheduler-timing") return { kind: "notice", data: value };
  return { kind: "protocol-error", message: "unknown worklet message" };
}
