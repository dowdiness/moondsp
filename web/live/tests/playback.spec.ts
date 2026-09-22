import { setTimeout as delay } from "node:timers/promises";
import { expect, test } from "@playwright/test";
import { Player } from "../src/playback";
import { Draft, PlaybackInput } from "../src/authoring";
import type { AudioEvent, OpenSessionResult, SchedulerSession } from "../src/audio";
import { RequestId } from "../src/playback-protocol";
import type { PlayerOperation, PlayState } from "../src/playback-protocol";

type Command = { id: number; operation: PlayerOperation; input?: string };
function harness(deferred = false, delayedClose = false, cancellable = false) {
  const commands: Command[] = [];
  let deliver: (event: AudioEvent) => void = () => {};
  const opening = Promise.withResolvers<OpenSessionResult>();
  const closingStarted = Promise.withResolvers<void>();
  let busy = false;
  let firstOpening = true;
  const issue = (id: RequestId, operation: PlayerOperation, input?: PlaybackInput) => {
    commands.push({ id: id.value, operation, input: input?.wire });
    return "issued" as const;
  };
  const closing = Promise.withResolvers<{ kind: "closed" }>();
  const session: SchedulerSession = {
    kind: "scheduler", fadeIn: () => "issued",
    close: async () => {
      closingStarted.resolve();
      if (delayedClose) await closing.promise;
      busy = false;
      return { kind: "closed" } as const;
    },
    update: (id, input) => issue(id, "update", input),
    restart: (id, input) => issue(id, "restart", input),
    play: id => issue(id, "play"),
    pause: id => issue(id, "pause"),
  };
  const engine = { openSession: async (next: (event: AudioEvent) => void, signal?: AbortSignal): Promise<OpenSessionResult> => {
    if (busy) return { kind: "busy" };
    busy = true;
    deliver = next;
    const shouldDefer = deferred && firstOpening;
    firstOpening = false;
    if (!shouldDefer) return { kind: "opened", session };
    if (!cancellable) return opening.promise;
    return new Promise<OpenSessionResult>((resolve, reject) => {
      const abort = () => {
        busy = false;
        reject(new DOMException("Opening cancelled", "AbortError"));
      };
      signal?.addEventListener("abort", abort, { once: true });
      void opening.promise.then(result => {
        signal?.removeEventListener("abort", abort);
        resolve(result);
      });
    });
  } };
  const draft = new Draft('note("60")');
  const player = new Player(engine, { draft }, () => {});
  const reply = (command: Command, accepted = true, state: PlayState = "Playing") => {
    const draftVersion = command.input === undefined ? null : JSON.parse(command.input).version ?? null;
    const snapshot = { id: RequestId.decode(command.id)!, operation: command.operation, draftVersion, state,
      samplePosition: 128, tempo: 60, pendingCount: 0, skippedCount: 0 };
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

test("resuming uses Current song even when the editor contains invalid source", async () => {
  const h = harness(); await h.start();
  const paused = h.player.pause(); h.reply(await h.command(1), true, "Paused"); await paused;
  h.edit("note(");
  const diagnostic = h.player.view().diagnostic;
  expect(diagnostic).not.toBeNull();
  const resumed = h.player.play(); h.reply(await h.command(2)); await resumed;
  expect(h.commands[2]).toMatchObject({ operation: "play", input: undefined });
  expect(h.player.view().currentSource).toBe('note("60")');
  expect(h.player.view().diagnostic).toEqual(diagnostic);
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
  test(`close waits for ${duringOpen ? "opening" : "open"} session cleanup before reuse`, async () => {
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
    const reopening = h.player.play();
    h.releaseClose();
    await closing;
    h.reply(await h.command(nextCommand));
    expect((await reopening).kind).toBe("accepted");
    expect(h.player.view().state).toBe("Playing");
    await h.player.close();
  });
}

test("closing settles an outstanding command and quarantines its late receipt", async () => {
  const h = harness(); await h.start();
  const updating = h.player.update(PlaybackInput.text('note("67")')); const command = await h.command(1);
  const cancelled = expect(updating).rejects.toMatchObject({ name: "AbortError" });
  await h.player.close(); await cancelled;
  h.reply(command);
  expect(h.player.view().state).toBe("Empty");
  expect(h.player.view().currentSource).toBeNull();
});

test("a worklet fault rejects outstanding commands and retires late receipts", async () => {
  const h = harness(); await h.start();
  const updating = h.player.update(PlaybackInput.text('note("67")')); const command = await h.command(1);
  const rejected = expect(updating).rejects.toThrow("worklet failed");
  h.fail(); await rejected; h.reply(command);
  expect(h.player.view().state).toBe("Fault");
  expect(h.player.view().currentSource).toBeNull();
});

test("automatic updates retain only the latest unsent draft", async () => {
  const h = harness(); await h.start();
  h.edit('note("62")');
  const first = await h.command(1);
  h.edit('note("64")');
  await delay(250);
  h.edit('note("67")');
  await delay(250);
  expect(h.commands).toHaveLength(2);
  h.reply(first);
  const latest = await h.command(2);
  expect(JSON.parse(latest.input!).text).toBe('note("67")');
  h.reply(latest);
  await expect.poll(() => h.player.view().currentSource).toBe('note("67")');
  await h.player.close();
});

test("manual restart bypasses an automatic request and cancels older unsent work", async () => {
  const h = harness(); await h.start();
  h.edit('note("62")');
  const automatic = await h.command(1);
  h.edit('note("64")');
  await delay(250);
  const restarting = h.player.restart(h.draft.prepare());
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
