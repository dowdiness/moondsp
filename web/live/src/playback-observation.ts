import type { EditorView } from "@codemirror/view";
import type { AudioEngine, OnsetObservation, SignalObservation } from "./audio";
import type { Draft, LocatedOnset } from "./authoring";
import { setPlaybackHighlights, type PlaybackHighlight } from "./playback-highlights";
import { setSignalPlayheads, type SignalPlayhead } from "./signal-preview";

/** A signal value is held this long after its block, then retired: its notes have ended. */
const SIGNAL_HOLD_MS = 250;

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

/**
 * The signal values sounding at `now`: for each signal identity, the rows of
 * its latest due block, one per material that follows it, while that block is
 * at most `SIGNAL_HOLD_MS` old. Later rows stay pending.
 */
export function soundingSignals<T extends Pick<SignalObservation, "at" | "epoch" | "serial">>(pending: readonly T[], now: number): { sounding: T[]; pending: T[] } {
  const latest = new Map<string, number>();
  for (const row of pending) {
    const key = `${row.epoch}:${row.serial}`;
    if (row.at <= now && row.at > (latest.get(key) ?? -Infinity)) latest.set(key, row.at);
  }
  const sounding: T[] = [];
  const kept: T[] = [];
  for (const row of pending) {
    const at = latest.get(`${row.epoch}:${row.serial}`);
    if (row.at > now) kept.push(row);
    else if (row.at === at && now - row.at <= SIGNAL_HOLD_MS) { sounding.push(row); kept.push(row); }
  }
  return { sounding, pending: kept };
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
  let signals: SignalObservation[] = [];
  let shownSignals = false;
  /** Each signal identity's place in the current text; only an edit moves it. */
  let signalLocations = new Map<string, Readonly<{ from: number; to: number }> | null>();

  function clear(): void {
    pending = [];
    latestOnset = -Infinity;
    setPlaybackHighlights(view, []);
    signals = [];
    signalLocations = new Map();
    if (shownSignals) view.dispatch({ effects: setSignalPlayheads.of([]) });
    shownSignals = false;
  }
  /** Shows each sounding signal value on the draft's graph for that exact signal; retired ones show nothing. */
  function showSignals(now: number): void {
    const result = soundingSignals([...signals, ...engine.readSignals(now)], now);
    signals = result.pending;
    const sounding = result.sounding;
    if (!sounding.length && !shownSignals) return;
    const key = (row: SignalObservation) => `${row.epoch}:${row.serial}`;
    const unknown = [...new Map(sounding.filter(row => !signalLocations.has(key(row))).map(row => [key(row), row])).values()];
    if (unknown.length) {
      draft.locateSignals(unknown.map(row => [row.epoch, row.serial] as const))
        .forEach((location, i) => signalLocations.set(key(unknown[i]), location));
    }
    const playheads: SignalPlayhead[] = [];
    for (const row of sounding) {
      const location = signalLocations.get(key(row));
      if (location) playheads.push({ from: location.from, cycles: row.cycles, value: row.value });
    }
    view.dispatch({ effects: setSignalPlayheads.of(playheads) });
    shownSignals = playheads.length > 0;
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
      const incoming = engine.readOnsets(now).map((onset): PendingOnset => ({ ...onset, location: null }));
      ({ pending, latest: latestOnset } = advanceOnsets(pending, incoming, latestOnset, now));
      if (pending.length && (changed || incoming.length)) {
        const locations = draft.locateOnsets(pending.map(onset => onset.fields));
        for (let i = 0; i < pending.length; i++) pending[i].location = locations[i];
      }
      changed = false;
      setPlaybackHighlights(view, soundingOnsets(pending, latestOnset, now)
        .flatMap((onset): PlaybackHighlight[] => onset.location ? [onset.location] : []));
      showSignals(now);
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
    edited() { changed = true; signalLocations = new Map(); schedule(); },
    dispose() {
      if (disposed) return;
      disposed = true;
      cancelAnimationFrame(frame);
      visibility.removeEventListener("visibilitychange", visibilityChanged);
      clear();
    },
  };
}
