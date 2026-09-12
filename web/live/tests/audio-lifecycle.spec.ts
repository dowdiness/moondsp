import { expect, test } from "@playwright/test";

// Exercise the real AudioEngine with real Web Audio resources. Only the
// external failure notification is injected; close/resume timing is real.
for (const phase of ["closing", "suspended", "resuming"] as const) {
  test(`runtime failure during ${phase} survives async completion and permits recovery`, async ({ page }) => {
    await page.goto("/?audioMode=compiled");
    await page.locator("#mode-pattern").click();
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
  await page.locator("#mode-pattern").click();
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
  await page.locator("#mode-pattern").click();
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
