import "./output-scope.css";
import type { AudioEngine } from "./audio";

const SAMPLE_COUNT = 512;
const MAX_CANVAS_WIDTH = 640;
const MAX_CANVAS_HEIGHT = 128;
const SIGNAL_FLOOR = 0.0015;

type OutputState = "Silent" | "Live";

export function mountOutputScope(root: HTMLElement, engine: Pick<AudioEngine, "readWaveform">): { dispose(): void } {
  const section = document.createElement("section");
  section.className = "output-scope";
  section.setAttribute("aria-label", "Audio output");

  const heading = document.createElement("h2");
  heading.className = "output-scope__title";
  heading.textContent = "Audio output";
  const stateText = document.createElement("span");
  stateText.className = "output-scope__state";
  stateText.textContent = "Silent";

  const canvas = document.createElement("canvas");
  canvas.className = "output-scope__trace";
  canvas.setAttribute("aria-hidden", "true");
  const context = canvas.getContext("2d");
  section.append(heading, stateText, canvas);
  root.append(section);

  const samples = new Float32Array(SAMPLE_COUNT);
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  let disposed = false;
  let intersecting = true;
  let frame = 0;
  let slowTimer = 0;
  let width = 0;
  let height = 0;
  const palette = getComputedStyle(section);

  const draw = (): void => {
    if (!context || disposed) return;
    const available = engine.readWaveform(samples);
    let peak = 0;
    if (available) {
      for (let i = 0; i < samples.length; i++) peak = Math.max(peak, Math.abs(samples[i]));
    }
    const live = available && peak > SIGNAL_FLOOR;
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
    const dpr = Math.min(window.devicePixelRatio || 1, 1.5);
    const nextWidth = Math.max(1, Math.min(MAX_CANVAS_WIDTH, Math.round(rect.width * dpr)));
    const nextHeight = Math.max(1, Math.min(MAX_CANVAS_HEIGHT, Math.round(rect.height * dpr)));
    if (canvas.width !== nextWidth || canvas.height !== nextHeight) {
      canvas.width = nextWidth;
      canvas.height = nextHeight;
    }
    width = nextWidth;
    height = nextHeight;
    draw();
  };

  const active = (): boolean => !disposed && document.visibilityState === "visible" && intersecting;
  const stop = (): void => {
    if (frame) cancelAnimationFrame(frame);
    if (slowTimer) window.clearInterval(slowTimer);
    frame = 0;
    slowTimer = 0;
  };
  const animate = (): void => {
    frame = 0;
    if (!active() || reducedMotion.matches) return;
    draw();
    frame = requestAnimationFrame(animate);
  };
  const schedule = (): void => {
    stop();
    if (!active()) return;
    if (reducedMotion.matches) {
      draw();
      slowTimer = window.setInterval(draw, 250);
      return;
    }
    frame = requestAnimationFrame(animate);
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
  document.addEventListener("visibilitychange", onVisibility);
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
      document.removeEventListener("visibilitychange", onVisibility);
      reducedMotion.removeEventListener("change", onMotionPreference);
      section.remove();
    },
  };
}
