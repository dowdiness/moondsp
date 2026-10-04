import type { SyntaxNode, Tree } from "@lezer/common";

const SHARP_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const FLAT_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];
const DRUMS: Record<string, true> = { bd: true, sd: true, hh: true, cp: true, oh: true };

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

function hasError(node: SyntaxNode): boolean {
  let broken = false;
  node.toTree().iterate({ enter(ref) { if (ref.type.isError) broken = true; } });
  return broken;
}

function directChildren(node: SyntaxNode): SyntaxNode[] {
  const children: SyntaxNode[] = [];
  for (let child = node.firstChild; child; child = child.nextSibling) children.push(child);
  return children;
}

function parseSelectedAtom(atom: string, callName: string): boolean {
  if (callName === "s") return DRUMS[atom] === true;
  if (callName !== "note") return false;
  return midiValue(atom) !== null;
}

/**
 * Build a one-step phrase from the original declarations and the selected chain.
 * It intentionally excludes unrelated performance lines and their wrappers.
 */
export function auditionSource(doc: string, patternFrom: number, stepFrom: number, tree: Tree): string | null {
  if (!Number.isInteger(patternFrom) || !Number.isInteger(stepFrom) || patternFrom < 0 || stepFrom < 0 ||
      patternFrom > doc.length || stepFrom > doc.length) return null;
  const program = tree.topNode;
  if (program.name !== "Program") return null;
  const topLevel = directChildren(program);
  const matches: SyntaxNode[] = [];
  tree.iterate({ enter(ref) {
    if (ref.name === "Chain" && ref.from === patternFrom) matches.push(ref.node);
  } });
  if (matches.length !== 1) return null;
  const chain = matches[0];
  if (!chain || hasError(chain)) return null;
  const call = directChildren(chain).find(node => node.name === "Call");
  if (!call || hasError(call)) return null;
  const callName = call.getChild("CallName");
  const args = call.getChild("Args");
  if (!callName || !args) return null;
  const name = doc.slice(callName.from, callName.to);
  const argsChildren = directChildren(args).filter(node => node.name !== "LineComment" && node.name !== "BlockComment");
  if (argsChildren.length !== 3 || argsChildren[0].name !== "(" || argsChildren[1].name !== "String" || argsChildren[2].name !== ")") return null;
  const string = argsChildren[1];
  const raw = doc.slice(string.from, string.to);
  if (raw.length < 2 || raw[0] !== '"' || raw[raw.length - 1] !== '"') return null;
  const bodyStart = string.from + 1;
  const body = raw.slice(1, -1);
  const token = /[^\s]+/gu;
  let match: RegExpExecArray | null;
  while ((match = token.exec(body))) {
    const tokenFrom = bodyStart + match.index;
    if (tokenFrom !== stepFrom) continue;
    const atom = match[0];
    if (atom === "~" || !parseSelectedAtom(atom, name)) return null;
    const chainText = doc.slice(chain.from, chain.to);
    const localFrom = string.from - chain.from + 1;
    const localTo = string.to - chain.from - 1;
    const previewChain = chainText.slice(0, localFrom) + atom + chainText.slice(localTo);
    const declarations = topLevel.filter(node => node.name === "Binding" || node.name === "Declaration");
    if (declarations.some(hasError)) return null;
    return [...declarations.map(node => doc.slice(node.from, node.to)), previewChain].join("\n");
  }
  return null;
}
