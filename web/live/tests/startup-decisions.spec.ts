import { expect, test } from "@playwright/test";
import { engineOptions } from "../src/engine-options";
import { RECOVERY_PREFIX, recoveryDrafts, saveDecision } from "../src/save-policy";
import { authoringView } from "../src/status-view";

test("a save writes only over this tab's own saved score", () => {
  expect(saveDecision("old", "old", "new")).toBe("write");
  expect(saveDecision(null, null, "new")).toBe("write");
  // Another tab saved since this tab last did: never overwrite it.
  expect(saveDecision("theirs", "old", "new")).toBe("conflict");
  expect(saveDecision(null, "old", "new")).toBe("conflict");
  // Matching text needs no write, even when it came from another tab.
  expect(saveDecision("new", "old", "new")).toBe("unchanged");
});

test("saved drafts list other tabs' checkpoints newest first and skip malformed entries", () => {
  const entry = (source: string, savedAt: number): string => JSON.stringify({ source, savedAt });
  const drafts = recoveryDrafts([
    [`${RECOVERY_PREFIX}b`, entry("older", 10)],
    [`${RECOVERY_PREFIX}mine`, entry("own", 99)],
    [`${RECOVERY_PREFIX}c`, "{not json"],
    [`${RECOVERY_PREFIX}d`, JSON.stringify({ source: "no time" })],
    ["moondsp.live.score.v1", entry("shared", 50)],
    [`${RECOVERY_PREFIX}a`, entry("newer", 20)],
    [`${RECOVERY_PREFIX}e`, entry("same time, later key", 10)],
  ], `${RECOVERY_PREFIX}mine`);
  expect(drafts.map(draft => draft.source)).toEqual(["newer", "older", "same time, later key"]);
});

test("score tools gate playback and explain a failed load", () => {
  expect(authoringView("starting")).toMatchObject({ authoring: "loading", readiness: null, changeStatusHidden: true });
  expect(authoringView("loading").readiness).toBe("Code is editable. Loading score tools…");
  expect(authoringView("loading").start).toMatchObject({ disabled: true, busy: true });
  expect(authoringView("ready")).toMatchObject({
    authoring: "ready", readiness: null, changeStatusHidden: false, unavailable: null,
    start: { disabled: false, busy: false }, restart: { disabled: false }, sourceToggle: { disabled: false, busy: false },
  });
  const failed = authoringView("failed");
  expect(failed.start).toMatchObject({ disabled: true, title: expect.stringContaining("Playback unavailable") });
  expect(failed.unavailable).toEqual({ transport: "Playback unavailable", draftStatus: "Playback unavailable", draftVersion: "Unavailable" });
});

test("URL switches parse strictly and fall back to engine defaults", () => {
  expect(engineOptions(new URLSearchParams(""))).toEqual({ sampleRate: 48000, latencyHint: undefined, enableOnsets: true });
  expect(engineOptions(new URLSearchParams("sampleRate=-5&latencyHint=fast&onsets=0")))
    .toEqual({ sampleRate: 48000, latencyHint: undefined, enableOnsets: false });
  expect(engineOptions(new URLSearchParams("nativeSampleRate=1&sampleRate=44100&latencyHint=playback")))
    .toEqual({ sampleRate: undefined, latencyHint: "playback", enableOnsets: true });
  expect(engineOptions(new URLSearchParams("sampleRate=44100")))
    .toMatchObject({ sampleRate: 44100 });
});
