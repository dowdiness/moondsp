import { expect, test } from "@playwright/test";
import { decodeWorkletMessage, RequestId } from "../src/playback-protocol";

test("decodes complete player receipts", () => {
  const decoded = decodeWorkletMessage({ type: "player-receipt", id: 1, operation: "pause",
    accepted: true, restartRequired: false, state: 3, samplePosition: 128, tempo: 60,
    pendingCount: 2, skippedCount: 0 });
  expect(decoded.kind).toBe("receipt");
  if (decoded.kind === "receipt") expect(decoded.receipt.operation).toBe("pause");
});

test("rejects incomplete or unknown replies", () => {
  expect(decodeWorkletMessage({ type: "player-receipt", id: 1, operation: "play" }).kind).toBe("protocol-error");
  expect(decodeWorkletMessage({ type: "invented-success", id: 1 }).kind).toBe("protocol-error");
  expect(RequestId.decode(Number.MAX_SAFE_INTEGER + 1)).toBeNull();
});
