import { projectNotation } from "./notation-structure";

export type ChordQuality = { label: string; value: string; aliases: string[] };

// These are authoring choices, not an interval table. The production compiler
// remains the authority for validation and the displayed constituent pitches.
export const QUALITIES: ChordQuality[] = [
  { label: "Major", value: "", aliases: [] },
  { label: "Minor · m", value: "m", aliases: ["min"] },
  { label: "Suspended 2 · sus2", value: "sus2", aliases: [] },
  { label: "Suspended 4 · sus4", value: "sus4", aliases: [] },
  { label: "Diminished · dim", value: "dim", aliases: [] },
  { label: "Augmented · aug", value: "aug", aliases: ["+"] },
  { label: "Dominant 7 · 7", value: "7", aliases: [] },
  { label: "Major 7 · maj7", value: "maj7", aliases: ["M7"] },
  { label: "Minor 7 · m7", value: "m7", aliases: ["min7"] },
  { label: "Minor major 7 · mMaj7", value: "mMaj7", aliases: ["mM7"] },
  { label: "Half-diminished · m7b5", value: "m7b5", aliases: ["ø", "ø7"] },
  { label: "Diminished 7 · dim7", value: "dim7", aliases: [] },
  { label: "Augmented 7 · aug7", value: "aug7", aliases: ["+7"] },
  { label: "Suspended 7 · 7sus4", value: "7sus4", aliases: [] },
  { label: "Major 6 · 6", value: "6", aliases: [] },
  { label: "Minor 6 · m6", value: "m6", aliases: [] },
  { label: "Add 9 · add9", value: "add9", aliases: [] },
  { label: "Dominant 9 · 9", value: "9", aliases: [] },
  { label: "Major 9 · maj9", value: "maj9", aliases: ["M9"] },
  { label: "Minor 9 · m9", value: "m9", aliases: ["min9"] },
];
const QUALITY_SPELLINGS = QUALITIES.flatMap(quality => [quality.value, ...quality.aliases])
  .sort((a, b) => b.length - a.length);
export const ROOTS = ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B"];
export type ChordParts = { root: string; quality: string; octave: string };

