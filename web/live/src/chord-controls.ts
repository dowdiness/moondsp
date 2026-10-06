import { chordParts, chordPitches, spellChord, QUALITIES, ROOTS, type ChordParts } from "./chord-model";
import { mountChordToneEditor } from "./chord-tone-editor";
import { transposePitch } from "./pitch";
import "./chord-controls.css";


export function mountChordControls(container: HTMLElement, change: (value: string) => boolean, measure: () => void): {
  update: (value: string | null, restSeed: string, doc: unknown, from: number) => void;
  dispose: () => void;
} {
  container.className = "chord-controls";
  container.setAttribute("role", "group");
  const direct = document.createElement("div");
  let atom: string | null = null;
  let current: ChordParts | null = null;
  const editor = mountChordToneEditor(direct, pitches => {
    if (atom === null) return false;
    try { return change(spellChord(pitches, atom)); }
    catch (error) { feedback.textContent = error instanceof Error ? error.message : String(error); return false; }
  });
  const named = document.createElement("details");
  named.className = "chord-controls__named";
  const summary = document.createElement("summary");
  summary.textContent = "Choose by chord name";
  const fields = document.createElement("div");
  fields.className = "chord-controls__fields";
  const root = document.createElement("select");
  root.setAttribute("aria-label", "Chord root");
  for (const value of ROOTS) root.add(new Option(value, value));
  const quality = document.createElement("select");
  quality.setAttribute("aria-label", "Chord type");
  for (const item of QUALITIES) quality.add(new Option(item.label, item.value));
  const rootLabel = document.createElement("label");
  rootLabel.append("Root ", root);
  const qualityLabel = document.createElement("label");
  qualityLabel.append("Type ", quality);
  const tones = document.createElement("output");
  tones.className = "chord-controls__tones";
  tones.setAttribute("aria-label", "Chord tones");
  const feedback = document.createElement("span");
  feedback.className = "step-feedback";
  feedback.setAttribute("role", "status");
  fields.append(rootLabel, qualityLabel);
  named.append(summary, fields);
  container.append(direct, named, tones, feedback);
  named.addEventListener("toggle", measure);
  function retainSpelling(select: HTMLSelectElement, value: string, label = value): void {
    select.querySelector("option[data-current]")?.remove();
    if (![...select.options].some(option => option.value === value)) {
      const option = new Option(label, value);
      option.dataset.current = "true";
      select.add(option);
    }
    select.value = value;
  }
  function commit(part: "root" | "quality"): void {
    if (!current || atom === null) return;
    const value = part === "root" ? root.value : quality.value;
    const kind = QUALITIES.find(item => item.value === value || item.aliases.includes(value));
    if (part === "quality" && atom !== "~" && kind &&
        (current.quality === kind.value || kind.aliases.includes(current.quality))) {
      quality.value = current.quality;
      return;
    }
    const nextRoot = part === "root" ? value : current.root;
    const nextQuality = part === "quality" ? value : current.quality;
    const octave = !nextQuality && /^[679]/.test(current.octave) ? `0${current.octave}` : current.octave;
    const next = `${nextRoot}${nextQuality}${octave}`;
    root.value = current.root;
    quality.value = current.quality;
    if (next === atom) return;
    const pitches = chordPitches(next);
    if (!pitches || pitches.some(pitch => pitch < 0 || pitch > 127)) {
      feedback.textContent = "This chord is outside the supported pitch range.";
      return;
    }
    feedback.textContent = "";
    change(next);
  }
  root.addEventListener("change", () => commit("root"));
  quality.addEventListener("change", () => commit("quality"));
  return {
    update(value, restSeed, doc, from) {
      container.hidden = value === null;
      direct.dataset.from = String(from);
      direct.dataset.to = String(from + (value?.length ?? 0));
      atom = value;
      feedback.textContent = "";
      if (value === null) { current = null; editor.update([], [], "C4", doc, from); return; }
      current = value === "~" ? chordParts(restSeed) ?? chordParts("C") : chordParts(value);
      root.disabled = quality.disabled = !current;
      container.setAttribute("aria-label", value === "~" ? "Fill selected chord rest" : `Edit selected chord ${value}`);
      const pitches = chordPitches(value) ?? [];
      const spelling = current && /[bf]/.test(current.root.slice(1)) ? "Db4" : "C4";
      const base = spelling === "Db4" ? 61 : 60;
      editor.update(pitches, chordPitches(restSeed) ?? [60, 64, 67], spelling, doc, from);
      if (current) {
        retainSpelling(root, current.root);
        const kind = QUALITIES.find(item => item.value === current!.quality || item.aliases.includes(current!.quality));
        retainSpelling(quality, current.quality, `${kind?.label ?? current.quality} (${current.quality})`);
      } else {
        root.selectedIndex = quality.selectedIndex = -1;
      }
      tones.textContent = value === "~" ? "Choose a chord to fill this step" : pitches.map(pitch => transposePitch(spelling, pitch - base) ?? String(pitch)).join(" · ");
    },
    dispose() { editor.dispose(); },
  };
}
