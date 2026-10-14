import type { AudioEngine } from "./audio";
import { barLevels, createLevelHistory, markCycle, pushLevel } from "./level-history";

// The horizon draws the measured master output as a scrolling level history:
// one rounded bar per short window of RMS, mirrored about the centre line, newest
// at the right. Cycle boundaries are ticked along the bottom edge. It shows what
// the analyser measured, not which notes produced it. Behind the bars, the live
// waveform sways across the band.

const SAMPLE_COUNT = 1024;
const SIGNAL_FLOOR = 0.0015;
const BAR_PX = 3;
const GAP_PX = 2;
const WAVE_SAMPLES = 640;
// Enough bars for an 8K-wide canvas; the arrays are reused every frame.
const MAX_BARS = 2048;

export type SignalHorizon = {
  setCycle(position: number, playing: boolean): void;
  dispose(): void;
};

export function mountSignalHorizon(root: HTMLElement, engine: Pick<AudioEngine, "readWaveform">): SignalHorizon {
  const canvas = document.createElement("canvas");
  root.append(canvas);
  const context = canvas.getContext("2d");
  const samples = new Float32Array(SAMPLE_COUNT);
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  let disposed = false;
  let frame = 0;
  let slowTimer = 0;
  let width = 0;
  let height = 0;
  let dpr = 1;
  const history = createLevelHistory();
  const levels = new Float32Array(MAX_BARS);
  const barTicks = new Uint8Array(MAX_BARS);
  let lastCycle: number | null = null;
  let transportPlaying = false;
  let historyQuiet = true;
  let lastLive = false;
  let colors = readColors();

  function readColors(): { bar: string; wave: string; waveEnd: string; tick: string; group: string } {
    const style = getComputedStyle(root);
    return {
      wave: style.getPropertyValue("--wave-a").trim() || "#2f9479",
      waveEnd: style.getPropertyValue("--wave-b").trim() || "#8b7ad8",
      bar: style.getPropertyValue("--horizon-a").trim() || "#354acb",
      tick: style.getPropertyValue("--ink-muted").trim() || "#526b63",
      group: style.getPropertyValue("--accent").trim() || "#354acb",
    };
  }

  // Start the waveform at a rising zero crossing so periodic tones stand still.
  function triggerOffset(): number {
    const limit = SAMPLE_COUNT - WAVE_SAMPLES;
    for (let i = 1; i < limit; i++) if (samples[i - 1] <= 0 && samples[i] > 0) return i;
    return 0;
  }

  function draw(): void {
    if (!context || disposed || width === 0) return;
    const available = engine.readWaveform(samples);
    let sum = 0;
    let peak = 0;
    if (available) {
      for (let i = 0; i < SAMPLE_COUNT; i++) {
        const value = samples[i];
        sum += value * value;
        if (Math.abs(value) > peak) peak = Math.abs(value);
      }
    }
    const live = available && peak > SIGNAL_FLOOR;
    pushLevel(history, live ? Math.sqrt(sum / SAMPLE_COUNT) : 0, performance.now(), transportPlaying);
    if (root.dataset.live !== String(live)) root.dataset.live = String(live);
    lastLive = live;

    context.clearRect(0, 0, width, height);
    const tickSpace = 10 * dpr;
    const center = (height - tickSpace) / 2;
    const reach = center - 2 * dpr;
    const minHalf = 0.75 * dpr;
    const barWidth = BAR_PX * dpr;
    const pitch = (BAR_PX + GAP_PX) * dpr;
    const bars = Math.max(1, Math.min(MAX_BARS, Math.floor(width / pitch)));
    const offsetX = width - bars * pitch + GAP_PX * dpr;
    const frozen = !transportPlaying;
    historyQuiet = barLevels(history, bars, levels, barTicks);

    // Behind the bars, the present waveform sways across the band.
    if (live) {
      const offset = triggerOffset();
      const gain = reach * 0.9 / Math.max(0.02, peak);
      const step = width / (WAVE_SAMPLES - 1);
      context.beginPath();
      for (let i = 0; i < WAVE_SAMPLES; i++) {
        const taper = Math.sin(Math.PI * i / (WAVE_SAMPLES - 1));
        // A three-sample average keeps noisy material from drawing as fuzz.
        const sample = (samples[offset + i - 1 < 0 ? 0 : offset + i - 1] + samples[offset + i] + samples[offset + i + 1]) / 3;
        const y = center - sample * gain * taper;
        if (i === 0) context.moveTo(0, y);
        else context.lineTo(i * step, y);
      }
      const ink = context.createLinearGradient(0, 0, width, 0);
      ink.addColorStop(0, colors.wave);
      ink.addColorStop(1, colors.waveEnd);
      context.strokeStyle = ink;
      context.globalAlpha = frozen ? 0.06 : 0.14;
      context.lineWidth = 6 * dpr;
      context.stroke();
      context.globalAlpha = frozen ? 0.25 : 0.55;
      context.lineWidth = 1.5 * dpr;
      context.stroke();
    }

    for (let bar = 0; bar < bars; bar++) {
      const shaped = levels[bar];
      const tick = barTicks[bar];
      const half = minHalf + Math.pow(shaped, 1.15) * (reach - minHalf);
      const age = (bar + 1) / bars;
      const x = offsetX + bar * pitch;
      context.globalAlpha = (0.22 + 0.78 * Math.pow(age, 0.8)) * (0.5 + 0.5 * shaped) * (frozen ? 0.55 : 1);
      context.fillStyle = colors.bar;
      context.beginPath();
      context.roundRect(x, center - half, barWidth, half * 2, barWidth / 2);
      context.fill();
      if (!tick) continue;
      // Cycle ticks along the bottom edge; every fourth cycle is longer and in the accent.
      const group = tick === 2;
      context.globalAlpha = (group ? 0.9 : 0.4) * (frozen ? 0.6 : 1);
      context.fillStyle = group ? colors.group : colors.tick;
      const tickHeight = (group ? 7 : 4) * dpr;
      context.fillRect(Math.round(x + barWidth / 2 - dpr / 2), height - tickHeight, dpr, tickHeight);
    }
    context.globalAlpha = 1;
  }

  function resize(): void {
    const rect = root.getBoundingClientRect();
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    const nextWidth = Math.max(1, Math.round(rect.width * dpr));
    const nextHeight = Math.max(1, Math.round(rect.height * dpr));
    if (canvas.width !== nextWidth || canvas.height !== nextHeight) {
      canvas.width = nextWidth;
      canvas.height = nextHeight;
    }
    width = nextWidth;
    height = nextHeight;
    draw();
  }

  const stop = (): void => {
    if (frame) cancelAnimationFrame(frame);
    if (slowTimer) window.clearInterval(slowTimer);
    frame = 0;
    slowTimer = 0;
  };
  const animate = (): void => {
    frame = 0;
    if (disposed || document.visibilityState !== "visible") return;
    draw();
    // Idle at a low rate once the visible history is silent or frozen.
    if (historyQuiet || (!transportPlaying && !lastLive)) slowTimer = window.setTimeout(() => { slowTimer = 0; animate(); }, 200);
    else frame = requestAnimationFrame(animate);
  };
  const schedule = (): void => {
    stop();
    if (disposed || document.visibilityState !== "visible") return;
    if (reducedMotion.matches) {
      draw();
      slowTimer = window.setInterval(() => draw(), 250);
      return;
    }
    frame = requestAnimationFrame(animate);
  };

  const resizeObserver = new ResizeObserver(resize);
  resizeObserver.observe(root);
  const onVisibility = (): void => schedule();
  // A color-scheme change re-reads the palette.
  const colorScheme = window.matchMedia("(prefers-color-scheme: dark)");
  const onColorScheme = (): void => { colors = readColors(); draw(); };
  colorScheme.addEventListener("change", onColorScheme);
  document.addEventListener("visibilitychange", onVisibility);
  reducedMotion.addEventListener("change", schedule);
  resize();
  schedule();

  return {
    setCycle(position: number, playing: boolean): void {
      transportPlaying = playing;
      const cycle = Math.floor(position);
      if (playing && lastCycle !== null && cycle > lastCycle) markCycle(history, cycle);
      lastCycle = playing ? cycle : null;
      // Keep looping quickly while the transport moves, even through rests.
      if (playing && slowTimer && !reducedMotion.matches) schedule();
    },
    dispose(): void {
      if (disposed) return;
      disposed = true;
      stop();
      resizeObserver.disconnect();
      colorScheme.removeEventListener("change", onColorScheme);
      document.removeEventListener("visibilitychange", onVisibility);
      reducedMotion.removeEventListener("change", schedule);
      canvas.remove();
    },
  };
}
