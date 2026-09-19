export interface Note {
  readonly midi: number;
  readonly name: string;
  readonly computerKey: string;
  readonly black: boolean;
}

/** Single source for the C4–C5 monophonic keyboard. */
export const NOTES: readonly Note[] = [
  { midi: 60, name: "C4", computerKey: "A", black: false },
  { midi: 61, name: "C♯4", computerKey: "W", black: true },
  { midi: 62, name: "D4", computerKey: "S", black: false },
  { midi: 63, name: "D♯4", computerKey: "E", black: true },
  { midi: 64, name: "E4", computerKey: "D", black: false },
  { midi: 65, name: "F4", computerKey: "F", black: false },
  { midi: 66, name: "F♯4", computerKey: "T", black: true },
  { midi: 67, name: "G4", computerKey: "G", black: false },
  { midi: 68, name: "G♯4", computerKey: "Y", black: true },
  { midi: 69, name: "A4", computerKey: "H", black: false },
  { midi: 70, name: "A♯4", computerKey: "U", black: true },
  { midi: 71, name: "B4", computerKey: "J", black: false },
  { midi: 72, name: "C5", computerKey: "K", black: false },
];

export const NOTE_BY_MIDI = new Map(NOTES.map(note => [note.midi, note]));
export const MIDI_BY_KEY = new Map(NOTES.map(note => [note.computerKey.toLowerCase(), note.midi]));

export function noteAriaLabel(note: Note): string {
  return `${note.name.replace("♯", " sharp ")}, computer key ${note.computerKey}`;
}

export function activeNoteName(activeMidi: number | null): string {
  return activeMidi === null ? "—" : NOTE_BY_MIDI.get(activeMidi)?.name ?? "—";
}

export function noteDescription(
  midi: number,
  activeMidi: number | null,
  heldMidis: ReadonlySet<number>,
): string {
  if (activeMidi === midi) return "Active note";
  return heldMidis.has(midi) ? "Held; another note is active" : "Hold to play";
}
