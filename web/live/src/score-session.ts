import { isolateHistory } from "@codemirror/commands";
import type { EditorView } from "@codemirror/view";
import type { Notice } from "./notice";
import { RECOVERY_PREFIX, STORAGE_KEY, recoveryDrafts, saveDecision } from "./save-policy";
import type { Disposable } from "./scope";

// Imperative shell for local saving, saved drafts, and score files. The rules
// for what a save does live in save-policy; this module reads and writes storage
// and the DOM.

const SAVE_DELAY_MS = 350;
const MAX_IMPORT_BYTES = 1024 * 1024;

export function loadScore(fallback: string): string {
  try {
    return window.localStorage.getItem(STORAGE_KEY) ?? fallback;
  } catch {
    return fallback;
  }
}

export type ScoreSessionElements = {
  saveStatus: HTMLElement;
  saveButton: HTMLButtonElement;
  openButton: HTMLButtonElement;
  fileInput: HTMLInputElement;
  recoveryPanel: HTMLDetailsElement;
  recoveryList: HTMLElement;
};

export function mountScoreSession(
  elements: ScoreSessionElements, deps: { view: EditorView; notice: Notice },
): Disposable & { changed(): void } {
  const { saveStatus, saveButton, openButton, fileInput, recoveryPanel, recoveryList } = elements;
  const { view, notice } = deps;
  const say = (message: string): void => notice.say(message);
  let pickerDoc: typeof view.state.doc | undefined;
  let timer: number | undefined;
  let disposed = false;
  let savedSource: string | null = view.state.doc.toString();
  let dirty = true;
  let warning: string | null = null;
  let recoveryKey: string | undefined;

  // Keys are immutable: a tab can replace only its own previous checkpoint,
  // and only after its replacement is durable. No shared read/modify/write.
  const checkpoint = (source: string): void => {
    const key = `${RECOVERY_PREFIX}${crypto.randomUUID()}`;
    window.localStorage.setItem(key, JSON.stringify({ source, savedAt: Date.now() }));
    const previous = recoveryKey;
    recoveryKey = key;
    if (previous) window.localStorage.removeItem(previous);
  };

  const refreshRecoveries = (): void => {
    try {
      const storage = window.localStorage;
      const entries = Array.from({ length: storage.length }, (_, index) => storage.key(index))
        .filter((key): key is string => key !== null)
        .map(key => [key, storage.getItem(key)] as const);
      const drafts = recoveryDrafts(entries, recoveryKey);
      recoveryList.replaceChildren();
      for (const { key, source, savedAt } of drafts) {
        const row = document.createElement("li");
        row.className = "saved-draft";
        const time = document.createElement("span");
        time.textContent = new Date(savedAt).toLocaleString();
        const preview = document.createElement("pre");
        preview.textContent = source.length ? source.slice(0, 240) : "(Empty score)";
        const restore = document.createElement("button");
        restore.type = "button";
        restore.textContent = "Restore";
        restore.addEventListener("click", () => {
          view.dispatch({
            changes: { from: 0, to: view.state.doc.length, insert: source },
            annotations: isolateHistory.of("full"),
          });
          recoveryPanel.open = false;
          view.focus();
          say("Restored a saved draft. Undo restores your previous score.");
        });
        const discard = document.createElement("button");
        discard.type = "button";
        discard.textContent = "Delete saved draft";
        discard.addEventListener("click", () => {
          if (!window.confirm("Delete this saved draft? This cannot be undone. Your open score is unchanged.")) return;
          try {
            window.localStorage.removeItem(key);
            refreshRecoveries();
            recoveryPanel.querySelector("summary")?.focus();
          } catch {
            say("Could not delete the saved draft. Your score is unchanged.");
          }
        });
        row.append(time, preview, restore, discard);
        recoveryList.append(row);
      }
      recoveryPanel.hidden = drafts.length === 0;
    } catch {
      say("Saved drafts are unavailable. Download your score to keep it.");
    }
  };

  const setSaveStatus = (message: string): void => {
    saveStatus.textContent = message;
    saveStatus.dataset.warning = String(message === "Not saved");
  };
  const warnSave = (message: string): void => {
    warning = message;
    setSaveStatus("Not saved");
    say(message);
  };
  const warnConflict = (): void => warnSave(
    "The saved score changed in another tab. Saving keeps a separate recovery copy in Saved drafts. Download your score before reloading to use the shared saved version.",
  );
  const saveNow = (initialize = false): void => {
    if (timer !== undefined) {
      window.clearTimeout(timer);
      timer = undefined;
    }
    if (!dirty) return;
    try {
      const source = view.state.doc.toString();
      // Synchronous protection must precede the shared write, including pagehide.
      // A failed checkpoint prevents publishing a score we could not recover.
      if (!initialize) checkpoint(source);
      const stored = window.localStorage.getItem(STORAGE_KEY);
      // Only the first mount may establish a previously absent saved score.
      if (initialize && stored === null) savedSource = null;
      const decision = saveDecision(stored, savedSource, source);
      if (decision === "conflict") {
        warnConflict();
        return;
      }
      if (decision === "write") window.localStorage.setItem(STORAGE_KEY, source);
      savedSource = source;
      dirty = false;
      setSaveStatus("Saved locally");
      if (warning !== null) notice.retract(warning);
      warning = null;
    } catch {
      warnSave("Local storage is unavailable. Download your score to keep it.");
    }
  };
  const changed = (): void => {
    if (disposed) return;
    dirty = true;
    if (timer !== undefined) window.clearTimeout(timer);
    setSaveStatus("Saving…");
    timer = window.setTimeout(saveNow, SAVE_DELAY_MS);
  };
  const onPageHide = (): void => saveNow();
  const onStorage = (event: StorageEvent): void => {
    try {
      if (event.storageArea !== window.localStorage) return;
      // Do not replace buttons while someone is inspecting or using a snapshot.
      // Immutable keys make an older displayed snapshot safe to restore/delete.
      if (!recoveryPanel.open &&
          (event.key === null || event.key.startsWith(RECOVERY_PREFIX))) refreshRecoveries();
      if (event.key !== null && event.key !== STORAGE_KEY) return;
      if (window.localStorage.getItem(STORAGE_KEY) !== savedSource) warnConflict();
    } catch {
      warnSave("Local storage is unavailable. Download your score to keep it.");
    }
  };

  const download = (): void => {
    let url: string | undefined;
    try {
      const blob = new Blob([view.state.doc.toString()], { type: "text/plain;charset=utf-8" });
      url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = "moondsp-score.mini";
      link.click();
      say("Score downloaded as moondsp-score.mini.");
    } catch {
      say("Could not download the score. Your editing session is still available.");
    } finally {
      if (url !== undefined) window.setTimeout(() => URL.revokeObjectURL(url!), 0);
    }
  };

  const openPicker = (): void => {
    pickerDoc = view.state.doc;
    fileInput.click();
  };

  const onFileChange = async (): Promise<void> => {
    const originalDoc = pickerDoc;
    pickerDoc = undefined;
    const file = fileInput.files?.[0];
    // Allow selecting the same file again; a cancelled picker leaves the draft untouched.
    fileInput.value = "";
    if (!file || !originalDoc) return;
    if (file.size > MAX_IMPORT_BYTES) {
      say("That score is larger than 1 MB and was not opened.");
      return;
    }

    try {
      const source = await file.text();
      if (source.length > MAX_IMPORT_BYTES) {
        say("That score is larger than 1 MB and was not opened.");
        return;
      }
      if (view.state.doc !== originalDoc) {
        say("The score was not opened because your text changed while the file was loading. Try opening it again.");
        return;
      }
      view.dispatch({
        changes: { from: 0, to: originalDoc.length, insert: source },
        annotations: isolateHistory.of("full"),
      });
      say(`Opened ${file.name}. Undo restores the previous score.`);
    } catch {
      say("Could not read that score file. Your editing session is still available.");
    }
  };
  const onRecoveryToggle = (): void => {
    // The queued disclosure event can arrive after a user has focused a draft.
    if (!recoveryList.contains(document.activeElement)) refreshRecoveries();
  };

  saveButton.addEventListener("click", download);
  openButton.addEventListener("click", openPicker);
  fileInput.addEventListener("change", onFileChange);
  window.addEventListener("pagehide", onPageHide);
  window.addEventListener("storage", onStorage);
  recoveryPanel.addEventListener("toggle", onRecoveryToggle);

  // A matching stored score is already saved; do not rewrite it on mount or exit.
  saveNow(true);
  refreshRecoveries();

  return {
    changed,
    dispose(): void {
      if (disposed) return;
      saveNow();
      disposed = true;
      saveButton.removeEventListener("click", download);
      openButton.removeEventListener("click", openPicker);
      fileInput.removeEventListener("change", onFileChange);
      window.removeEventListener("pagehide", onPageHide);
      window.removeEventListener("storage", onStorage);
      recoveryPanel.removeEventListener("toggle", onRecoveryToggle);
    },
  };
}
