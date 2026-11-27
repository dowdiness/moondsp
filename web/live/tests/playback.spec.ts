import { setTimeout as delay } from "node:timers/promises";
import { expect, test } from "@playwright/test";
import { Player } from "../src/playback";
import { Draft, PlaybackInput } from "../src/authoring";
import type { AudioEvent, AudioFormat, AudioSession, OpenSessionResult } from "../src/audio";
import { RequestId } from "../src/playback-protocol";
import type { PlayerOperation, PlayState } from "../src/playback-protocol";

type Command = { id: number; operation: PlayerOperation; input?: string };
const PLAYER_FORMAT: AudioFormat = { sampleRate: 48000, blockSize: 128 };
type Setup = { plannedFormat?: AudioFormat; sessionFormat?: AudioFormat; text?: string };
function harness(deferred = false, delayedClose = false, cancellable = false,
  { plannedFormat, sessionFormat = PLAYER_FORMAT, text = 'note("60")' }: Setup = {}) {
  const commands: Command[] = [];
  let deliver: (event: AudioEvent) => void = () => {};
  const opening = Promise.withResolvers<OpenSessionResult>();
  const closingStarted = Promise.withResolvers<void>();
  // Like AudioEngine, only a running session or a live start is busy: a
  // closing session and a cancelled start give way to the next one at once.
  let owner: "running" | AbortSignal | undefined | null = null;
  const busy = () => owner === "running" || (owner !== null && !owner?.aborted);
  let firstOpening = true;
  const issue = (id: RequestId, operation: PlayerOperation, input?: PlaybackInput) => {
    commands.push({ id: id.value, operation, input: input?.wire });
    return "issued" as const;
  };
  const closing = Promise.withResolvers<{ kind: "closed" }>();
  const session: AudioSession = {
    format: sessionFormat,
    fadeIn: () => "issued",
    close: async () => {
      owner = null;
      closingStarted.resolve();
      if (delayedClose) await closing.promise;
      return { kind: "closed" } as const;
    },
    update: (id, input) => issue(id, "update", input),
    restart: (id, input) => issue(id, "restart", input),
    play: id => issue(id, "play"),
    pause: id => issue(id, "pause"),
  };
  const engine = { plannedFormat, openSession: async (next: (event: AudioEvent) => void, signal?: AbortSignal): Promise<OpenSessionResult> => {
    if (busy()) return { kind: "busy" };
    deliver = next;
    const shouldDefer = deferred && firstOpening;
    firstOpening = false;
    if (!shouldDefer) { owner = "running"; return { kind: "opened", session }; }
    owner = signal;
    const opened = opening.promise.then(result => { if (owner === signal) owner = "running"; return result; });
    if (!cancellable) return opened;
    return new Promise<OpenSessionResult>((resolve, reject) => {
      const abort = () => {
        if (owner === signal) owner = null;
        reject(new DOMException("Opening cancelled", "AbortError"));
      };
      signal?.addEventListener("abort", abort, { once: true });
      void opened.then(result => {
        signal?.removeEventListener("abort", abort);
        resolve(result);
      });
    });
  } };
  const draft = new Draft(text);
  const player = new Player(engine, { draft }, () => {});
  const reply = (command: Command, accepted = true, state: PlayState = "Playing") => {
    const draftVersion = command.input === undefined ? null : JSON.parse(command.input).version ?? null;
    const snapshot = { id: RequestId.decode(command.id)!, operation: command.operation, draftVersion, state,
      mode: "pattern" as const, cyclePosition: 0, samplePosition: 128, tempo: 60, pendingCount: 0, skippedCount: 0 };
    deliver({ kind: "receipt", receipt: accepted ? { ...snapshot, kind: "accepted" }
      : { ...snapshot, kind: "rejected", restartRequired: false, message: "invalid source" } });
  };
  const command = async (index: number) => {
    await expect.poll(() => commands.length).toBeGreaterThan(index);
    return commands[index];
  };
  const start = async () => {
    const pending = player.play(); reply(await command(0)); await pending;
  };
  const edit = (text: string) => {
    const state = draft.state();
    draft.edit({ base: state.version, edits: [{ from: 0, to: state.text.length, inserted: text }] });
    player.editDraft();
  };
  return { player, draft, edit, commands, reply, command, start, deliver: (event: AudioEvent) => deliver(event),
    open: () => opening.resolve({ kind: "opened", session }),
    releaseClose: () => closing.resolve({ kind: "closed" }),
    whenClosing: closingStarted.promise,
    fail: () => deliver({ kind: "failed", message: "worklet failed" }) };
}

