import { test as base, expect } from "@playwright/test";
import { setTimeout as delay } from "node:timers/promises";
import type { AudioEvent, AudioStatus, OpenSessionResult } from "../src/audio";
import { LivePlayback } from "../src/playback";
import type { PlaybackView } from "../src/playback";
import { decodeWorkletMessage } from "../src/playback-protocol";
import type { PlaybackMode } from "../src/playback-protocol";

type Submission = {
  mode: PlaybackMode;
  text: string;
  policy: "continue" | "restart";
  revision: number;
};

// Controls external audio timing only. All submission, acceptance, freshness,
// dedupe and reveal decisions run through the same LivePlayback as the editor.
class ControlledAudio {
  readonly mode = "scheduler" as const;
  status: AudioStatus = { kind: "idle" };
  audible = false;
  bpm = 60;
  readonly submissions: Submission[] = [];
  readonly tempoCommands: { revision: number; bpm: number }[] = [];
  readonly sessions: ((event: AudioEvent) => void)[] = [];
  private deliver: (event: AudioEvent) => void = () => {
    throw new Error("No audio session has been opened");
  };

  async openSession(deliver: (event: AudioEvent) => void): Promise<OpenSessionResult> {
    this.deliver = deliver;
    this.sessions.push(deliver);
    this.audible = false;
    this.status = { kind: "starting" };
    await Promise.resolve();
    this.status = { kind: "running" };
    return { kind: "opened", session: {
      kind: "scheduler",
      fadeIn: () => { this.audible = true; return "issued"; },
      requestTempoChange: (tempo, id) => {
        this.bpm = tempo.value;
        this.tempoCommands.push({ revision: id.value, bpm: tempo.value });
        return "issued";
      },
      submitScore: ({ id, score, policy }) => {
        this.submissions.push({ mode: score.mode, text: score.text, policy, revision: id.value });
        return "issued";
      },
      close: async () => {
        this.audible = false;
        this.status = { kind: "idle" };
        return { kind: "closed" };
      },
    } };
  }
  fail() {
    this.audible = false;
    this.status = { kind: "error", message: "audio owner failed" };
    this.deliver({ kind: "failed", message: "audio owner failed" });
  }
  reply(raw: unknown) {
    const message = decodeWorkletMessage(raw);
    switch (message.kind) {
      case "receipt": case "tempo": this.deliver(message); break;
      case "runtime-error": case "protocol-error": throw new Error(message.message);
      case "ready": case "notice": throw new Error("Unexpected test receipt");
    }
  }
  accept(submission: Submission, tempo = this.bpm, tempoRevision = this.tempoCommands.at(-1)!.revision) {
    this.reply({ type: `${submission.mode}-updated`, revision: submission.revision,
      operation: submission.policy === "continue" ? "update" : "restart",
      tempo, tempoRevision, samplePosition: 128, acceptedAtSample: 0 });
  }
}

type Session = { audio: ControlledAudio; playback: LivePlayback; view: () => PlaybackView };
const test = base.extend<{ session: Session }>({
  session: async ({}, use) => {
    const audio = new ControlledAudio();
    let view: PlaybackView;
    const playback = new LivePlayback(audio, { text: 'note("60")' },
      state => { view = state; });
    await use({ audio, playback, view: () => view });
    if (audio.status.kind === "running") await playback.toggle();
  },
});

test("stale acceptance reveals audio without painting over the draft", async ({ session }) => {
  const { audio, playback, view } = session;
  await playback.toggle();
  const first = audio.submissions[0];
  expect(audio.audible).toBe(false);
  playback.edit("note(");
  const feedbackBeforeAcceptance = view().feedback;
  audio.accept(first);
  expect(audio.audible).toBe(true);
  expect(view().feedback).toEqual(feedbackBeforeAcceptance);
  expect(view().diagnostic).toBeNull();

  await expect.poll(() => audio.submissions.length).toBe(2);
  const edit = audio.submissions[1];
  expect(edit.policy).toBe("continue");
  audio.reply({ type: "pattern-error", revision: edit.revision, message: "position 5: expected note", recovery: "edit" });
  expect(view().diagnostic).toEqual({ message: "position 5: expected note", documentLength: 5 });
  expect(audio.audible).toBe(true);
  audio.accept(first);
  expect(view().diagnostic?.message).toBe("position 5: expected note");
});

