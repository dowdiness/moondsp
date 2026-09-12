import { Tempo } from "./tempo";

export type PlaybackMode = "pattern" | "song";

/** Nonempty source, not a successfully parsed or accepted score. MoonBit owns syntax. */
export class ScoreSource {
  private constructor(readonly mode: PlaybackMode, private readonly source: string) {}

  get text(): string { return this.source; }

  static parse(mode: PlaybackMode, text: string): Draft {
    return text.trim() === ""
      ? { kind: "empty", mode, text }
      : { kind: "score", score: new ScoreSource(mode, text) };
  }
}

export type Draft =
  | { readonly kind: "empty"; readonly mode: PlaybackMode; readonly text: string }
  | { readonly kind: "score"; readonly score: ScoreSource };

export class RequestId {
  private constructor(private readonly serial: number) {}

  get value(): number { return this.serial; }

  static decode(value: unknown): RequestId | null {
    return typeof value === "number" && Number.isSafeInteger(value) && value > 0
      ? new RequestId(value) : null;
  }

  static first(): RequestId { return new RequestId(1); }

  next(): RequestId {
    if (this.value === Number.MAX_SAFE_INTEGER) throw new Error("Playback request IDs exhausted");
    return new RequestId(this.value + 1);
  }
}

export type ScoreRequest = Readonly<{
  id: RequestId;
  score: ScoreSource;
  policy: "continue" | "restart";
}>;

export type PlaybackReceipt =
  | Readonly<{ kind: "accepted"; id: RequestId; mode: PlaybackMode;
      operation: "update" | "restart"; tempo: Tempo; tempoRevision: RequestId | null;
      samplePosition: number; acceptedAtSample: number }>
  | Readonly<{ kind: "rejected"; id: RequestId; message: string; recovery: "edit" | "restart" }>
  | Readonly<{ kind: "superseded"; id: RequestId }>;

export type TempoReceipt =
  | Readonly<{ kind: "accepted"; id: RequestId; tempo: Tempo }>
  | Readonly<{ kind: "rejected"; id: RequestId; tempo: Tempo; message: string }>;

export type WorkletMessage =
  | { kind: "ready" }
  | { kind: "receipt"; receipt: PlaybackReceipt }
  | { kind: "tempo"; receipt: TempoReceipt }
  | { kind: "runtime-error"; message: string }
  | { kind: "notice"; data: Readonly<Record<string, unknown>> }
  | { kind: "protocol-error"; message: string };

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function sample(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

/** The sole untrusted-message decoder. No partial replies enter playback state. */
export function decodeWorkletMessage(value: unknown): WorkletMessage {
  if (!record(value)) return { kind: "protocol-error", message: "Worklet message must be an object" };
  switch (value.type) {
    case "ready": return { kind: "ready" };
    case "error":
      return typeof value.message === "string"
        ? { kind: "runtime-error", message: value.message }
        : { kind: "protocol-error", message: "Worklet error lacks a message" };
    case "pattern-updated":
    case "song-updated": {
      const id = RequestId.decode(value.revision);
      const tempo = Tempo.decode(value.tempo);
      const tempoRevision = value.tempoRevision === null ? null : RequestId.decode(value.tempoRevision);
      if (id === null || tempo === null || (value.tempoRevision !== null && tempoRevision === null) ||
          (value.operation !== "update" && value.operation !== "restart") ||
          !sample(value.samplePosition) || !sample(value.acceptedAtSample)) {
        return { kind: "protocol-error", message: "Malformed playback acceptance" };
      }
      return { kind: "receipt", receipt: {
        kind: "accepted", id, tempo, tempoRevision,
        mode: value.type === "pattern-updated" ? "pattern" : "song",
        operation: value.operation, samplePosition: value.samplePosition,
        acceptedAtSample: value.acceptedAtSample,
      } };
    }
    case "tempo-updated":
    case "tempo-error": {
      const id = RequestId.decode(value.revision);
      const tempo = Tempo.decode(value.tempo);
      if (id === null || tempo === null) {
        return { kind: "protocol-error", message: "Malformed tempo acknowledgement" };
      }
      if (value.type === "tempo-updated") {
        return { kind: "tempo", receipt: { kind: "accepted", id, tempo } };
      }
      return typeof value.message === "string"
        ? { kind: "tempo", receipt: { kind: "rejected", id, tempo, message: value.message } }
        : { kind: "protocol-error", message: "Tempo rejection lacks a message" };
    }
    case "pattern-error":
    case "song-error":
    case "playback-error": {
      const id = RequestId.decode(value.revision);
      if (id === null || typeof value.message !== "string" ||
          (value.recovery !== "edit" && value.recovery !== "restart")) {
        return { kind: "protocol-error", message: "Malformed playback rejection" };
      }
      return { kind: "receipt", receipt: { kind: "rejected", id, message: value.message,
        recovery: value.recovery } };
    }
    case "playback-superseded": {
      const id = RequestId.decode(value.revision);
      return id === null
        ? { kind: "protocol-error", message: "Malformed superseded request" }
        : { kind: "receipt", receipt: { kind: "superseded", id } };
    }
    case "debug":
    case "telemetry":
    case "scheduler-timing":
      return { kind: "notice", data: value };
    default:
      return { kind: "protocol-error", message: `Unexpected worklet message: ${String(value.type)}` };
  }
}