test("the draft reports what the player would refuse as soon as the player's format is known", async () => {
  const layered = (parts: number) =>
    `song(section("a",4,s("bd*256")),${Array.from({ length: parts }, (_, i) => `part("p${i}","a",0)`).join(",")})`;
  const limit = "playback arrangement exceeds the query expansion limit";
  // A configured sample rate is known before audio starts.
  const configured = harness(false, false, false, { plannedFormat: PLAYER_FORMAT, text: layered(96) });
  expect(configured.player.view().diagnostic).toEqual({ kind: "over-limit", message: limit });
  expect(configured.player.view().draftStatus).toBe("over-limit");
  const fitting = harness(false, false, false, { plannedFormat: PLAYER_FORMAT, text: layered(32) });
  expect(fitting.player.view().diagnostic).toBeNull();
  // A native rate is known once audio opens, and Play then sends nothing the player would refuse.
  const native = harness(false, false, false, { text: layered(96) });
  expect(native.player.view().diagnostic).toBeNull();
  await expect(native.player.play()).rejects.toThrow(limit);
  expect(native.commands).toHaveLength(0);
  expect(native.player.view().diagnostic?.message).toBe(limit);
  const restarted = harness(false, false, false, { text: layered(96) });
  await expect(restarted.player.restart()).rejects.toThrow(limit);
  expect(restarted.commands).toHaveLength(0);
  await Promise.all([configured.player.close(), fitting.player.close(), native.player.close(), restarted.player.close()]);
});

test("a format no player can run gets no early check, and an unplayable session is a fault", async () => {
  const unrunnable: AudioFormat = { sampleRate: 768000, blockSize: 128 };
  const planned = harness(false, false, false, { plannedFormat: unrunnable });
  expect(planned.player.view().diagnostic).toBeNull();
  const reported = harness(false, false, false, { sessionFormat: unrunnable });
  await expect(reported.player.play()).rejects.toThrow(/unplayable format/);
  expect(reported.commands).toHaveLength(0);
  expect(reported.player.view().state).toBe("Fault");
  await Promise.all([planned.player.close(), reported.player.close()]);
});

test("resuming uses Current song even when the editor contains invalid source", async () => {
  const h = harness(); await h.start();
  const paused = h.player.pause(); h.reply(await h.command(1), true, "Paused"); await paused;
  h.edit("note(");
  const diagnostic = h.player.view().diagnostic;
  expect(diagnostic).not.toBeNull();
  const resumed = h.player.play(); h.reply(await h.command(2)); await resumed;
  expect(h.commands[2]).toMatchObject({ operation: "play", input: undefined });
  expect(h.player.view().currentSource).toBe('note("60")');
  // The page repaints the mark only when the diagnostic itself changes.
  h.player.editDraft();
  expect(h.player.view().diagnostic).toBe(diagnostic);
  await h.player.close();
  expect(h.player.view().diagnostic).toBe(diagnostic);
});

test("a failure inside the editor is reported as one until the draft moves on", async () => {
  const h = harness();
  h.player.reportDraftFailure(new Error("edit lost"));
  expect(h.player.view()).toMatchObject({ draftStatus: "internal", feedback: "edit lost", diagnostic: null });
  h.edit('note("62")');
  expect(h.player.view()).toMatchObject({ draftStatus: "unsubmitted", feedback: null });
  // Preparing the draft for Play fails the same way as preparing it after an edit.
  h.draft.prepare = () => { throw new Error("prepare lost"); };
  await expect(h.player.play()).rejects.toThrow("prepare lost");
  expect(h.player.view()).toMatchObject({ draftStatus: "internal", feedback: "prepare lost", diagnostic: null });
  await h.player.close();
});

test("a late source error cannot annotate a newer editor version", async () => {
  const h = harness(); await h.start();
  const pending = h.player.update(h.draft.prepare()); const old = await h.command(1);
  h.edit('note("60")'); h.reply(old, false); await pending;
  expect(h.player.view().diagnostic).toBeNull();
  expect(h.player.view().feedback).toBeNull();
  expect(h.player.view().currentSource).toBe('note("60")');
  await h.player.close();
});

test("Pause during startup cancels Play without sending a command or showing an error", async () => {
  const h = harness(true);
  const starting = h.player.play();
  const cancelled = expect(starting).rejects.toMatchObject({ name: "AbortError" });
  const pausing = h.player.pause();
  h.open();
  await expect(pausing).rejects.toMatchObject({ name: "AbortError" });
  await cancelled;
  expect(h.commands).toEqual([]);
  expect(h.player.view().currentSource).toBeNull();
  expect(h.player.view().feedback).toBeNull();
  await h.player.close();
});

