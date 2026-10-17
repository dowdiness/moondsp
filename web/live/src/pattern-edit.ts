import { isolateHistory } from "@codemirror/commands";
import { Transaction } from "@codemirror/state";
import type { EditorView } from "@codemirror/view";
import type { SourceChange } from "./notation-structure";

/** A source edit made by a pattern control, and the source it selects afterward. */
export type PatternEdit = Readonly<{ changes: readonly SourceChange[]; selection?: Readonly<{ from: number; to: number }> }>;

/**
 * Applies `edit`, whose positions are `offset` characters into the document, as
 * one undo step. Text already equal to its replacement is left alone, and an
 * edit that changes nothing only moves the selection.
 */
export function dispatchPatternEdit(view: EditorView, edit: PatternEdit, offset = 0): void {
  const changes = edit.changes
    .map(change => ({ from: change.from + offset, to: change.to + offset, insert: change.insert }))
    .filter(change => view.state.doc.sliceString(change.from, change.to) !== change.insert);
  const selection = edit.selection && { anchor: edit.selection.from + offset, head: edit.selection.to + offset };
  if (!changes.length) {
    if (selection) view.dispatch({ selection });
    return;
  }
  view.dispatch({
    changes, selection,
    annotations: [Transaction.userEvent.of("input.pattern"), isolateHistory.of("full")],
  });
  // Redo restores the selection recorded before the next selection change, so
  // record the edited source itself rather than a mapping of the old selection.
  if (selection) view.dispatch({ selection: view.state.selection });
}
