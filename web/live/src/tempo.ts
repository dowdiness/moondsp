const DECIMAL_NUMBER = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/;
const RUNTIME_MINIMUM = 0.001;
const RUNTIME_MAXIMUM = 1000;
const EMPTY_MESSAGE = "Enter a tempo.";
const INVALID_MESSAGE = "Enter a finite decimal tempo no greater than 1000 BPM.";

/** A validated scheduler tempo in beats per minute. */
export class Tempo {
  static readonly DEFAULT = new Tempo(60);
  // Manual entry retains the live editor's one-BPM lower clamp.
  static readonly MINIMUM = new Tempo(1);

  // Private state makes Tempo nominal: `{ value: number }` is not a Tempo.
  private constructor(private readonly bpm: number) {}

  public get value(): number {
    return this.bpm;
  }

  /** Decode a value received across a typed boundary. */
  static decode(value: unknown): Tempo | null {
    if (typeof value !== "number" || !Number.isFinite(value) ||
        value < RUNTIME_MINIMUM || value > RUNTIME_MAXIMUM) {
      return null;
    }
    return new Tempo(value);
  }

  /** Parse the complete user input, normalizing finite values below one BPM. */
  static parseInput(
    text: string,
  ): { kind: "parsed"; tempo: Tempo } | { kind: "empty" } | { kind: "invalid"; message: string } {
    const input = text.trim();
    if (input === "") return { kind: "empty" };
    if (!DECIMAL_NUMBER.test(input)) return { kind: "invalid", message: INVALID_MESSAGE };

    const value = Number(input);
    if (!Number.isFinite(value) || value > RUNTIME_MAXIMUM) return { kind: "invalid", message: INVALID_MESSAGE };
    return { kind: "parsed", tempo: new Tempo(Math.max(Tempo.MINIMUM.value, value)) };
  }
}

export type TempoField =
  | Readonly<{ kind: "displaying"; tempo: Tempo }>
  | Readonly<{ kind: "editing"; committed: Tempo; text: string }>;

type CommitTempoResult =
  | Readonly<{ kind: "committed"; field: TempoField; tempo: Tempo }>
  | Readonly<{ kind: "restored"; field: TempoField; reason: "empty" | "invalid"; message: string }>;

export function committedTempo(field: TempoField): Tempo {
  switch (field.kind) {
    case "displaying":
      return field.tempo;
    case "editing":
      return field.committed;
  }
}

export function tempoText(field: TempoField): string {
  switch (field.kind) {
    case "displaying":
      return String(field.tempo.value);
    case "editing":
      return field.text;
  }
}

export function editTempo(field: TempoField, text: string): TempoField {
  return { kind: "editing", committed: committedTempo(field), text };
}

export function receiveTempo(field: TempoField, tempo: Tempo): TempoField {
  return committedTempo(field).value === tempo.value
    ? field
    : { kind: "displaying", tempo };
}

export function commitTempo(field: TempoField): CommitTempoResult {
  switch (field.kind) {
    case "displaying":
      return { kind: "committed", field, tempo: field.tempo };
    case "editing": {
      const parsed = Tempo.parseInput(field.text);
      switch (parsed.kind) {
        case "parsed":
          return {
            kind: "committed",
            field: { kind: "displaying", tempo: parsed.tempo },
            tempo: parsed.tempo,
          };
        case "empty":
          return {
            kind: "restored",
            field: { kind: "displaying", tempo: field.committed },
            reason: "empty",
            message: EMPTY_MESSAGE,
          };
        case "invalid":
          return {
            kind: "restored",
            field: { kind: "displaying", tempo: field.committed },
            reason: "invalid",
            message: parsed.message,
          };
      }
    }
  }
}
