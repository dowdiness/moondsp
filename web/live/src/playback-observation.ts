import type { EditorView } from "@codemirror/view";
import type { AudioEngine, OnsetObservation } from "./audio";
import type { Draft, LocatedOnset } from "./authoring";
import { setPlaybackHighlights, type PlaybackHighlight } from "./playback-highlights";

const MAX_OBSERVATIONS = 256;
type PendingOnset = OnsetObservation & { location: LocatedOnset | null };

/** Presents executed events. Never queries patterns or advances a musical clock. */
export function mountPlaybackObservation(
  view: EditorView,
  draft: Draft,
  engine: AudioEngine,
  report: (error: unknown) => void,
): { setPlaying(playing: boolean): void; edited(): void; dispose(): void } {
  let playing = false;
  let disposed = false;
  let faulted = false;
  let frame = 0;
  let generation = engine.observationGeneration;
  let changed = false;
  let pending: PendingOnset[] = [];
  let latestOnset = -Infinity;

  function clear(): void {
    pending = [];
    latestOnset = -Infinity;
    setPlaybackHighlights(view, []);
  }
  function schedule(): void {
    if (!frame && playing && !faulted && !disposed && !document.hidden) frame = requestAnimationFrame(tick);
  }
  function tick(now: number): void {
    frame = 0;
    if (!playing || disposed || document.hidden) return;
    try {
      if (generation !== engine.observationGeneration) {
        generation = engine.observationGeneration;
        clear();
      }
      const incoming = engine.readOnsets(now).filter(onset => Number.isFinite(onset.at));
      if (incoming.length) {
        pending.push(...incoming.map(onset => ({ ...onset, location: null })));
        // Order by the audio timestamp: device-time estimates can shift between
        // drains, but simultaneous notes must remain one onset group.
        pending.sort((a, b) => a.fields[0] - b.fields[0]);
        if (pending.length > MAX_OBSERVATIONS) pending = pending.slice(-MAX_OBSERVATIONS);
      }
      for (const onset of pending) {
        if (onset.at <= now) latestOnset = Math.max(latestOnset, onset.fields[0]);
      }
      // Keep the latest executed group until another onset replaces it. A late
      // batch jumps to its newest due group; it never replays intermediate notes.
      pending = pending.filter(onset => onset.fields[0] >= latestOnset);
      if (pending.length && (changed || incoming.length)) {
        const locations = draft.locateOnsets(pending.map(onset => onset.fields));
        for (let i = 0; i < pending.length; i++) pending[i].location = locations[i];
      }
      changed = false;
      const highlights: PlaybackHighlight[] = [];
      for (const onset of pending) {
        if (onset.fields[0] === latestOnset && onset.at <= now && onset.location) highlights.push(onset.location);
      }
      setPlaybackHighlights(view, highlights);
      schedule();
    } catch (error) {
      // A broken observation contract must be visible, but must not stop audio.
      faulted = true;
      clear();
      report(error);
    }
  }
  function visibilityChanged(): void {
    engine.discardOnsets();
    generation = engine.observationGeneration;
    cancelAnimationFrame(frame);
    frame = 0;
    clear();
    schedule();
  }
  document.addEventListener("visibilitychange", visibilityChanged);
  return {
    setPlaying(value) {
      if (!value) faulted = false;
      if (playing === value) return;
      playing = value;
      if (!playing) {
        cancelAnimationFrame(frame);
        frame = 0;
        clear();
      } else schedule();
    },
    edited() { changed = true; schedule(); },
    dispose() {
      disposed = true;
      cancelAnimationFrame(frame);
      document.removeEventListener("visibilitychange", visibilityChanged);
      clear();
    },
  };
}
