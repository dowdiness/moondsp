import { StateEffect, type Transaction } from "@codemirror/state";
import type { PlaybackView } from "./playback";

// Functional core for the update status shown on a phrase: which phrases were
// edited since playback last settled, and what their status says. The pattern
// widget shows it; main.ts reports each playback view with `playbackChanged`.

export type PhraseUpdateFeedback = Readonly<{ text: string; scope: "phrase" | "score"; tone: "neutral" | "error" }>;
type Span = Readonly<{ from: number; to: number }>;

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

export const playbackChanged = StateEffect.define<PlaybackView>();

/** The latest playback view, and the phrase contents edited since playback settled. */
export type PhraseUpdates = Readonly<{ playback: PlaybackView | null; edited: readonly Span[] }>;
export const noPhraseUpdates: PhraseUpdates = { playback: null, edited: [] };

/** `phrases` are the content ranges of every phrase after `transaction`. */
export function trackPhraseUpdates(value: PhraseUpdates, transaction: Transaction, phrases: readonly Span[]): PhraseUpdates {
  let { playback, edited } = value;
  for (const effect of transaction.effects) {
    if (!effect.is(playbackChanged)) continue;
    playback = effect.value;
    const settled = ["Empty", "Ready", "Ended", "Fault"].includes(playback.state) ||
      playback.draftStatus === "accepted" && phraseUpdateFeedback(playback) === null;
    if (settled) edited = [];
  }
  if (transaction.docChanged) {
    const { changes } = transaction;
    const next = edited.map(span => ({ from: changes.mapPos(span.from, 1), to: changes.mapPos(span.to, -1) }))
      .filter(span => span.to > span.from);
    changes.iterChangedRanges((_fromA, _toA, from, to) => {
      const hit = phrases.find(range => from <= range.to && to >= range.from);
      if (hit && !next.some(span => span.from === hit.from && span.to === hit.to)) next.push(hit);
    });
    edited = next;
  }
  return playback === value.playback && edited === value.edited ? value : { playback, edited };
}

/** The status to show on the phrase whose content is `range`, if it was edited. */
export function phraseUpdateAt(value: PhraseUpdates, range: Span): PhraseUpdateFeedback | null {
  if (!value.playback || !value.edited.some(span => span.from === range.from && span.to === range.to)) return null;
  return phraseUpdateFeedback(value.playback);
}
