import { expect, test } from "@playwright/test";
import { decodeWorkletMessage, RequestId, ScoreSource } from "../src/playback-protocol";

const acceptance = {
  type: "song-updated", revision: 1, operation: "update",
  tempo: 0.001, tempoRevision: null, acceptedAtSample: 128, samplePosition: 256,
};

test("acceptance decoding preserves runtime tempo and requires complete receipt data", () => {
  const decoded = decodeWorkletMessage(acceptance);
  expect(decoded.kind).toBe("receipt");
  if (decoded.kind !== "receipt" || decoded.receipt.kind !== "accepted") throw new Error("Expected acceptance");
  expect(decoded.receipt.tempo.value).toBe(0.001);
  expect(decoded.receipt.id.value).toBe(1);

  for (const invalid of [
    { ...acceptance, revision: undefined },
    { ...acceptance, revision: 0 },
    { ...acceptance, operation: undefined },
    { ...acceptance, tempo: undefined },
    { ...acceptance, tempo: Infinity },
    { ...acceptance, tempoRevision: undefined },
    { ...acceptance, acceptedAtSample: -1 },
  ]) {
    expect(decodeWorkletMessage(invalid).kind).toBe("protocol-error");
  }
});

test("rejections have explicit recovery while unknown messages fail decoding", () => {
  expect(decodeWorkletMessage({ type: "song-error", revision: 2,
    message: "layout differs", recovery: "restart" })).toMatchObject({
    kind: "receipt", receipt: { kind: "rejected", recovery: "restart" },
  });
  expect(decodeWorkletMessage({ type: "pattern-error", revision: 2,
    message: "restart required is just diagnostic text", recovery: "edit" })).toMatchObject({
    kind: "receipt", receipt: { kind: "rejected", recovery: "edit" },
  });
  for (const recovery of [undefined, "retry"]) {
    expect(decodeWorkletMessage({ type: "song-error", revision: 2,
      message: "restart required", recovery }).kind).toBe("protocol-error");
  }
  expect(decodeWorkletMessage({ type: "invented-success", revision: 2 }).kind).toBe("protocol-error");
});

test("source parsing separates empty drafts without pretending to parse score syntax", () => {
  expect(ScoreSource.parse("pattern", " \n").kind).toBe("empty");
  const draft = ScoreSource.parse("pattern", "note(");
  expect(draft.kind).toBe("score");
  if (draft.kind !== "score") throw new Error("Expected nonempty source");
  expect(draft.score.text).toBe("note(");
  expect(RequestId.decode(Number.MAX_SAFE_INTEGER + 1)).toBeNull();
  const last = RequestId.decode(Number.MAX_SAFE_INTEGER);
  if (last === null) throw new Error("Expected final representable ID");
  expect(() => last.next()).toThrow();
});
