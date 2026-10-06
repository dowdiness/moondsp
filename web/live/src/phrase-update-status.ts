import type { Extension } from "@codemirror/state";
import { ViewPlugin, type ViewUpdate, type EditorView } from "@codemirror/view";
import type { PlaybackView } from "./playback";

export type PhraseUpdateFeedback = Readonly<{ text: string; scope: "phrase" | "score"; tone: "neutral" | "error" }>;
type Span = { from: number; to: number };

/** Status wording intentionally distinguishes accepted code from material activation. */
export function phraseUpdateFeedback(state: PlaybackView): PhraseUpdateFeedback | null {
  switch (state.draftStatus) {
    case "queued": return { text: "Queued · waiting to send", scope: "phrase", tone: "neutral" };
    case "submitting": return { text: "Sending · not yet accepted", scope: "phrase", tone: "neutral" };
    case "invalid": return state.state === "Playing"
      ? { text: "Invalid draft · accepted playback continues", scope: "score", tone: "error" }
      : { text: "Invalid draft · not submitted", scope: "score", tone: "error" };
    case "rejected": return state.state === "Playing"
      ? { text: "Rejected · accepted playback continues (score-wide)", scope: "score", tone: "error" }
      : { text: "Rejected · score update not accepted", scope: "score", tone: "error" };
    case "accepted":
      if (state.acceptedVersion === null || state.acceptedVersion[0] !== state.draftVersion[0] ||
          state.acceptedVersion[1] !== state.draftVersion[1]) return { text: "Accepted earlier version · newer edits remain", scope: "phrase", tone: "neutral" };
      if (state.pendingCount > 0) return { text: state.state === "Playing"
        ? "Accepted · score still updating"
        : "Accepted · score has pending material updates", scope: "score", tone: "neutral" };
      return null;
    case "unsubmitted": return null;
  }
}

function ranges(view: EditorView): Span[] {
  return [...view.dom.querySelectorAll<HTMLElement>(".score-pattern[data-pattern-start][data-pattern-end][data-content-from][data-content-to]")]
    .map(element => ({ from: Number(element.dataset.contentFrom), to: Number(element.dataset.contentTo) }))
    .filter(range => Number.isSafeInteger(range.from) && Number.isSafeInteger(range.to) && range.to > range.from);
}

const instances = new WeakMap<EditorView, PhraseStatusView>();
class PhraseStatusView {
  private spans: Span[] = [];
  private pendingChanges: Span[] = [];
  private lastState: PlaybackView | undefined;
  constructor(private readonly view: EditorView) { instances.set(view, this); }
  update(update: ViewUpdate): void {
    if (!update.docChanged) return;
    const desc = update.changes;
    this.pendingChanges = this.pendingChanges.map(span => ({
      from: desc.mapPos(span.from, -1), to: desc.mapPos(span.to, 1),
    }));
    desc.iterChangedRanges((_fromA, _toA, fromB, toB) =>
      this.pendingChanges.push({ from: fromB, to: toB }));
    this.spans = this.spans.map(span => ({ from: desc.mapPos(span.from, 1), to: desc.mapPos(span.to, -1) }))
      .filter(span => span.to > span.from);
  }
  docViewUpdate(): void {
    const current = ranges(this.view);
    this.pendingChanges = this.pendingChanges.filter(change => {
      const hit = current.find(range => change.from <= range.to && change.to >= range.from);
      if (!hit) return true;
      if (!this.spans.some(span => span.from === hit.from && span.to === hit.to)) this.spans.push({ ...hit });
      return false;
    });
    if (this.lastState) this.render(this.lastState, false);
  }
  render(state: PlaybackView, settle = true): void {
    this.lastState = state;
    const feedback = phraseUpdateFeedback(state);
    if (settle && (["Empty", "Ready", "Ended", "Fault"].includes(state.state) ||
        state.draftStatus === "accepted" && feedback === null)) {
      this.spans = []; this.pendingChanges = [];
    }
    for (const pattern of this.view.dom.querySelectorAll<HTMLElement>(".score-pattern")) {
      const from = Number(pattern.dataset.contentFrom), to = Number(pattern.dataset.contentTo);
      const relevant = this.spans.some(span => span.from === from && span.to === to);
      const slot = pattern.querySelector<HTMLElement>(".phrase-update[role=status]");
      if (!slot) continue;
      const visible = relevant && feedback !== null;
      slot.hidden = !visible;
      slot.textContent = visible ? feedback.text : "";
      slot.dataset.scope = visible ? feedback.scope : "";
      slot.dataset.tone = visible ? feedback.tone : "";
    }
  }
  destroy(): void { instances.delete(this.view); }
}

export function phraseUpdateStatus(): Extension {
  return ViewPlugin.fromClass(PhraseStatusView);
}
export function renderPhraseUpdateStatus(view: EditorView, state: PlaybackView): void {
  instances.get(view)?.render(state);
}
