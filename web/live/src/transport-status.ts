import type { AuthoringView, ControlView, StatusView } from "./status-view";

// Imperative shell for the transport and change status: writes the views that
// status-view decides. It holds no state and makes no decisions.

export type TransportElements = {
  body: HTMLElement;
  start: HTMLButtonElement;
  restart: HTMLButtonElement;
  sourceToggle: HTMLButtonElement;
  status: HTMLElement;
  tempo: HTMLElement;
  position: HTMLElement;
  restoreScore: HTMLButtonElement;
  readiness: HTMLElement;
  changeStatus: HTMLElement;
  draftStatus: HTMLElement;
  changeHelp: HTMLElement;
  changeTiming: HTMLElement;
  draftVersion: HTMLElement;
  draftVersions: HTMLElement;
  materialStatus: HTMLElement;
};

export function setText(element: HTMLElement, text: string): void {
  if (element.textContent !== text) element.textContent = text;
}

function writeAction(start: HTMLButtonElement, action: "play" | "pause", label: string): void {
  setText(start, label);
  start.dataset.action = action;
}

export function writeStatus(elements: TransportElements, status: StatusView): void {
  const e = elements;
  setText(e.status, status.label);
  e.status.dataset.samplePosition = status.samplePosition;
  e.status.dataset.tempo = status.tempoValue;
  setText(e.position, status.position);
  setText(e.tempo, status.tempo);
  e.restoreScore.hidden = status.restoreHidden;
  e.changeStatus.dataset.tone = status.tone;
  e.draftStatus.dataset.state = status.draftState;
  e.draftStatus.dataset.version = status.draftVersion;
  setText(e.draftStatus, status.headline);
  setText(e.changeHelp, status.help);
  e.changeHelp.hidden = status.helpHidden;
  setText(e.draftVersion, status.draftVersion);
  setText(e.draftVersions, status.versions);
  setText(e.materialStatus, status.materials);
  setText(e.changeTiming, status.timing);
  e.changeTiming.hidden = status.timingHidden;
  e.start.disabled = false;
  writeAction(e.start, status.action, status.actionLabel);
}

function writeControl(control: HTMLButtonElement, view: ControlView): void {
  control.disabled = view.disabled;
  if (view.busy) control.setAttribute("aria-busy", "true");
  else control.removeAttribute("aria-busy");
  control.title = view.title;
}

export function writeAuthoring(elements: TransportElements, authoring: AuthoringView): void {
  const e = elements;
  e.body.dataset.authoring = authoring.authoring;
  writeControl(e.start, authoring.start);
  writeControl(e.restart, authoring.restart);
  writeControl(e.sourceToggle, authoring.sourceToggle);
  e.changeStatus.hidden = authoring.changeStatusHidden;
  setText(e.readiness, authoring.readiness ?? "");
  e.readiness.hidden = authoring.readiness === null;
  const unavailable = authoring.unavailable;
  if (!unavailable) return;
  if (unavailable.transport !== null) {
    setText(e.status, unavailable.transport);
    writeAction(e.start, "play", "Play");
  }
  setText(e.draftStatus, unavailable.draftStatus);
  setText(e.draftVersion, unavailable.draftVersion);
}
