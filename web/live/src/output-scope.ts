import "./output-scope.css";
import type { AudioEngine } from "./audio";
import { canvasPixels, drawCadence, signalStats } from "./signal-math";

const SAMPLE_COUNT = 512;
const MAX_CANVAS_WIDTH = 640;
const MAX_CANVAS_HEIGHT = 128;

type OutputState = "Silent" | "Live";

export type OutputScopeHost = {
  /** The container the scope section is appended to. */
  root: HTMLElement;
  /** The document whose visibility pauses drawing. */
  visibility: Document;
  reducedMotion: MediaQueryList;
};

export function mountOutputScope(host: OutputScopeHost, engine: Pick<AudioEngine, "readWaveform">): { dispose(): void } {
  const { root, visibility, reducedMotion } = host;
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

  const samples = new Float32Array(SAMPLE_COUNT);
  let disposed = false;
  let intersecting = true;
  let frame = 0;
  let slowTimer = 0;
  let width = 0;
  let height = 0;
  const palette = getComputedStyle(section);

  const draw = (): void => {
    if (disposed) return;
    const live = engine.readWaveform(samples) > 0 && signalStats(samples).live;
    const state: OutputState = live ? "Live" : "Silent";
    if (stateText.textContent !== state) stateText.textContent = state;
    stateText.dataset.state = state.toLowerCase();

    context.clearRect(0, 0, width, height);
    const center = height / 2;
    context.lineWidth = Math.max(1, width / MAX_CANVAS_WIDTH);
    context.strokeStyle = palette.getPropertyValue(live ? "--output-live" : "--output-quiet").trim();
    context.beginPath();
    if (live) {
      const step = width / (samples.length - 1);
      for (let i = 0; i < samples.length; i++) {
        const x = i * step;
        const y = center - samples[i] * height * 0.43;
        if (i === 0) context.moveTo(x, y);
        else context.lineTo(x, y);
      }
    } else {
      context.moveTo(0, center);
      context.lineTo(width, center);
    }
    context.stroke();
  };

  const resize = (): void => {
    const rect = canvas.getBoundingClientRect();
    const pixels = canvasPixels(rect.width, rect.height, doc.defaultView!.devicePixelRatio,
      { maxDpr: 1.5, maxWidth: MAX_CANVAS_WIDTH, maxHeight: MAX_CANVAS_HEIGHT });
    if (canvas.width !== pixels.width || canvas.height !== pixels.height) {
      canvas.width = pixels.width;
      canvas.height = pixels.height;
    }
    width = pixels.width;
    height = pixels.height;
    draw();
  };

  const cadence = () => drawCadence(!disposed && visibility.visibilityState === "visible" && intersecting, reducedMotion.matches);
  const stop = (): void => {
    if (frame) cancelAnimationFrame(frame);
    if (slowTimer) window.clearInterval(slowTimer);
    frame = 0;
    slowTimer = 0;
  };
  const animate = (): void => {
    frame = 0;
    if (cadence() !== "frame") return;
    draw();
    frame = requestAnimationFrame(animate);
  };
  const schedule = (): void => {
    stop();
    switch (cadence()) {
      case "stopped": return;
      case "interval":
        draw();
        slowTimer = window.setInterval(draw, 250);
        return;
      case "frame": frame = requestAnimationFrame(animate);
    }
  };

  const resizeObserver = new ResizeObserver(resize);
  resizeObserver.observe(section);
  const intersectionObserver = new IntersectionObserver(entries => {
    intersecting = entries[0]?.isIntersecting ?? false;
    if (intersecting) resize();
    schedule();
  });
  intersectionObserver.observe(section);
  const onVisibility = (): void => schedule();
  const onMotionPreference = (): void => schedule();
  visibility.addEventListener("visibilitychange", onVisibility);
  reducedMotion.addEventListener("change", onMotionPreference);
  resize();
  schedule();

  return {
    dispose(): void {
      if (disposed) return;
      disposed = true;
      stop();
      resizeObserver.disconnect();
      intersectionObserver.disconnect();
      visibility.removeEventListener("visibilitychange", onVisibility);
      reducedMotion.removeEventListener("change", onMotionPreference);
      section.remove();
    },
  };
}
