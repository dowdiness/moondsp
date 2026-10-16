// Functional core for local saving across tabs. Every tab shares one saved
// score and keeps its own immutable recovery checkpoint; these rules decide
// what a save does and which checkpoints another tab can restore.

export const STORAGE_KEY = "moondsp.live.score.v1";
export const RECOVERY_PREFIX = "moondsp.live.draft.v1.";

export type SaveDecision = "write" | "unchanged" | "conflict";

/**
 * `stored` is the shared saved score now, `saved` what this tab last saved or
 * loaded (null when it has none), `source` the text to save. Another tab's newer
 * score is never overwritten; matching text needs no write.
 */
export function saveDecision(stored: string | null, saved: string | null, source: string): SaveDecision {
  if (stored === source) return "unchanged";
  return stored === saved ? "write" : "conflict";
}

export type RecoveryDraft = Readonly<{ key: string; source: string; savedAt: number }>;

/**
 * The restorable checkpoints among storage `entries`, newest first, excluding
 * this tab's own. A malformed entry is skipped without hiding the others.
 */
export function recoveryDrafts(entries: Iterable<readonly [string, string | null]>, ownKey: string | undefined): RecoveryDraft[] {
  const drafts: RecoveryDraft[] = [];
  for (const [key, value] of entries) {
    if (!key.startsWith(RECOVERY_PREFIX) || key === ownKey || value === null) continue;
    try {
      const entry: unknown = JSON.parse(value);
      if (typeof entry === "object" && entry !== null && "source" in entry && "savedAt" in entry &&
          typeof entry.source === "string" && typeof entry.savedAt === "number" && Number.isFinite(entry.savedAt)) {
        drafts.push({ key, source: entry.source, savedAt: entry.savedAt });
      }
    } catch { /* A malformed entry must not hide other recoverable drafts. */ }
  }
  return drafts.sort((a, b) => b.savedAt - a.savedAt || a.key.localeCompare(b.key));
}
