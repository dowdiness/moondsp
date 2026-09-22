import { expect, test } from "@playwright/test";
import { decodeWorkletMessage, RequestId } from "../src/playback-protocol";

test("draft receipts require exact safe versions and source-free operations reject them", () => {
  const receipt = { type: "player-receipt", id: 1, operation: "update",
    accepted: true, restartRequired: false, state: 2, samplePosition: 128, tempo: 60,
    pendingCount: 2, skippedCount: 0, draftVersion: [7, 0] };
  const decoded = decodeWorkletMessage(receipt);
  expect(decoded.kind).toBe("receipt");
  if (decoded.kind === "receipt") expect(decoded.receipt.draftVersion).toEqual([7, 0]);
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
