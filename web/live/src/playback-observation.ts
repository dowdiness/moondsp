import type { EditorView } from "@codemirror/view";
import type { AudioEngine, OnsetObservation } from "./audio";
import type { Draft, LocatedOnset } from "./authoring";
import { setPlaybackHighlights, type PlaybackHighlight } from "./playback-highlights";

const MAX_OBSERVATIONS = 256;
type PendingOnset = OnsetObservation & { location: LocatedOnset | null };
type Timed = Pick<OnsetObservation, "at" | "fields">;

/**
 * Adds `incoming` onsets to `pending` in audio-time order, keeping the newest
 * `MAX_OBSERVATIONS`, and advances `latest` to the newest audio time due by
 * `now`. Onsets older than it are dropped: a late batch jumps to its newest
 * due group and never replays the ones in between.
 */
export function advanceOnsets<T extends Timed>(pending: readonly T[], incoming: readonly T[], latest: number, now: number): { pending: T[]; latest: number } {
  let next = [...pending, ...incoming];
  if (incoming.length) {
    // Order by the audio timestamp: device-time estimates can shift between
    // drains, but simultaneous notes must remain one onset group.
    next.sort((a, b) => a.fields[0] - b.fields[0]);
    if (next.length > MAX_OBSERVATIONS) next = next.slice(-MAX_OBSERVATIONS);
  }
  for (const onset of next) if (onset.at <= now) latest = Math.max(latest, onset.fields[0]);
  return { pending: next.filter(onset => onset.fields[0] >= latest), latest };
}

/** The onsets sounding at `now`: the latest due group, held until another replaces it. */
export function soundingOnsets<T extends Timed>(pending: readonly T[], latest: number, now: number): T[] {
  return pending.filter(onset => onset.fields[0] === latest && onset.at <= now);
}

/** Presents executed events. Never queries patterns or advances a musical clock. */
export function mountPlaybackObservation(
  view: EditorView,
  draft: Draft,
  engine: AudioEngine,
  /** The document whose visibility pauses observation. */
  visibility: Document,
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
    if (!frame && playing && !faulted && !disposed && !visibility.hidden) frame = requestAnimationFrame(tick);
  }
  function tick(now: number): void {
    frame = 0;
    if (!playing || disposed || visibility.hidden) return;
    try {
      if (generation !== engine.observationGeneration) {
        generation = engine.observationGeneration;
        clear();
      }
      const incoming = engine.readOnsets(now).filter(onset => Number.isFinite(onset.at))
        .map((onset): PendingOnset => ({ ...onset, location: null }));
      ({ pending, latest: latestOnset } = advanceOnsets(pending, incoming, latestOnset, now));
      if (pending.length && (changed || incoming.length)) {
        const locations = draft.locateOnsets(pending.map(onset => onset.fields));
        for (let i = 0; i < pending.length; i++) pending[i].location = locations[i];
      }
      changed = false;
      setPlaybackHighlights(view, soundingOnsets(pending, latestOnset, now)
        .flatMap((onset): PlaybackHighlight[] => onset.location ? [onset.location] : []));
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
  visibility.addEventListener("visibilitychange", visibilityChanged);
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
      if (disposed) return;
      disposed = true;
      cancelAnimationFrame(frame);
      visibility.removeEventListener("visibilitychange", visibilityChanged);
      clear();
    },
  };
}
