// Pure level-history model behind the signal horizon. It records measured RMS
// into fixed 20 ms slots and turns the newest slots into bar levels; it owns no
// DOM and allocates nothing per frame.

export const SLOT_MS = 20;
export const HISTORY_SLOTS = 400;
export const GROUP_CYCLES = 4;
const PEAK_RELEASE = Math.pow(0.5, SLOT_MS / 3000);
const PEAK_FLOOR = 0.02;
const DYNAMIC_RANGE_DB = 30;
const RELEASE_PER_BAR = 0.86;
// Longer gaps (a hidden tab, a stalled main thread) were never measured; they are
// skipped like a pause instead of being drawn as an interpolated ramp.
const MAX_INTERPOLATED_MS = 250;

/** 0 = no boundary, 1 = cycle boundary, 2 = every GROUP_CYCLES cycles. */
export type Tick = 0 | 1 | 2;

export type LevelHistory = {
  readonly values: Float32Array;
  readonly ticks: Uint8Array;
  head: number;
  lastPush: number;
  peak: number;
  pendingTick: Tick;
};

export function createLevelHistory(): LevelHistory {
  return { values: new Float32Array(HISTORY_SLOTS), ticks: new Uint8Array(HISTORY_SLOTS), head: 0, lastPush: 0, peak: 0, pendingTick: 0 };
}

/** Marks the next recorded slot with the cycle boundary the transport crossed. */
export function markCycle(history: LevelHistory, cycle: number): void {
  history.pendingTick = cycle % GROUP_CYCLES === 0 ? 2 : 1;
}

/**
 * Records `rms` for every whole slot elapsed since the last push. A stopped
 * transport freezes the history. Slots missed by a long frame are interpolated
 * from the previous value instead of holding one level; a gap longer than
 * 250 ms records one slot, as if the history had been paused.
 */
export function pushLevel(history: LevelHistory, rms: number, now: number, playing: boolean): void {
  if (!playing) { history.lastPush = now; return; }
  if (history.lastPush === 0) history.lastPush = now;
  const elapsed = now - history.lastPush;
  if (elapsed > MAX_INTERPOLATED_MS) {
    history.lastPush = now;
    record(history, rms);
    return;
  }
  let slots = Math.floor(elapsed / SLOT_MS);
  if (slots <= 0) return;
  history.lastPush = now - (elapsed % SLOT_MS);
  const previous = history.values[(history.head + HISTORY_SLOTS - 1) % HISTORY_SLOTS];
  const total = slots;
  while (slots-- > 0) record(history, previous + (rms - previous) * (total - slots) / total);
}

function record(history: LevelHistory, value: number): void {
  history.values[history.head] = value;
  history.ticks[history.head] = history.pendingTick;
  history.pendingTick = 0;
  history.head = (history.head + 1) % HISTORY_SLOTS;
  // Slow-release peak tracking keeps quiet and loud scores legible.
  history.peak = Math.max(value, history.peak * PEAK_RELEASE);
}

/**
 * Fills `levels[0..bars)` (oldest to newest) with values in [0, 1] and
 * `ticks[0..bars)` with the strongest boundary in each bar's window. Each bar
 * takes the loudest slot in its window, normalised by the tracked peak and
 * mapped over a 30 dB range, with an instant attack and a short visual release.
 * About two slots feed each bar, so narrow displays show a shorter window.
 * Returns true when every visible slot is silent.
 */
export function barLevels(history: LevelHistory, bars: number, levels: Float32Array, ticks: Uint8Array): boolean {
  const visibleSlots = Math.min(HISTORY_SLOTS, bars * 2);
  const firstSlot = HISTORY_SLOTS - visibleSlots;
  const slotsPerBar = visibleSlots / bars;
  const norm = 1 / Math.max(PEAK_FLOOR, history.peak);
  let quiet = true;
  let carried = 0;
  for (let bar = 0; bar < bars; bar++) {
    const first = firstSlot + Math.floor(bar * slotsPerBar);
    const last = Math.max(first + 1, firstSlot + Math.floor((bar + 1) * slotsPerBar));
    let value = 0;
    let tick = 0;
    for (let slot = first; slot < last; slot++) {
      const index = (history.head + slot) % HISTORY_SLOTS;
      if (history.values[index] > value) value = history.values[index];
      if (history.ticks[index] > tick) tick = history.ticks[index];
    }
    if (value > 0) quiet = false;
    const decibels = 20 * Math.log10(Math.max(value * norm, 1e-4));
    const measured = Math.max(0, Math.min(1, (decibels + DYNAMIC_RANGE_DB) / DYNAMIC_RANGE_DB));
    carried = Math.max(measured, carried * RELEASE_PER_BAR);
    levels[bar] = carried;
    ticks[bar] = tick;
  }
  return quiet;
}
