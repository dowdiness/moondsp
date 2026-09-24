import { expect, test } from "@playwright/test";
import { decodeWorkletMessage, RequestId } from "../src/playback-protocol";

test("draft receipts require exact safe versions and source-free operations reject them", () => {
  const receipt = { type: "player-receipt", id: 1, operation: "update",
    accepted: true, restartRequired: false, state: "Playing", mode: "song", cyclePosition: 0, samplePosition: 128, tempo: 60,
    pendingCount: 2, skippedCount: 0, draftVersion: [7, 0] };
  const decoded = decodeWorkletMessage(receipt);
  expect(decoded.kind).toBe("receipt");
  if (decoded.kind === "receipt") expect(decoded.receipt.draftVersion).toEqual([7, 0]);
  expect(decodeWorkletMessage({ ...receipt, state: 2, mode: 2 }).kind).toBe("protocol-error");
  for (const draftVersion of [undefined, [0, 1], [7, -1], [7, 0.5], [Number.MAX_SAFE_INTEGER + 1, 0]]) {
    expect(decodeWorkletMessage({ ...receipt, draftVersion }).kind).toBe("protocol-error");
  }
  expect(decodeWorkletMessage({ ...receipt, operation: "pause" }).kind).toBe("protocol-error");
  expect(decodeWorkletMessage({ ...receipt, operation: "pause", draftVersion: null }).kind).toBe("receipt");
});

test("rejects incomplete or unknown replies", () => {
  expect(decodeWorkletMessage({ type: "player-receipt", id: 1, operation: "play" }).kind).toBe("protocol-error");
  expect(decodeWorkletMessage({ type: "invented-success", id: 1 }).kind).toBe("protocol-error");
  expect(RequestId.decode(Number.MAX_SAFE_INTEGER + 1)).toBeNull();
});

test("status requires semantic mode/state strings and finite nonnegative musical position", () => {
  const status = { type: "player-status", state: "Paused", mode: "pattern", cyclePosition: 1.25,
    samplePosition: 48000, tempo: 120, pendingCount: 1, skippedCount: 0 };
  expect(decodeWorkletMessage(status)).toMatchObject({ kind: "status", mode: "pattern", cyclePosition: 1.25 });
  for (const field of ["state", "mode"] as const) {
    expect(decodeWorkletMessage({ ...status, [field]: 0 }).kind).toBe("protocol-error");
  }
  expect(decodeWorkletMessage({ ...status, mode: "invalid" }).kind).toBe("protocol-error");
  for (const cyclePosition of [undefined, -1, Number.NaN, Number.POSITIVE_INFINITY]) {
    expect(decodeWorkletMessage({ ...status, cyclePosition }).kind).toBe("protocol-error");
  }
});
