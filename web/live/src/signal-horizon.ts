import { barLevels, createLevelHistory, markCycle, pushLevel } from "./level-history";
import { MAX_BARS, barShape, horizonLayout, tickShape, toneRamp, toneStep, type HorizonLayout } from "./horizon-geometry";
import type { OutputFrame, OutputObservation } from "./output-observation";
import { canvasPixels, horizonResting, triggerOffset } from "./signal-math";

// Imperative shell for the horizon: one rounded bar per short window of measured
// RMS, mirrored about the centre line, newest at the right, with cycle ticks along
// the bottom edge and the live waveform swaying behind. It shows what the analyser
// measured, not which notes produced it. Level and geometry decisions live in
// level-history, horizon-geometry, and signal-math; readings come from the output
// observation; this module records them, draws, and subscribes.

const WAVE_SAMPLES = 640;

export type SignalHorizon = {
  setCycle(position: number, playing: boolean): void;
  dispose(): void;
};

export type SignalHorizonHost = {
  /** The horizon container; the canvas is appended to it. */
  root: HTMLElement;
  /** A color-scheme change re-reads the palette. */
  colorScheme: MediaQueryList;
};

export function mountSignalHorizon(host: SignalHorizonHost, output: OutputObservation): SignalHorizon {
  const { root, colorScheme } = host;
  const canvas = root.ownerDocument.createElement("canvas");
  root.append(canvas);
  // A fresh canvas always provides a 2D context.
  const context = canvas.getContext("2d")!;
  let width = 0;
  let height = 0;
  let dpr = 1;
  const history = createLevelHistory();
  const levels = new Float32Array(MAX_BARS);
  const barTicks = new Uint8Array(MAX_BARS);
  const barTones = new Float32Array(MAX_BARS);
  let lastCycle: number | null = null;
  let transportPlaying = false;
  let historyQuiet = true;
  let lastLive = false;
  let colors = readColors();
  let toneFills: CanvasGradient[] = [];

  function readColors(): { bar: string; barBright: string; wave: string; waveEnd: string; tick: string; group: string; rule: string } {
    const style = getComputedStyle(root);
    const token = (name: string): string => style.getPropertyValue(name).trim();
    return {
      wave: token("--wave-a"), waveEnd: token("--wave-b"), bar: token("--horizon-a"), barBright: token("--horizon-bright"),
      tick: token("--ink-muted"), group: token("--accent"), rule: token("--border"),
    };
  }

  // Each bar is coloured by the measured tone of its loudest slot, from dark
  // (low) to bright (high). Bars are solid at the centre line and soften toward
  // their tips, so loud passages read as shapes rather than as a wall of colour.
  function paintBars(): void {
    const { center, reach } = horizonLayout(width, height, dpr);
    toneFills = toneRamp(colors.bar, colors.barBright).map(({ solid, soft }) => {
      const fill = context.createLinearGradient(0, center - reach, 0, center + reach);
      fill.addColorStop(0, soft);
      fill.addColorStop(0.5, solid);
      fill.addColorStop(1, soft);
      return fill;
    });
  }

  /** Adds a reading to the level history and notes whether the output is live. */
  function record({ stats, tone, time }: OutputFrame): void {
    pushLevel(history, stats.rms, time, transportPlaying, tone);
    if (root.dataset.live !== String(stats.live)) root.dataset.live = String(stats.live);
    lastLive = stats.live;
  }

  // Behind the bars, the present waveform sways across the band.
  function drawWave(samples: Float32Array, peak: number, layout: HorizonLayout, frozen: boolean): void {
    const offset = triggerOffset(samples, WAVE_SAMPLES);
    const gain = layout.reach * 0.9 / Math.max(0.02, peak);
    const step = width / (WAVE_SAMPLES - 1);
    context.beginPath();
    for (let i = 0; i < WAVE_SAMPLES; i++) {
      const taper = Math.sin(Math.PI * i / (WAVE_SAMPLES - 1));
      // A three-sample average keeps noisy material from drawing as fuzz.
      const sample = (samples[offset + i - 1 < 0 ? 0 : offset + i - 1] + samples[offset + i] + samples[offset + i + 1]) / 3;
      const y = layout.center - sample * gain * taper;
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
    context.globalAlpha = frozen ? 0.3 : 0.7;
    context.lineWidth = 1.5 * dpr;
    context.stroke();
  }

  // The cycle ruler: one hairline along the bottom edge that the ticks rise from.
  function drawCycleRuler(): void {
    context.globalAlpha = 1;
    context.fillStyle = colors.rule;
    context.fillRect(0, height - dpr, width, dpr);
  }

  // One bar per recorded window, coloured by its tone, with its cycle tick below;
  // every fourth cycle's tick is longer and in the accent.
  function drawBars(layout: HorizonLayout, frozen: boolean): void {
    const { center, barWidth } = layout;
    for (let bar = 0; bar < layout.bars; bar++) {
      const { half, alpha } = barShape(layout, levels[bar], bar, frozen);
      const x = layout.offsetX + bar * layout.pitch;
      context.globalAlpha = alpha;
      context.fillStyle = toneFills[toneStep(barTones[bar])];
      context.beginPath();
      context.roundRect(x, center - half, barWidth, half * 2, barWidth / 2);
      context.fill();
      const tick = barTicks[bar];
      if (!tick) continue;
      const shape = tickShape(tick, frozen, dpr);
      context.globalAlpha = shape.alpha;
      context.fillStyle = tick === 2 ? colors.group : colors.tick;
      context.fillRect(Math.round(x + barWidth / 2 - dpr / 2), height - shape.height, dpr, shape.height);
    }
  }

  // The write head: where the next measurement lands, at the right edge on the
  // centre line. It is brighter while the transport runs and shows no level.
  function drawWriteHead(center: number, frozen: boolean): void {
    const headX = width - 10 * dpr;
    context.globalAlpha = frozen ? 0.12 : 0.22;
    context.fillStyle = colors.group;
    context.beginPath();
    context.arc(headX, center, 6 * dpr, 0, Math.PI * 2);
    context.fill();
    context.globalAlpha = frozen ? 0.55 : 1;
    context.beginPath();
    context.arc(headX, center, 2.5 * dpr, 0, Math.PI * 2);
    context.fill();
    context.globalAlpha = 1;
  }

  function draw(frame: OutputFrame): void {
    record(frame);
    const layout = horizonLayout(width, height, dpr);
    const frozen = !transportPlaying;
    historyQuiet = barLevels(history, layout.bars, levels, barTicks, barTones);
    context.clearRect(0, 0, width, height);
    if (frame.stats.live) drawWave(frame.samples, frame.stats.peak, layout, frozen);
    drawCycleRuler();
    drawBars(layout, frozen);
    drawWriteHead(layout.center, frozen);
  }

  function resize(): void {
    const rect = root.getBoundingClientRect();
    const pixels = canvasPixels(rect.width, rect.height, root.ownerDocument.defaultView!.devicePixelRatio, { maxDpr: 2 });
    if (canvas.width !== pixels.width || canvas.height !== pixels.height) {
      canvas.width = pixels.width;
      canvas.height = pixels.height;
    }
    ({ width, height, dpr } = pixels);
    paintBars();
    output.refresh();
  }

  const resizeObserver = new ResizeObserver(resize);
  resizeObserver.observe(root);
  const onColorScheme = (): void => { colors = readColors(); paintBars(); output.refresh(); };
  colorScheme.addEventListener("change", onColorScheme);
  const watching = output.watch({
    onScreen: () => width > 0,
    resting: () => horizonResting(historyQuiet, transportPlaying, lastLive),
    draw,
  });
  resize();

  return {
    setCycle(position: number, playing: boolean): void {
      transportPlaying = playing;
      const cycle = Math.floor(position);
      if (playing && lastCycle !== null && cycle > lastCycle) markCycle(history, cycle);
      lastCycle = playing ? cycle : null;
      // A moving transport keeps the horizon from resting, even through rests.
      output.reconsider();
    },
    dispose(): void {
      watching.dispose();
      resizeObserver.disconnect();
      colorScheme.removeEventListener("change", onColorScheme);
      canvas.remove();
    },
  };
}
