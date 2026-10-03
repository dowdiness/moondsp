import { expect, test } from "@playwright/test";
import { Audition, type AuditionState } from "../src/audition";
import type { AudioEvent, OpenSessionResult, SchedulerSession } from "../src/audio";

function harness() {
  const events: string[] = [];
  const sources: string[] = [];
  let closeCount = 0;
  let deliver: (event: AudioEvent) => void = () => {};
  const session: SchedulerSession = {
    kind: "scheduler",
    fadeIn: () => "issued",
    close: async () => { closeCount += 1; return { kind: "closed" }; },
    update: () => "issued",
    restart: (id, input) => {
      sources.push(input.source);
      deliver({ kind: "receipt", receipt: {
        id, operation: "restart", draftVersion: null, kind: "accepted", state: "Playing", mode: "pattern",
        cyclePosition: 0, samplePosition: 1, tempo: 60, pendingCount: 0, skippedCount: 0,
      } });
      return "issued";
    },
    play: () => "issued",
    pause: () => "issued",
  };
  const engine = {
    openSession: async (next: (event: AudioEvent) => void, signal?: AbortSignal): Promise<OpenSessionResult> => {
      deliver = next;
      if (signal?.aborted) throw new DOMException("cancelled", "AbortError");
      return { kind: "opened", session };
    },
  };
  const audition = new Audition(engine);
  const report = (name: string) => (state: AuditionState) => events.push(`${name}:${state.kind}`);
  return { audition, events, sources, get closeCount() { return closeCount; }, report,
    fail: (message: string) => deliver({ kind: "failed", message }) };
}

test("stop followed by a new source auditions only the latest request", async () => {
  const h = harness();
  h.audition.play('note("60")', h.report("old"));
  h.audition.stop();
  h.audition.play('note("62")', h.report("new"));
  await expect.poll(() => h.events.includes("new:playing")).toBe(true);
  expect(h.sources).toEqual(['note("62")']);
  expect(h.events).toContain("old:idle");
  expect(h.events).not.toContain("old:playing");
  h.audition.stop();
  expect(h.events.at(-1)).toBe("new:idle");
});

test("an accepted audition reports playing then auto-stops and closes its session", async () => {
  const h = harness();
  h.audition.play('note("64")', h.report("note"));
  await expect.poll(() => h.events.includes("note:playing")).toBe(true);
  await expect.poll(() => h.events.at(-1), { timeout: 1500 }).toBe("note:idle");
  expect(h.closeCount).toBe(1);
  h.audition.dispose();
});

test("runtime failure after acceptance reports the worklet error", async () => {
  const h = harness();
  h.audition.play('note("60")', h.report("note"));
  await expect.poll(() => h.events.includes("note:playing")).toBe(true);
  h.fail("DSP runtime failed");
  expect(h.events.at(-1)).toBe("note:error");
  h.audition.dispose();
});


test("a late initialization is closed before the replacement source starts", async () => {
  let resolveOpening!: (result: OpenSessionResult) => void;
  const opening = new Promise<OpenSessionResult>(resolve => { resolveOpening = resolve; });
  const sources: string[] = [];
  let opens = 0;
  let closedLateSession = 0;
  const makeSession = (late: boolean): SchedulerSession => ({
    kind: "scheduler", fadeIn: () => "issued",
    close: async () => { if (late) closedLateSession += 1; return { kind: "closed" }; },
    update: () => "issued", play: () => "issued", pause: () => "issued",
    restart: (id, input) => {
      sources.push(input.source);
      deliver({ kind: "receipt", receipt: {
        id, operation: "restart", draftVersion: null, kind: "accepted", state: "Playing", mode: "pattern",
        cyclePosition: 0, samplePosition: 1, tempo: 60, pendingCount: 0, skippedCount: 0,
      } });
      return "issued";
    },
  });
  let deliver: (event: AudioEvent) => void = () => {};
  const lateSession = makeSession(true);
  const replacementSession = makeSession(false);
  const engine = {
    openSession: async (next: (event: AudioEvent) => void): Promise<OpenSessionResult> => {
      deliver = next;
      opens += 1;
      return opens === 1 ? opening : { kind: "opened", session: replacementSession };
    },
  };
  const audition = new Audition(engine);
  const states: string[] = [];
  audition.play("obsolete", state => states.push(`old:${state.kind}`));
  await expect.poll(() => opens).toBe(1);
  audition.stop();
  audition.play("latest", state => states.push(`new:${state.kind}`));
  resolveOpening({ kind: "opened", session: lateSession });
  await expect.poll(() => states.includes("new:playing")).toBe(true);
  expect(closedLateSession).toBe(1);
  expect(sources).toEqual(["latest"]);
  expect(states).toContain("old:idle");
  audition.dispose();
});
test("rejected playback is reported as an actionable error and can be retried", async () => {
  const retryEvents: AuditionState[] = [];
  let rejectNext = true;
  const session: SchedulerSession = {
    kind: "scheduler", fadeIn: () => "issued", close: async () => ({ kind: "closed" }),
    update: () => "issued", play: () => "issued", pause: () => "issued",
    restart: (id) => {
      if (rejectNext) {
        rejectNext = false;
        (engineDeliver as (event: AudioEvent) => void)({ kind: "receipt", receipt: {
          id, operation: "restart", draftVersion: null, kind: "rejected", restartRequired: false,
          message: "Source has no playable pattern", state: "Fault", mode: "none", cyclePosition: 0,
          samplePosition: 0, tempo: 60, pendingCount: 0, skippedCount: 0,
        } });
      } else {
        (engineDeliver as (event: AudioEvent) => void)({ kind: "receipt", receipt: {
          id, operation: "restart", draftVersion: null, kind: "accepted", state: "Playing", mode: "pattern",
          cyclePosition: 0, samplePosition: 1, tempo: 60, pendingCount: 0, skippedCount: 0,
        } });
      }
      return "issued";
    },
  };
  let engineDeliver: ((event: AudioEvent) => void) | undefined;
  const engine = { openSession: async (next: (event: AudioEvent) => void): Promise<OpenSessionResult> => {
    engineDeliver = next;
    return { kind: "opened", session };
  } };
  const audition = new Audition(engine);
  audition.play("bad", state => retryEvents.push(state));
  await expect.poll(() => retryEvents.at(-1)?.kind).toBe("error");
  expect(retryEvents.at(-1)).toEqual({ kind: "error", message: "Source has no playable pattern" });
  audition.play('note("60")', state => retryEvents.push(state));
  await expect.poll(() => retryEvents.at(-1)?.kind).toBe("playing");
  expect(retryEvents.map(state => state.kind)).toEqual(["loading", "error", "loading", "playing"]);
  audition.dispose();
});
