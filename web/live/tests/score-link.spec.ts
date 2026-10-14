import { expect, test } from "@playwright/test";
import { decodeScoreFragment, encodeScoreLink } from "../src/score-link";

test("score links round-trip UTF-8 text and reject oversized or invalid fragments", async () => {
  const source = '// 日本語のスケッチ\nbpm(84);\nnote("C4 Eb4 G4").gain(0.2)';
  const link = await encodeScoreLink(source, "https://example.test/");
  expect(await decodeScoreFragment(new URL(link).hash)).toBe(source);

  // 1 MiB of text is accepted; one byte more inflates past the bound and is refused
  // while streaming, without materialising the whole payload.
  const limit = "a".repeat(1024 * 1024);
  expect(await decodeScoreFragment(new URL(await encodeScoreLink(limit, "https://example.test/")).hash)).toBe(limit);
  const bomb = new URL(await encodeScoreLink("a".repeat(64 * 1024 * 1024), "https://example.test/")).hash;
  expect(bomb.length).toBeLessThan(200_000);
  expect(await decodeScoreFragment(bomb)).toBeNull();
  expect(await decodeScoreFragment(new URL(await encodeScoreLink(`${limit}a`, "https://example.test/")).hash)).toBeNull();

  expect(await decodeScoreFragment(`#score=${"A".repeat(1_500_000)}`)).toBeNull();
  await expect(decodeScoreFragment("#score=!!!")).rejects.toThrow();
  expect(await decodeScoreFragment("#editor")).toBeNull();
});
