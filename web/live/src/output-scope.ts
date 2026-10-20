import "./output-scope.css";
import type { OutputFrame, OutputObservation } from "./output-observation";
import type { Disposable } from "./scope";
import { canvasPixels } from "./signal-math";

// Imperative shell for Help's audio output trace: draws each reading of the
// output while the trace is on screen.

/** The trace shows the first part of each reading. */
const TRACE_SAMPLES = 512;
/** How far a full-scale sample reaches from the centre line, as a share of the canvas height. */
const TRACE_REACH = 0.43;
const MAX_CANVAS_WIDTH = 640;
const MAX_CANVAS_HEIGHT = 128;

type OutputState = "Silent" | "Live";

export type OutputScopeHost = {
  /** The container the scope section is appended to. */
  root: HTMLElement;
};

export function mountOutputScope(host: OutputScopeHost, output: OutputObservation): Disposable {
  const { root } = host;
  const doc = root.ownerDocument;
  const section = doc.createElement("section");
  section.className = "output-scope";
  section.setAttribute("aria-label", "Audio output");

  const heading = doc.createElement("h2");
  heading.className = "output-scope__title";
  heading.textContent = "Audio output";
  const stateText = doc.createElement("span");
  stateText.className = "output-scope__state";
  stateText.textContent = "Silent";

  const canvas = doc.createElement("canvas");
  canvas.className = "output-scope__trace";
  canvas.setAttribute("aria-hidden", "true");
  // A fresh canvas always provides a 2D context.
  const context = canvas.getContext("2d")!;
  section.append(heading, stateText, canvas);
  root.append(section);

  let onScreen = true;
  let width = 0;
  let height = 0;
  const palette = getComputedStyle(section);

  function showState(live: boolean): void {
    const state: OutputState = live ? "Live" : "Silent";
    if (stateText.textContent !== state) stateText.textContent = state;
    stateText.dataset.state = state.toLowerCase();
  }

  function traceWave(samples: Float32Array, center: number): void {
    const trace = samples.subarray(0, TRACE_SAMPLES);
    const step = width / (trace.length - 1);
    trace.forEach((sample, i) => {
      const x = i * step;
      const y = center - sample * height * TRACE_REACH;
      if (i === 0) context.moveTo(x, y);
      else context.lineTo(x, y);
    });
  }

  function traceSilence(center: number): void {
    context.moveTo(0, center);
    context.lineTo(width, center);
  }

  function draw({ samples, stats }: OutputFrame): void {
    showState(stats.live);
    context.clearRect(0, 0, width, height);
    const center = height / 2;
    context.lineWidth = Math.max(1, width / MAX_CANVAS_WIDTH);
    context.strokeStyle = palette.getPropertyValue(stats.live ? "--output-live" : "--output-quiet").trim();
    context.beginPath();
    if (stats.live) traceWave(samples, center);
    else traceSilence(center);
    context.stroke();
  }

  function resize(): void {
    const rect = canvas.getBoundingClientRect();
    const pixels = canvasPixels(rect.width, rect.height, doc.defaultView!.devicePixelRatio,
      { maxDpr: 1.5, maxWidth: MAX_CANVAS_WIDTH, maxHeight: MAX_CANVAS_HEIGHT });
    if (canvas.width !== pixels.width || canvas.height !== pixels.height) {
      canvas.width = pixels.width;
      canvas.height = pixels.height;
    }
    width = pixels.width;
    height = pixels.height;
    output.refresh();
  }

  const resizeObserver = new ResizeObserver(resize);
  resizeObserver.observe(section);
  const intersectionObserver = new IntersectionObserver(entries => {
    const latest = entries[entries.length - 1];
    onScreen = latest.isIntersecting;
    resize();
  });
  intersectionObserver.observe(section);
  const watching = output.watch({ onScreen: () => onScreen, resting: () => false, draw });
  resize();

  return {
    dispose(): void {
      watching.dispose();
      resizeObserver.disconnect();
      intersectionObserver.disconnect();
      section.remove();
    },
  };
}