test("close cancels unresolved initialization and an immediate Play opens afresh", async () => {
  const h = harness(true, false, true);
  const cancelled = expect(h.player.play()).rejects.toMatchObject({ name: "AbortError" });
  const closing = h.player.close();
  const playing = h.player.play();
  await closing;
  await cancelled;
  h.reply(await h.command(0));
  expect((await playing).kind).toBe("accepted");
  expect(h.player.view().state).toBe("Playing");
  await h.player.close();
});

test("Play Pause Play replaces the cancelled initialization without a Pause command", async () => {
  const h = harness(true, false, true);
  const cancelled = expect(h.player.play()).rejects.toMatchObject({ name: "AbortError" });
  const pausing = expect(h.player.pause()).rejects.toMatchObject({ name: "AbortError" });
  const playing = h.player.play();
  await cancelled;
  await pausing;
  h.reply(await h.command(0));
  expect((await playing).kind).toBe("accepted");
  expect(h.commands.map(command => command.operation)).toEqual(["restart"]);
  expect(h.player.view().feedback).toBeNull();
  await h.player.close();
});

for (const duringOpen of [true, false]) {
  test(`Play during ${duringOpen ? "opening" : "open"} session cleanup reopens without waiting for it`, async () => {
    const h = harness(duringOpen, true);
    let cancelled: Promise<void> | undefined;
    if (duringOpen) {
      cancelled = expect(h.player.play()).rejects.toMatchObject({ name: "AbortError" });
    } else {
      await h.start();
    }
    const nextCommand = h.commands.length;
    let closed = false;
    const closing = Promise.all([h.player.close(), h.player.close()]).then(() => { closed = true; });
    if (duringOpen) h.open();
    await h.whenClosing;
    await cancelled;
    expect(closed).toBe(false);
    // The new run starts inside Play's gesture, while the old one still closes.
    const reopening = h.player.play();
    h.reply(await h.command(nextCommand));
    expect((await reopening).kind).toBe("accepted");
    expect(closed).toBe(false);
    h.releaseClose();
    await closing;
    expect(h.player.view().state).toBe("Playing");
    await h.player.close();
  });
}

test("closing settles an outstanding command and quarantines its late receipt", async () => {
  const h = harness(); await h.start();
  const updating = h.player.update(new Draft('note("67")').prepare()); const command = await h.command(1);
  const cancelled = expect(updating).rejects.toMatchObject({ name: "AbortError" });
  await h.player.close(); await cancelled;
  h.reply(command);
  expect(h.player.view().state).toBe("Empty");
  expect(h.player.view().currentSource).toBeNull();
});

test("a worklet fault rejects outstanding commands and retires late receipts", async () => {
  const h = harness(); await h.start();
  const updating = h.player.update(new Draft('note("67")').prepare()); const command = await h.command(1);
  const rejected = expect(updating).rejects.toThrow("worklet failed");
  h.fail(); await rejected; h.reply(command);
  expect(h.player.view().state).toBe("Fault");
  expect(h.player.view().currentSource).toBeNull();
  expect(h.player.view().acceptedVersion).toBeNull();
});

test("a fault forgets the session's sample status; the next session reports its own", async () => {
  const h = harness(); await h.start();
  const loading = { loading: ["piano_c2"], failed: [], overLimit: [], unknown: [] };
  h.deliver({ kind: "samples", ...loading });
  expect(h.player.view().samples).toEqual(loading);
  h.fail();
  expect(h.player.view().samples).toEqual({ loading: [], failed: [], overLimit: [], unknown: [] });
});

test("automatic updates retain only the latest unsent draft", async () => {
  const h = harness(); await h.start();
  h.edit('note("62")');
  const firstVersion = h.draft.state().version;
  expect(h.player.view().draftStatus).toBe("queued");
  const first = await h.command(1);
  expect(h.player.view().draftStatus).toBe("submitting");
  expect(h.player.view().inFlightVersions).toEqual([firstVersion]);
  h.edit('note("64")');
  await delay(250);
  h.edit('note("67")');
  await delay(250);
  const latestVersion = h.draft.state().version;
  expect(h.player.view().draftStatus).toBe("queued");
  expect(h.commands).toHaveLength(2);
  h.reply(first);
  const latest = await h.command(2);
  expect(JSON.parse(latest.input!).text).toBe('note("67")');
  expect(h.player.view().acceptedVersion).toEqual(firstVersion);
  expect(h.player.view().draftStatus).toBe("submitting");
  h.reply(latest);
  await expect.poll(() => h.player.view().currentSource).toBe('note("67")');
  expect(h.player.view().acceptedVersion).toEqual(latestVersion);
  expect(h.player.view().draftStatus).toBe("accepted");
  await h.player.close();
});

