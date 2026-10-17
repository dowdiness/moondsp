import { expect, test } from "@playwright/test";
import { statusView, type StatusInput } from "../src/status-view";

const base: StatusInput = {
  state: "Playing",
  currentSource: "$: s(\"bd\")",
  acceptedVersion: [3, 2],
  draftVersion: [3, 4],
  inFlightVersions: [],
  draftStatus: "accepted",
  tempoText: "96",
  samplePosition: 4800,
  mode: "pattern",
  cyclePosition: 1.256,
  pendingCount: 0,
  skippedCount: 0,
};

test("a rejected edit during playback keeps the accepted code and offers restore", () => {
  const view = statusView({
    ...base,
    draftStatus: "invalid",
    inFlightVersions: [[3, 3], [3, 4]],
    pendingCount: 1,
    skippedCount: 2,
  });
  expect(view).toMatchObject({
    label: "Playing",
    playing: true,
    action: "pause",
    tone: "error",
    restoreHidden: false,
    headline: "Check your code",
    help: "Playback continues with accepted code. Check the error below.",
    helpHidden: false,
    draftVersion: "3:4",
    versions: "Accepted 3:2 · Sending 3:3, 3:4",
    materials: "1 material awaiting entry · 2 skipped",
    timing: "1 part is waiting to switch. 2 changes were skipped in this pass.",
    timingHidden: false,
    position: "Position: 1.26 cycles",
    tempo: "96 BPM",
  });
});

test("an empty player reads as ready with nothing accepted", () => {
  const view = statusView({
    ...base,
    state: "Empty",
    currentSource: null,
    acceptedVersion: null,
    draftStatus: "unsubmitted",
    mode: "none",
    pendingCount: 2,
  });
  expect(view).toMatchObject({
    label: "Ready",
    playing: false,
    action: "play",
    actionLabel: "Play",
    tone: "neutral",
    restoreHidden: true,
    headline: "Not sent to audio yet",
    helpHidden: true,
    versions: "No accepted draft",
    materials: "No accepted score",
    timingHidden: true,
    tempo: "",
  });
  // With nothing accepted there is no earlier score to restore, even after an error.
  expect(statusView({ ...base, currentSource: null, acceptedVersion: null, draftStatus: "invalid", state: "Ready" })).toMatchObject({
    tone: "error",
    restoreHidden: true,
    help: "Fix the error below, then press Play.",
  });
});

test("accepted code is up to date only once every part has switched", () => {
  expect(statusView(base)).toMatchObject({ tone: "ok", headline: "Code is up to date", timingHidden: true });
  expect(statusView({ ...base, pendingCount: 2 })).toMatchObject({
    tone: "neutral",
    headline: "Changes accepted",
    materials: "2 materials awaiting entry",
    timing: "2 parts are waiting to switch.",
  });
  // A skipped change alone also keeps the status from reading as up to date.
  expect(statusView({ ...base, skippedCount: 1 })).toMatchObject({
    tone: "neutral",
    materials: "No pending transitions · 1 skipped",
    timing: "1 change was skipped in this pass.",
    timingHidden: false,
  });
  // A fault is an error even when the latest draft was accepted, and restoring is not offered.
  expect(statusView({ ...base, state: "Fault" })).toMatchObject({
    tone: "error",
    headline: "Audio stopped",
    helpHidden: false,
    restoreHidden: true,
    action: "play",
  });
  expect(statusView({ ...base, state: "Starting", draftStatus: "unsubmitted" })).toMatchObject({
    playing: false,
    action: "pause",
    headline: "Starting audio…",
  });
});
