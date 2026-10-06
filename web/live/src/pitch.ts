const SHARP_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const FLAT_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];

export function midiValue(value: string): { midi: number; numeric: boolean; flat: boolean } | null {
  if (/^-?(?:\d+(?:\.\d*)?|\.\d+)$/.test(value)) {
    const midi = Number(value);
    return Number.isFinite(midi) && midi >= 0 && midi <= 127
      ? { midi, numeric: true, flat: false } : null;
  }
  const match = /^([A-Ga-g])([#sbf]{0,2})(-?\d*)$/.exec(value);
  if (!match) return null;
  const letter = match[1].toUpperCase();
  const base = ({ C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 } as Record<string, number>)[letter];
  const accidentals = match[2].toLowerCase();
  if (accidentals.length === 2 && (accidentals[0] === "b" || accidentals[0] === "f") !==
      (accidentals[1] === "b" || accidentals[1] === "f")) return null;
  let delta = 0;
  for (const accidental of accidentals) {
    if (accidental === "#" || accidental === "s") delta++;
    else delta--;
  }
  const octaveText = match[3];
  if (octaveText === "-") return null;
  const octave = octaveText === "" ? 4 : Number(octaveText);
  const midi = (octave + 1) * 12 + base + delta;
  return Number.isInteger(midi) && midi >= 0 && midi <= 127
    ? { midi, numeric: false, flat: accidentals.includes("b") || accidentals.includes("f") } : null;
}

/** Transpose one Mini note atom by semitones; invalid or out-of-range notes return null. */
export function transposePitch(value: string, semitones: number): string | null {
  if (!Number.isInteger(semitones)) return null;
  const parsed = midiValue(value);
  if (!parsed) return null;
  const midi = parsed.midi + semitones;
  if (!Number.isFinite(midi) || midi < 0 || midi > 127) return null;
  if (parsed.numeric) return String(midi);
  const octave = Math.floor(midi / 12) - 1;
  const pitchClass = midi % 12;
  return `${(parsed.flat ? FLAT_NAMES : SHARP_NAMES)[pitchClass]}${octave}`;
}
