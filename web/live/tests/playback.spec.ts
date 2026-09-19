import { expect, test } from "@playwright/test";
import { Player } from "../src/playback";
import type { AudioEvent, OpenSessionResult, SchedulerSession } from "../src/audio";
import { RequestId } from "../src/playback-protocol";
import type { PlayerOperation, PlayState } from "../src/playback-protocol";

type Command = { id: number; operation: PlayerOperation; text?: string };
function harness(deferred = false, delayedClose = false, cancellable = false) {
  let deliver: (event: AudioEvent) => void = () => {};
  const opening = Promise.withResolvers<OpenSessionResult>();
  const closingStarted = Promise.withResolvers<void>();
  let busy = false;
  let firstOpening = true;
  const commands: Command[] = [];
  const issue = (id: RequestId, operation: PlayerOperation, text?: string) => {
    commands.push({ id: id.value, operation, text });
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
    update: (id, text) => issue(id, "update", text),
    restart: (id, text) => issue(id, "restart", text),
    play: id => issue(id, "play"), pause: id => issue(id, "pause"),
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
  const player = new Player(engine, { text: 'note("60")' }, () => {});
  const reply = (command: Command, accepted = true, state: PlayState = "Playing") => {
    const snapshot = { id: RequestId.decode(command.id)!, operation: command.operation, state,
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
  return { player, commands, reply, command, start,
    open: () => opening.resolve({ kind: "opened", session }),
    releaseClose: () => closing.resolve({ kind: "closed" }),
    whenClosing: closingStarted.promise,
    fail: () => deliver({ kind: "failed", message: "worklet failed" }) };
}

test("resuming uses Current song even when the editor contains invalid source", async () => {
  const h = harness(); await h.start();
  const paused = h.player.pause(); h.reply(await h.command(1), true, "Paused"); await paused;
  const update = h.player.update("note("); h.reply(await h.command(2), false, "Paused"); await update;
  const resumed = h.player.play(); h.reply(await h.command(3)); await resumed;
  expect(h.commands[3]).toMatchObject({ operation: "play", text: undefined });
  expect(h.player.view().currentSource).toBe('note("60")');
  expect(h.player.view().diagnostic?.message).toBe("invalid source");
  await h.player.close();
});

test("a late source error cannot annotate a newer editor version", async () => {
  const h = harness(); await h.start();
  const pending = h.player.update("note("); const old = await h.command(1);
  h.player.edit('note("67")'); h.reply(old, false); await pending;
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
  const updating = h.player.update('note("67")'); const command = await h.command(1);
  const cancelled = expect(updating).rejects.toMatchObject({ name: "AbortError" });
  await h.player.close(); await cancelled;
  h.reply(command);
  expect(h.player.view().state).toBe("Empty");
  expect(h.player.view().currentSource).toBeNull();
});

test("a worklet fault rejects outstanding commands and retires late receipts", async () => {
  const h = harness(); await h.start();
  const updating = h.player.update('note("67")'); const command = await h.command(1);
  const rejected = expect(updating).rejects.toThrow("worklet failed");
  h.fail(); await rejected; h.reply(command);
  expect(h.player.view().state).toBe("Fault");
  expect(h.player.view().currentSource).toBeNull();
});
