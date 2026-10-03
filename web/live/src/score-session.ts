import { isolateHistory } from "@codemirror/commands";
import type { EditorView } from "@codemirror/view";

const STORAGE_KEY = "moondsp.live.score.v1";
const RECOVERY_PREFIX = "moondsp.live.draft.v1.";
const SAVE_DELAY_MS = 350;
const MAX_IMPORT_BYTES = 1024 * 1024;

export function loadScore(fallback: string): string {
  try {
    return window.localStorage.getItem(STORAGE_KEY) ?? fallback;
  } catch {
    return fallback;
  }
}

export function mountScoreSession(view: EditorView): { changed(): void; dispose(): void } {
  const saveStatus = document.getElementById("save-status");
  const sessionMessage = document.getElementById("session-message");
  const saveButton = document.getElementById("save-score") as HTMLButtonElement | null;
  const openButton = document.getElementById("open-score") as HTMLButtonElement | null;
  const fileInput = document.getElementById("score-file") as HTMLInputElement | null;
  const recoveryPanel = document.getElementById("saved-drafts") as HTMLDetailsElement | null;
  const recoveryList = document.getElementById("saved-draft-list");
  let pickerDoc: typeof view.state.doc | undefined;
  let timer: number | undefined;
  let disposed = false;
  let savedSource: string | null = view.state.doc.toString();
  let dirty = true;
  let saveWarning = false;
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
    if (!recoveryPanel || !recoveryList) return;
    try {
      const drafts: { key: string; source: string; savedAt: number }[] = [];
      for (let index = 0; index < window.localStorage.length; index++) {
        const key = window.localStorage.key(index);
        if (!key?.startsWith(RECOVERY_PREFIX) || key === recoveryKey) continue;
        try {
          const entry = JSON.parse(window.localStorage.getItem(key) ?? "null");
          if (entry && typeof entry.source === "string" &&
              typeof entry.savedAt === "number" && Number.isFinite(entry.savedAt)) {
            drafts.push({ key, source: entry.source, savedAt: entry.savedAt });
          }
        } catch { /* A malformed entry must not hide other recoverable drafts. */ }
      }
      drafts.sort((a, b) => b.savedAt - a.savedAt || a.key.localeCompare(b.key));
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
          setSessionMessage("Restored a saved draft. Undo restores your previous score.");
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
            setSessionMessage("Could not delete the saved draft. Your score is unchanged.");
          }
        });
        row.append(time, preview, restore, discard);
        recoveryList.append(row);
      }
      recoveryPanel.hidden = drafts.length === 0;
    } catch {
      setSessionMessage("Saved drafts are unavailable. Download your score to keep it.");
    }
  };

  const setSaveStatus = (message: string): void => {
    if (saveStatus) saveStatus.textContent = message;
  };
  const setSessionMessage = (message: string): void => {
    if (sessionMessage) {
      sessionMessage.textContent = message;
      sessionMessage.hidden = message.length === 0;
    }
  };
  const warnSave = (message: string): void => {
    saveWarning = true;
    setSaveStatus("Not saved");
    setSessionMessage(message);
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
      if (stored !== savedSource && stored !== source) {
        warnConflict();
        return;
      }
      if (stored !== source) window.localStorage.setItem(STORAGE_KEY, source);
      savedSource = source;
      dirty = false;
      setSaveStatus("Saved locally");
      if (saveWarning) setSessionMessage("");
      saveWarning = false;
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
      if (!recoveryPanel?.open &&
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
      setSessionMessage("Score downloaded as moondsp-score.mini.");
    } catch {
      setSessionMessage("Could not download the score. Your editing session is still available.");
    } finally {
      if (url !== undefined) window.setTimeout(() => URL.revokeObjectURL(url!), 0);
    }
  };

  const openPicker = (): void => {
    if (!fileInput) {
      setSessionMessage("Score import is unavailable in this page.");
      return;
    }
    pickerDoc = view.state.doc;
    fileInput.click();
  };

  const onFileChange = async (): Promise<void> => {
    if (!fileInput) return;
    const originalDoc = pickerDoc;
    pickerDoc = undefined;
    const file = fileInput.files?.[0];
    // Allow selecting the same file again; a cancelled picker leaves the draft untouched.
    fileInput.value = "";
    if (!file || !originalDoc) return;
    if (file.size > MAX_IMPORT_BYTES) {
      setSessionMessage("That score is larger than 1 MB and was not opened.");
      return;
    }

    try {
      const source = await file.text();
      if (source.length > MAX_IMPORT_BYTES) {
        setSessionMessage("That score is larger than 1 MB and was not opened.");
        return;
      }
      if (view.state.doc !== originalDoc) {
        setSessionMessage("The score was not opened because your text changed while the file was loading. Try opening it again.");
        return;
      }
      view.dispatch({
        changes: { from: 0, to: originalDoc.length, insert: source },
        annotations: isolateHistory.of("full"),
      });
      setSessionMessage(`Opened ${file.name}. Undo restores the previous score.`);
    } catch {
      setSessionMessage("Could not read that score file. Your editing session is still available.");
    }
  };

  saveButton?.addEventListener("click", download);
  openButton?.addEventListener("click", openPicker);
  fileInput?.addEventListener("change", onFileChange);
  window.addEventListener("pagehide", onPageHide);
  window.addEventListener("storage", onStorage);
  recoveryPanel?.addEventListener("toggle", refreshRecoveries);

  // A matching stored score is already saved; do not rewrite it on mount or exit.
  saveNow(true);
  refreshRecoveries();

  return {
    changed,
    dispose(): void {
      if (disposed) return;
      saveNow();
      disposed = true;
      saveButton?.removeEventListener("click", download);
      openButton?.removeEventListener("click", openPicker);
      fileInput?.removeEventListener("change", onFileChange);
      window.removeEventListener("pagehide", onPageHide);
      window.removeEventListener("storage", onStorage);
      recoveryPanel?.removeEventListener("toggle", refreshRecoveries);
    },
  };
}
