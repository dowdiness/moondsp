import {
  create_draft as createDraft,
  draft_state as draftState,
  edit_draft as editDraft,
  prepare_playback as preparePlayback,
  dispose_draft as disposeDraft,
  type DraftHandle,
} from "./generated/authoring.js";

export type DraftVersion = readonly [number, number];
export type DraftState = Readonly<{ text: string; version: DraftVersion; diagnostic: string | null }>;
export type DraftEdit = Readonly<{ from: number; to: number; inserted: string }>;

export function decodeDraftVersion(value: unknown): DraftVersion | null {
  if (!Array.isArray(value) || value.length !== 2 ||
      !Number.isSafeInteger(value[0]) || value[0] <= 0 ||
      !Number.isSafeInteger(value[1]) || value[1] < 0) return null;
  return Object.freeze([value[0], value[1]]) as DraftVersion;
}

export function sameDraftVersion(left: DraftVersion | null, right: DraftVersion | null): boolean {
  return left === null || right === null ? left === right : left[0] === right[0] && left[1] === right[1];
}

function decodeState(raw: { text: string; version: unknown; diagnostic: string | null }): DraftState {
  const version = decodeDraftVersion(raw.version);
  if (!version || typeof raw.text !== "string" || (raw.diagnostic !== null && typeof raw.diagnostic !== "string")) {
    throw new Error("invalid authoring state");
  }
  return Object.freeze({ text: raw.text, version, diagnostic: raw.diagnostic });
}

let inputFromDraft: (wire: string, state: DraftState) => PlaybackInput;

/** Immutable capability; only Draft preparation or deliberate text input can create it. */
export class PlaybackInput {
  private constructor(private readonly encoded: string, readonly source: string, readonly draftVersion: DraftVersion | null) {
    Object.freeze(this);
  }
  get wire(): string { return this.encoded; }
  static {
    inputFromDraft = (wire, state) => new PlaybackInput(wire, state.text, state.version);
  }
  static text(source: string): PlaybackInput {
    return new PlaybackInput(JSON.stringify({ schema: 1, kind: "text", text: source }), source, null);
  }
}

/** Main-thread ownership, independent of AudioContext and playback-run lifetime. */
export class Draft {
  private readonly handle: DraftHandle;
  private disposed = false;
  constructor(text: string) {
    let handle: DraftHandle | undefined;
    createDraft(text, created => { handle = created; }, message => { throw new Error(message); });
    if (!handle) throw new Error("authoring constructor did not return a Draft");
    this.handle = handle;
  }
  state(): DraftState {
    if (this.disposed) throw new Error("Draft is disposed");
    return decodeState(JSON.parse(draftState(this.handle)));
  }
  edit(transaction: Readonly<{ base: DraftVersion; edits: readonly DraftEdit[] }>): DraftState {
    if (this.disposed) throw new Error("Draft is disposed");
    const result = JSON.parse(editDraft(this.handle, JSON.stringify(transaction)));
    if (!result.ok) throw new Error(result.message);
    return decodeState(result.state);
  }
  prepare(): PlaybackInput {
    if (this.disposed) throw new Error("Draft is disposed");
    const result = JSON.parse(preparePlayback(this.handle));
    if (!result.ok) throw new Error(result.message);
    return inputFromDraft(result.input, this.state());
  }
  dispose(): void {
    if (!this.disposed) {
      disposeDraft(this.handle);
      this.disposed = true;
    }
  }
}