export function chordParts(value: string): ChordParts | null {
  if (value.startsWith("{")) return null;
  // Quality precedes accidentals in the engine's grammar: Csus4 is C + sus4,
  // not Cs + us4. Likewise C7 is dominant seventh, whereas C74 has octave 4.
  for (let length = 1; length <= 3; length++) {
    const root = value.slice(0, length);
    if (!/^[A-Ga-g][#sbf]{0,2}$/.test(root)) continue;
    const suffix = value.slice(length);
    for (const quality of QUALITY_SPELLINGS) {
      if (!suffix.startsWith(quality)) continue;
      const octave = suffix.slice(quality.length);
      if (/^\d*$/.test(octave)) return { root, quality, octave };
    }
  }
  return null;
}

/** Return the exact unique MIDI pitches projected for one chord atom. */
export function chordPitches(atom: string): number[] | null {
  if (atom === "~") return [];
  const projection = projectNotation("chord", atom);
  if (projection.error || projection.events.some(event => event.pitch === null)) return null;
  const pitches = [...new Set(projection.events.flatMap(event => event.pitch === null ? [] : [event.pitch]))];
  if (pitches.length === 0 || pitches.some(pitch => !isMidiPitch(pitch))) return null;
  return pitches.sort((left, right) => left - right);
}

const ROOT_PITCH_CLASSES: Record<string, number> = {
  C: 0, "C#": 1, Db: 1, D: 2, "D#": 3, Eb: 3, E: 4, F: 5, "F#": 6, Gb: 6,
  G: 7, "G#": 8, Ab: 8, A: 9, "A#": 10, Bb: 10, B: 11,
};
const compilerTemplates = new Map<string, readonly number[] | null>();

/** Spell an edited pitch set exactly, using braces whenever no supported root-position chord fits. */
export function spellChord(pitches: readonly number[], original: string): string {
  const sorted = [...pitches];
  if (sorted.some(pitch => !isMidiPitch(pitch))) throw new RangeError("Chord pitches must be MIDI integers from 0 to 127");
  sorted.sort((left, right) => left - right);
  for (let index = 1; index < sorted.length; index++) {
    if (sorted[index] === sorted[index - 1]) throw new RangeError("Chord pitches must be unique");
  }
  if (sorted.length === 0) return "~";

  const originalPitches = chordPitches(original);
  if (originalPitches && samePitches(sorted, originalPitches)) return original;

  const flatPreference = /[bf]/i.test(chordParts(original)?.root.slice(1) ?? "");
  // Preserve an authored quality alias during a pure whole-chord transposition.
  const parts = chordParts(original);
  if (parts && originalPitches && originalPitches.length === sorted.length) {
    const shift = sorted[0] - originalPitches[0];
    if (originalPitches.every((pitch, index) => sorted[index] === pitch + shift)) {
      const originalRootPitch = chordRootPitch(parts);
      const shiftedRoot = originalRootPitch === null ? null : originalRootPitch + shift;
      if (shiftedRoot !== null && shiftedRoot >= 12 && isMidiPitch(shiftedRoot)) {
        const retained = spellRoot(parts.root, shiftedRoot, flatPreference) + parts.quality +
          octaveSuffix(parts.quality, shiftedRoot, parts.octave === "");
        if (templateMatches(parts.quality, shiftedRoot, sorted)) return retained;
      }
    }
  }

  for (const rootPitch of sorted) {
    const pc = rootPitch % 12;
    for (const root of rootSpellings(pc, flatPreference)) {
      for (const quality of QUALITIES) {
        const template = qualityTemplate(quality.value);
        if (!template || !samePitches(sorted, template.map(interval => rootPitch + interval))) continue;
        const octave = octaveSuffix(quality.value, rootPitch, parts?.octave === "");
        return rootPitch < 12 ? bracePitches(sorted) : `${root}${quality.value}${octave}`;
      }
    }
  }
  return bracePitches(sorted);
}

function qualityTemplate(quality: string): readonly number[] | null {
  if (!compilerTemplates.has(quality)) {
    const projection = projectNotation("chord", `C${quality}`);
    if (projection.error || projection.events.some(event => event.pitch === null)) {
      compilerTemplates.set(quality, null);
    } else {
      const pitches = [...new Set(projection.events.flatMap(event => event.pitch === null ? [] : [event.pitch]))];
      compilerTemplates.set(quality, pitches.every(isMidiPitch) && pitches.length > 0
        ? pitches.sort((left, right) => left - right).map(pitch => pitch - 60)
        : null);
    }
  }
  return compilerTemplates.get(quality) ?? null;
}

function templateMatches(quality: string, rootPitch: number, pitches: readonly number[]): boolean {
  const template = qualityTemplate(quality);
  return !!template && samePitches(pitches, template.map(interval => rootPitch + interval));
}

function chordRootPitch(parts: ChordParts): number | null {
  if (parts.octave !== "" && !/^0?[0-9]$/.test(parts.octave)) return null;
  const match = /^([A-Ga-g])([#sbf]{0,2})$/.exec(parts.root);
  if (!match) return null;
  const naturalPitchClasses: Record<string, number> = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
  const root = match[1].toUpperCase();
  const alteration = [...match[2].toLowerCase()].reduce(
    (sum, accidental) => sum + (accidental === "#" || accidental === "s" ? 1 : -1), 0,
  );
  const octave = parts.octave === "" ? 4 : Number(parts.octave);
  const pitch = (octave + 1) * 12 + naturalPitchClasses[root] + alteration;
  return isMidiPitch(pitch) ? pitch : null;
}

function rootSpellings(pitchClass: number, flatPreference: boolean): string[] {
  return ROOTS.filter(root => ROOT_PITCH_CLASSES[root] === pitchClass)
    .sort((left, right) => {
      const leftFlat = left.includes("b");
      const rightFlat = right.includes("b");
      return flatPreference ? Number(rightFlat) - Number(leftFlat) : Number(leftFlat) - Number(rightFlat);
    });
}

function spellRoot(originalRoot: string, pitch: number, flatPreference: boolean): string {
  const originalFlat = /[bf]/i.test(originalRoot.slice(1));
  return rootSpellings(pitch % 12, originalFlat || flatPreference)[0];
}

function octaveSuffix(quality: string, rootPitch: number, omitDefaultRegister: boolean): string {
  const octave = String(Math.floor(rootPitch / 12) - 1);
  if (omitDefaultRegister && octave === "4") return "";
  return quality === "" && /^[679]$/.test(octave) ? `0${octave}` : octave;
}

function bracePitches(pitches: readonly number[]): string {
  return `{${pitches.join(",")}}`;
}

function isMidiPitch(pitch: number): boolean {
  return Number.isInteger(pitch) && pitch >= 0 && pitch <= 127;
}

function samePitches(left: readonly number[], right: readonly number[]): boolean {
  return left.length === right.length && left.every((pitch, index) => pitch === right[index]);
}

// Chord tone editing: the decisions behind the tone grid's gestures and buttons.

/** Pointer travel, in CSS pixels, beyond which a tap on an empty row no longer adds a tone. */
const TAP_SLOP_PX = 6;

/** The pitch rows a tone grid shows around `reference` (C to G when empty): two rows of headroom and at least an octave. */
export function toneRows(reference: readonly number[]): { low: number; high: number } {
  let low = Math.max(0, Math.min(...(reference.length ? reference : [60])) - 2);
  let high = Math.min(127, Math.max(...(reference.length ? reference : [67])) + 2);
  if (high - low < 11) { high = Math.min(127, low + 11); low = Math.max(0, high - 11); }
  return { low, high };
}

/** The pitch row `y` pixels below the top of a grid of `rowHeight` rows showing `high` down to `low`. */
export function toneAtY(y: number, rowHeight: number, low: number, high: number): number {
  return Math.max(low, Math.min(high, high - Math.floor(y / rowHeight)));
}

/** The whole semitones a vertical drag from `startY` to `y` covers, upward positive. */
export function rowDelta(startY: number, y: number, rowHeight: number): number {
  return Math.round((startY - y) / rowHeight);
}

/** Whether a press that travelled (`dx`, `dy`) pixels has moved too far to count as a tap. */
export function movedPastTap(dx: number, dy: number): boolean {
  return Math.hypot(dx, dy) > TAP_SLOP_PX;
}

/** `pitches` with tone `index`, or every tone when it is null, moved by `delta` semitones. */
export function shiftTones(pitches: readonly number[], index: number | null, delta: number): number[] {
  return pitches.map((pitch, at) => index === null || at === index ? pitch + delta : pitch);
}

/** The pitch without a tone nearest `anchor`, above before below; null when every MIDI pitch has one. */
export function freePitchNear(anchor: number, pitches: readonly number[]): number | null {
  for (let distance = 1; distance <= 128; distance++)
    for (const pitch of [anchor + distance, anchor - distance])
      if (pitch >= 0 && pitch <= 127 && !pitches.includes(pitch)) return pitch;
  return null;
}

/** Why a set of tones cannot be written, or null when it can. */
export function toneSetError(pitches: readonly number[]): string | null {
  if (pitches.some(pitch => !Number.isInteger(pitch) || pitch < 0 || pitch > 127)) return "Keep tones within MIDI 0–127.";
  if (new Set(pitches).size !== pitches.length) return "That pitch already has a tone. Move to an empty row.";
  return null;
}
