import { decodeDraftVersion, type DraftVersion } from "./authoring";
const PLAY_STATES = ["Empty", "Ready", "Playing", "Paused", "Ended", "Fault"] as const;
const PLAY_MODES = ["none", "pattern", "song"] as const;


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
export type PlayerMode = "none" | "pattern" | "song";
export type PlayerSnapshot = Readonly<{
  state: PlayState;
  mode: PlayerMode;
  cyclePosition: number;
  samplePosition: number;
  tempo: number;
  pendingCount: number;
  skippedCount: number;
}>;
export type PlayerReceipt = PlayerSnapshot & Readonly<{ id: RequestId; operation: PlayerOperation; draftVersion: DraftVersion | null }> & (
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
function cyclePosition(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}
function playState(value: unknown): value is PlayState {
  return typeof value === "string" && (PLAY_STATES as readonly string[]).includes(value);
}
function mode(value: unknown): value is PlayerMode {
  return typeof value === "string" && (PLAY_MODES as readonly string[]).includes(value);
}
function operation(value: unknown): value is PlayerOperation {
  return value === "update" || value === "restart" || value === "play" || value === "pause";
}
function snapshot(value: Record<string, unknown>): PlayerSnapshot | null {
  if (!playState(value.state) || !mode(value.mode) || !cyclePosition(value.cyclePosition) || !count(value.samplePosition) ||
      !tempo(value.tempo) || !count(value.pendingCount) || !count(value.skippedCount)) return null;
  return { state: value.state, mode: value.mode, cyclePosition: value.cyclePosition, samplePosition: value.samplePosition,
    tempo: value.tempo, pendingCount: value.pendingCount, skippedCount: value.skippedCount };
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
    const version = value.draftVersion === null ? null : decodeDraftVersion(value.draftVersion);
    if (!id || !view || !operation(value.operation) || typeof value.accepted !== "boolean" ||
        (value.draftVersion !== null && version === null) ||
        ((value.operation === "play" || value.operation === "pause") && version !== null)) {
      return { kind: "protocol-error", message: "invalid player receipt" };
    }
    const base = { ...view, id, operation: value.operation, draftVersion: version };
    if (value.accepted) return { kind: "receipt", receipt: { ...base, kind: "accepted" } };
    if (typeof value.restartRequired !== "boolean" || typeof value.message !== "string") return { kind: "protocol-error", message: "invalid rejection receipt" };
    return { kind: "receipt", receipt: { ...base, kind: "rejected", restartRequired: value.restartRequired, message: value.message } };
  }
  // Compiled-engine diagnostics are not Player state changes.
  if (value.type === "telemetry" || value.type === "scheduler-timing") return { kind: "notice", data: value };
  return { kind: "protocol-error", message: "unknown worklet message" };
}
