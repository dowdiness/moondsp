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

test("score tools gate playback only in scheduler mode and explain a failed load", () => {
  expect(authoringView("starting", true)).toMatchObject({ authoring: "loading", readiness: null, changeStatusHidden: true });
  expect(authoringView("loading", true).readiness).toBe("Code is editable. Loading score tools…");
  expect(authoringView("loading", true).start).toMatchObject({ disabled: true, busy: true });
  expect(authoringView("loading", false).start).toMatchObject({ disabled: false, busy: false });
  expect(authoringView("ready", true)).toMatchObject({
    authoring: "ready", readiness: null, changeStatusHidden: false, unavailable: null,
    start: { disabled: false, busy: false }, restart: { disabled: false }, sourceToggle: { disabled: false, busy: false },
  });
  const failed = authoringView("failed", true);
  expect(failed.start).toMatchObject({ disabled: true, title: expect.stringContaining("Playback unavailable") });
  expect(failed.unavailable).toEqual({ transport: "Playback unavailable", draftStatus: "Playback unavailable", draftVersion: "Unavailable" });
  // Compiled mode plays without score tools, so its transport stays usable.
  expect(authoringView("failed", false).start.disabled).toBe(false);
  expect(authoringView("failed", false).unavailable?.transport).toBeNull();
});

test("URL switches parse strictly and fall back to engine defaults", () => {
  expect(engineOptions(new URLSearchParams(""))).toEqual({
    enableTelemetry: false, enableSchedulerTiming: false, schedulerTimingBatchSize: 128,
    sampleRate: 48000, latencyHint: undefined, mode: "scheduler", enableOnsets: true,
  });
  expect(engineOptions(new URLSearchParams("audioMode=compiled&telemetry=true&schedulerTiming=1&schedulerTimingBatch=0&sampleRate=-5&latencyHint=fast&onsets=0")))
    .toEqual({
      enableTelemetry: true, enableSchedulerTiming: true, schedulerTimingBatchSize: undefined,
      sampleRate: 48000, latencyHint: undefined, mode: "compiled", enableOnsets: false,
    });
  expect(engineOptions(new URLSearchParams("nativeSampleRate=1&sampleRate=44100&latencyHint=playback")))
    .toMatchObject({ sampleRate: undefined, latencyHint: "playback" });
  expect(engineOptions(new URLSearchParams("sampleRate=44100&telemetry=yes")))
    .toMatchObject({ sampleRate: 44100, enableTelemetry: false });
});