test("superseded first submission cannot reveal its replacement", async ({ session }) => {
  const { audio, playback, view } = session;
  await playback.toggle();
  const first = audio.submissions[0];
  playback.useExample({ mode: "song", text: 'song(section("a",1,note("72")),part("a","a"))' });
  const replacement = audio.submissions[1];
  audio.reply({ type: "playback-superseded", revision: first.revision });
  audio.accept(first);
  expect(audio.audible).toBe(false);
  expect(view().feedback).toBeNull();
  audio.accept(replacement);
  expect(audio.audible).toBe(true);
  expect(view().mode).toBe("song");
  expect(view().diagnostic).toBeNull();
});

test("Stop invalidates receipts before the next Play", async ({ session }) => {
  const { audio, playback, view } = session;
  await playback.toggle();
  const old = audio.submissions[0];
  await playback.toggle();
  await playback.toggle();
  const next = audio.submissions[1];
  expect(next.revision).toBeGreaterThan(old.revision);
  expect(next.policy).toBe("restart");
  audio.accept(old);
  audio.reply({ type: "pattern-error", revision: old.revision, message: "old error", recovery: "edit" });
  expect(audio.audible).toBe(false);
  expect(view().diagnostic).toBeNull();
  audio.accept(next);
  expect(audio.audible).toBe(true);
});

test("Retry drops pending edits and resubmits the latest draft", async ({ session }) => {
  const { audio, playback, view } = session;
  await playback.toggle();
  const old = audio.submissions[0];
  playback.edit('note("67")');
  audio.fail();
  expect(view().status.kind).toBe("error");
  await playback.toggle();
  const next = audio.submissions[1];
  expect(next.text).toBe('note("67")');
  expect(next.policy).toBe("restart");
  audio.accept(old);
  expect(audio.audible).toBe(false);
  audio.accept(next);
  expect(audio.audible).toBe(true);
  // A pre-failure debounce must not submit again after the Retry.
  await delay(250);
  expect(audio.submissions).toHaveLength(2);
});

test("reverting while a replacement is pending still submits the accepted text", async ({ session }) => {
  const { audio, playback, view } = session;
  await playback.toggle();
  audio.accept(audio.submissions[0]);
  playback.edit('note("72")');
  await expect.poll(() => audio.submissions.length).toBe(2);
  const replacement = audio.submissions[1];
  playback.edit('note("60")');
  await expect.poll(() => audio.submissions.length).toBe(3);
  const revert = audio.submissions[2];
  expect(revert.text).toBe('note("60")');
  expect(revert.policy).toBe("continue");
  audio.reply({ type: "playback-superseded", revision: replacement.revision });
  audio.accept(revert);
  playback.edit('note("60")');
  await delay(250);
  expect(audio.submissions).toHaveLength(3);
  expect(view().diagnostic).toBeNull();
});

test("Play uses edits made during asynchronous audio startup", async ({ session }) => {
  const { audio, playback } = session;
  const starting = playback.toggle();
  playback.edit('note("72")');
  await starting;
  expect(audio.submissions).toMatchObject([{ mode: "pattern", text: 'note("72")', policy: "restart" }]);
  expect(audio.audible).toBe(false);
  audio.accept(audio.submissions[0]);
  expect(audio.audible).toBe(true);
});

test("clearing the draft during startup leaves playback stopped", async ({ session }) => {
  const { audio, playback, view } = session;
  const starting = playback.toggle();
  playback.edit("");
  await starting;
  expect(view().status.kind).toBe("idle");
  expect(audio.audible).toBe(false);
  expect(audio.submissions).toHaveLength(0);
});

test("a retired audio session cannot fail a later Play", async ({ session }) => {
  const { audio, playback, view } = session;
  await playback.toggle();
  const retired = audio.sessions[0];
  await playback.toggle();
  await playback.toggle();
  audio.accept(audio.submissions[1]);
  retired({ kind: "failed", message: "late failure from retired session" });
  expect(view().status.kind).toBe("running");
  expect(audio.audible).toBe(true);
});

test("older render and tempo acknowledgements cannot undo a newer tempo commit", async ({ session }) => {
  const { audio, playback, view } = session;
  await playback.toggle();
  const initialTempo = audio.tempoCommands[0];
  playback.commitBpm("120");
  const changedTempo = audio.tempoCommands[1];
  audio.accept(audio.submissions[0], 60, initialTempo.revision);
  expect(view().tempoText).toBe("120");
  expect(audio.audible).toBe(true);
  audio.reply({ type: "tempo-updated", revision: changedTempo.revision, tempo: 120 });
  audio.reply({ type: "tempo-updated", revision: initialTempo.revision, tempo: 60 });
  expect(view().tempoText).toBe("120");
});
