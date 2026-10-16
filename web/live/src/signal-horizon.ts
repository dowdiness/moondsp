import type { AudioEngine } from "./audio";
import { barLevels, createLevelHistory, markCycle, pushLevel } from "./level-history";
import { MAX_BARS, barShape, horizonLayout, tickShape } from "./horizon-geometry";
import { canvasPixels, signalStats, triggerOffset } from "./signal-math";

// Imperative shell for the horizon: one rounded bar per short window of measured
// RMS, mirrored about the centre line, newest at the right, with cycle ticks along
// the bottom edge and the live waveform swaying behind. It shows what the analyser
// measured, not which notes produced it. Level and geometry decisions live in
// level-history, horizon-geometry, and signal-math; this module measures, draws, and subscribes.

const SAMPLE_COUNT = 1024;
const WAVE_SAMPLES = 640;
const SILENT = { rms: 0, peak: 0, live: false } as const;

export type SignalHorizon = {
  setCycle(position: number, playing: boolean): void;
  dispose(): void;
};

export type SignalHorizonHost = {
  /** The horizon container; the canvas is appended to it. */
  root: HTMLElement;
  /** The document whose visibility pauses drawing. */
  visibility: Document;
  reducedMotion: MediaQueryList;
  /** A color-scheme change re-reads the palette. */
  colorScheme: MediaQueryList;
};

export function mountSignalHorizon(host: SignalHorizonHost, engine: Pick<AudioEngine, "readWaveform">): SignalHorizon {
  const { root, visibility, reducedMotion, colorScheme } = host;
  const canvas = root.ownerDocument.createElement("canvas");
  root.append(canvas);
  // A fresh canvas always provides a 2D context.
  const context = canvas.getContext("2d")!;
  const samples = new Float32Array(SAMPLE_COUNT);
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
    const token = (name: string): string => style.getPropertyValue(name).trim();
    return { wave: token("--wave-a"), waveEnd: token("--wave-b"), bar: token("--horizon-a"), tick: token("--ink-muted"), group: token("--accent") };
  }

  function draw(): void {
    if (disposed || width === 0) return;
    const { rms, peak, live } = engine.readWaveform(samples) ? signalStats(samples) : SILENT;
    pushLevel(history, rms, performance.now(), transportPlaying);
    if (root.dataset.live !== String(live)) root.dataset.live = String(live);
    lastLive = live;

    context.clearRect(0, 0, width, height);
    const layout = horizonLayout(width, height, dpr);
    const { center, reach, barWidth } = layout;
    const frozen = !transportPlaying;
    historyQuiet = barLevels(history, layout.bars, levels, barTicks);

    // Behind the bars, the present waveform sways across the band.
    if (live) {
      const offset = triggerOffset(samples, WAVE_SAMPLES);
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

    for (let bar = 0; bar < layout.bars; bar++) {
      const { half, alpha } = barShape(layout, levels[bar], bar, frozen);
      const x = layout.offsetX + bar * layout.pitch;
      context.globalAlpha = alpha;
      context.fillStyle = colors.bar;
      context.beginPath();
      context.roundRect(x, center - half, barWidth, half * 2, barWidth / 2);
      context.fill();
      const tick = barTicks[bar];
      if (!tick) continue;
      // Cycle ticks along the bottom edge; every fourth cycle is longer and in the accent.
      const shape = tickShape(tick, frozen, dpr);
      context.globalAlpha = shape.alpha;
      context.fillStyle = tick === 2 ? colors.group : colors.tick;
      context.fillRect(Math.round(x + barWidth / 2 - dpr / 2), height - shape.height, dpr, shape.height);
    }
    context.globalAlpha = 1;
  }

  function resize(): void {
    const rect = root.getBoundingClientRect();
    const pixels = canvasPixels(rect.width, rect.height, root.ownerDocument.defaultView!.devicePixelRatio, { maxDpr: 2 });
    if (canvas.width !== pixels.width || canvas.height !== pixels.height) {
      canvas.width = pixels.width;
      canvas.height = pixels.height;
    }
    ({ width, height, dpr } = pixels);
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
    if (disposed || visibility.visibilityState !== "visible") return;
    draw();
    // Idle at a low rate once the visible history is silent or frozen.
    if (historyQuiet || (!transportPlaying && !lastLive)) slowTimer = window.setTimeout(() => { slowTimer = 0; animate(); }, 200);
    else frame = requestAnimationFrame(animate);
  };
  const schedule = (): void => {
    stop();
    if (disposed || visibility.visibilityState !== "visible") return;
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
  const onColorScheme = (): void => { colors = readColors(); draw(); };
  colorScheme.addEventListener("change", onColorScheme);
  visibility.addEventListener("visibilitychange", onVisibility);
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
      visibility.removeEventListener("visibilitychange", onVisibility);
      reducedMotion.removeEventListener("change", schedule);
      canvas.remove();
    },
  };
}
