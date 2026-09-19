import { expect, test } from "@playwright/test";

// Exercise the real AudioEngine with real Web Audio resources. Only the
// external failure notification is injected; close/resume timing is real.
for (const phase of ["closing", "suspended", "resuming"] as const) {
  test(`runtime failure during ${phase} survives async completion and permits recovery`, async ({ page }) => {
    await page.goto("/?audioMode=compiled");
    await page.locator(".cm-content").click();
    const result = await page.evaluate(async phase => {
      const engine = window.__moondspEngine!;
      const events: string[] = [];
      const first = await engine.openSession(event => events.push(event.kind));
      if (first.kind !== "opened") throw new Error("initial audio open failed");
      const closing = first.session.close();
      const fault = () => engine._testInjectReply({ type: "error", message: "controlled runtime failure" });
      let resumeResult: string | undefined;
      if (phase === "closing") {
        fault();
        await closing;
      } else {
        await closing;
        if (phase === "resuming") {
          const resuming = engine.openSession(event => events.push(event.kind));
          fault();
          resumeResult = (await resuming).kind;
        } else {
          fault();
        }
      }
      const afterFault = engine.getStatus();
      const retry = await engine.openSession(event => events.push(event.kind));
      const afterRetry = engine.getStatus();
      if (retry.kind === "opened") await retry.session.close();
      return { afterFault, afterRetry, resumeResult, events };
    }, phase);
    expect(result.afterFault).toMatchObject({ kind: "error" });
    expect(result.afterRetry).toEqual({ kind: "running" });
    if (phase === "resuming") expect(result.resumeResult).toBe("failed");
    if (phase !== "suspended") expect(result.events).toContain("failed");
  });
}

test("retired session cannot reveal or close a later playback run", async ({ page }) => {
  await page.goto("/?audioMode=compiled");
  await page.locator(".cm-content").click();
  const result = await page.evaluate(async () => {
    const engine = window.__moondspEngine!;
    const first = await engine.openSession(() => {});
    if (first.kind !== "opened") throw new Error("initial audio open failed");
    const closing = first.session.close();
    const duringClose = first.session.fadeIn();
    await closing;
    const afterClose = first.session.fadeIn();
    const second = await engine.openSession(() => {});
    if (second.kind !== "opened") throw new Error("audio resume failed");
    const afterReopen = first.session.fadeIn();
    const oldClose = await first.session.close();
    const currentReveal = second.session.fadeIn();
    const currentStatus = engine.getStatus();
    await second.session.close();
    return { duringClose, afterClose, afterReopen, oldClose, currentReveal, currentStatus };
  });
  expect(result).toEqual({
    duringClose: "session-expired", afterClose: "session-expired", afterReopen: "session-expired",
    oldClose: { kind: "session-expired" }, currentReveal: "issued", currentStatus: { kind: "running" },
  });
});

test("a failed Stop cannot overwrite an immediate Retry", async ({ page }) => {
  await page.goto("/?audioMode=compiled");
  await page.locator(".cm-content").click();
  const result = await page.evaluate(async () => {
    const engine = window.__moondspEngine!;
    const first = await engine.openSession(() => {});
    if (first.kind !== "opened") throw new Error("initial audio open failed");
    const closing = first.session.close();
    engine._testInjectReply({ type: "error", message: "failure during Stop" });
    const retrying = engine.openSession(() => {});
    await closing;
    const retry = await retrying;
    const status = engine.getStatus();
    const obsolete = first.session.fadeIn();
    if (retry.kind === "opened") await retry.session.close();
    return { status, retry: retry.kind, obsolete };
  });
  expect(result).toEqual({ status: { kind: "running" }, retry: "opened", obsolete: "session-expired" });
});