test("manual restart bypasses an automatic request and cancels older unsent work", async () => {
  const h = harness(); await h.start();
  h.edit('note("62")');
  const automatic = await h.command(1);
  h.edit('note("64")');
  await delay(250);
  const restarting = h.player.restart();
  const manual = await h.command(2);
  expect(manual.operation).toBe("restart");
  h.reply(manual); await restarting;
  h.reply(automatic);
  await delay(250);
  expect(h.commands).toHaveLength(3);
  expect(h.player.view().currentSource).toBe('note("64")');
  await h.player.close();
});

test("an invalid draft cancels queued automatic input without losing real acceptance", async () => {
  const h = harness(); await h.start();
  h.edit('note("62")');
  const automatic = await h.command(1);
  h.edit('note("64")');
  await delay(250);
  h.edit("note(");
  const diagnostic = h.player.view().diagnostic;
  h.reply(automatic);
  await delay(250);
  expect(h.commands).toHaveLength(2);
  expect(h.player.view().currentSource).toBe('note("62")');
  expect(h.player.view().diagnostic).toEqual(diagnostic);
  expect(diagnostic).not.toBeNull();
  expect(h.player.view().draftStatus).toBe("invalid");
  expect(h.player.view().acceptedVersion).toEqual(JSON.parse(automatic.input!).version);
  await h.player.close();
});

test("receipt version mismatch is a protocol failure, not acceptance", async () => {
  const h = harness(); await h.start();
  const pending = h.player.update(h.draft.prepare());
  const rejected = expect(pending).rejects.toThrow(/version mismatch/);
  const command = await h.command(1);
  h.deliver({ kind: "receipt", receipt: {
    id: RequestId.decode(command.id)!, operation: "update", draftVersion: null,
    kind: "accepted", state: "Playing", samplePosition: 128, tempo: 60,
    mode: "pattern", cyclePosition: 0,
    pendingCount: 0, skippedCount: 0,
  } });
  await rejected;
  expect(h.player.view().state).toBe("Fault");
  expect(h.player.view().currentSource).toBeNull();
  await h.player.close();
});

test("closing audio preserves the document source identities", async () => {
  const h = harness(); await h.start();
  const input = h.draft.prepare().wire;
  await h.player.close();
  const playing = h.player.play();
  const restarted = await h.command(1);
  expect(restarted.input).toBe(input);
  h.reply(restarted); await playing;
  expect(h.player.view().state).toBe("Playing");
  await h.player.close();
});

test("an older source receipt still records acceptance after a newer Pause receipt", async () => {
  const h = harness(); await h.start();
  h.edit('note("67")');
  const input = h.draft.prepare();
  const updating = h.player.update(input);
  const source = await h.command(1);
  const pausing = h.player.pause();
  h.reply(await h.command(2), true, "Paused"); await pausing;
  h.reply(source); await updating;
  expect(h.player.view().state).toBe("Paused");
  expect(h.player.view().acceptedVersion).toEqual(input.draftVersion);
  expect(h.player.view().draftStatus).toBe("accepted");
  await h.player.close();
});

test("the newest current-draft outcome survives reordered source receipts", async () => {
  const h = harness(); await h.start();
  const input = h.draft.prepare();
  const olderAcceptance = h.player.update(input);
  const newerRejection = h.player.update(input);
  h.reply(await h.command(2), false); await newerRejection;
  const diagnostic = h.player.view().diagnostic;
  h.reply(await h.command(1)); await olderAcceptance;
  expect(h.player.view().acceptedVersion).toEqual(input.draftVersion);
  expect(h.player.view().draftStatus).toBe("rejected");
  expect(h.player.view().diagnostic).toEqual(diagnostic);
  const olderRejection = h.player.update(input);
  const newerAcceptance = h.player.update(input);
  h.reply(await h.command(4)); await newerAcceptance;
  h.reply(await h.command(3), false); await olderRejection;
  expect(h.player.view().draftStatus).toBe("accepted");
  expect(h.player.view().diagnostic).toBeNull();
  await h.player.close();
});