test("cancelling stalled WASM fetch closes the owned context before reopening", async ({ page }) => {
  await page.goto("/?audioMode=compiled");
  await page.locator(".cm-content").click();
  const result = await page.evaluate(async () => {
    const engine = window.__moondspEngine!;
    const originalFetch = window.fetch;
    const originalClose = AudioContext.prototype.close;
    const contexts: AudioContext[] = [];
    const fetchStarted = Promise.withResolvers<void>();
    let fetchAborted = false;
    AudioContext.prototype.close = function() {
      contexts.push(this);
      return originalClose.call(this);
    };
    window.fetch = (_input, init) => {
      fetchStarted.resolve();
      return new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => {
          fetchAborted = true;
          reject(new DOMException("aborted", "AbortError"));
        }, { once: true });
      });
    };
    try {
      const controller = new AbortController();
      const opening = engine.openSession(() => {}, controller.signal).catch(error => error.name);
      await fetchStarted.promise;
      controller.abort();
      const cancellation = await opening;
      const retiredStates = contexts.map(context => context.state);
      window.fetch = originalFetch;
      const retry = await engine.openSession(() => {});
      const status = engine.getStatus();
      if (retry.kind === "opened") await retry.session.close();
      return { cancellation, fetchAborted, retiredStates, retry: retry.kind, status };
    } finally {
      window.fetch = originalFetch;
      AudioContext.prototype.close = originalClose;
    }
  });
  expect(result).toEqual({
    cancellation: "AbortError", fetchAborted: true, retiredStates: ["closed"],
    retry: "opened", status: { kind: "running" },
  });
});

test("cancelling suspended resume closes its graph before a late completion", async ({ page }) => {
  await page.goto("/?audioMode=compiled");
  await page.locator(".cm-content").click();
  const result = await page.evaluate(async () => {
    const engine = window.__moondspEngine!;
    const first = await engine.openSession(() => {});
    if (first.kind !== "opened") throw new Error("initial audio open failed");
    await first.session.close();
    const originalResume = AudioContext.prototype.resume;
    const resumeStarted = Promise.withResolvers<AudioContext>();
    const resumeRelease = Promise.withResolvers<void>();
    AudioContext.prototype.resume = function() {
      resumeStarted.resolve(this);
      return resumeRelease.promise;
    };
    try {
      const controller = new AbortController();
      const opening = engine.openSession(() => {}, controller.signal).catch(error => error.name);
      const context = await resumeStarted.promise;
      controller.abort();
      const cancellation = await opening;
      const retiredState = context.state;
      AudioContext.prototype.resume = originalResume;
      const retry = await engine.openSession(() => {});
      resumeRelease.resolve();
      await new Promise(resolve => setTimeout(resolve, 0));
      const status = engine.getStatus();
      if (retry.kind === "opened") await retry.session.close();
      return { cancellation, retiredState, retry: retry.kind, status };
    } finally {
      AudioContext.prototype.resume = originalResume;
    }
  });
  expect(result).toEqual({
    cancellation: "AbortError", retiredState: "closed", retry: "opened", status: { kind: "running" },
  });
});

test("late non-abortable WASM completion cannot disturb the replacement session", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.goto("/?audioMode=compiled");
  await page.locator(".cm-content").click();
  const result = await page.evaluate(async () => {
    const engine = window.__moondspEngine!;
    const originalFetch = window.fetch;
    const bodyStarted = Promise.withResolvers<void>();
    const bodyRelease = Promise.withResolvers<ArrayBuffer>();
    window.fetch = async () => ({
      ok: true,
      arrayBuffer: () => { bodyStarted.resolve(); return bodyRelease.promise; },
    } as Response);
    try {
      const controller = new AbortController();
      const opening = engine.openSession(() => {}, controller.signal).catch(error => error.name);
      await bodyStarted.promise;
      controller.abort();
      const cancellation = await opening;
      window.fetch = originalFetch;
      const retry = await engine.openSession(() => {});
      bodyRelease.resolve(new ArrayBuffer(8));
      await new Promise(resolve => setTimeout(resolve, 0));
      const status = engine.getStatus();
      if (retry.kind === "opened") await retry.session.close();
      return { cancellation, retry: retry.kind, status };
    } finally {
      window.fetch = originalFetch;
    }
  });
  expect(result).toEqual({ cancellation: "AbortError", retry: "opened", status: { kind: "running" } });
  expect(errors).toEqual([]);
});

test("the initialization deadline covers a fetch that never settles", async ({ page }) => {
  await page.goto("/?audioMode=compiled");
  await page.locator(".cm-content").click();
  const result = await page.evaluate(async () => {
    const engine = window.__moondspEngine!;
    const originalFetch = window.fetch;
    window.fetch = () => new Promise<Response>(() => {});
    try {
      const opening = await engine.openSession(() => {});
      const status = engine.getStatus();
      window.fetch = originalFetch;
      const retry = await engine.openSession(() => {});
      if (retry.kind === "opened") await retry.session.close();
      return { opening, status, retry: retry.kind };
    } finally {
      window.fetch = originalFetch;
    }
  });
  expect(result.opening).toMatchObject({ kind: "failed" });
  expect(result.status).toMatchObject({ kind: "error" });
  expect(result.retry).toBe("opened");
});
