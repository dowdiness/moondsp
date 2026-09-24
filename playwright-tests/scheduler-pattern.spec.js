// spec: specs/scheduler-pattern.md
// seed: playwright-tests/seed.spec.ts

const { test, expect } = require('@playwright/test');

async function setRangeValue(page, selector, value) {
  await page.locator(selector).evaluate((element, nextValue) => {
    element.value = String(nextValue);
    element.dispatchEvent(new Event('input', { bubbles: true }));
  }, value);
}

async function telemetryHistory(page) {
  return page.evaluate(() => window.__moondspTelemetryHistory || []);
}

async function currentTelemetry(page) {
  return page.evaluate(() => window.__moondspTelemetry);
}

async function waitForAnyTelemetryPeak(page, threshold = 0, afterSequence = 0) {
  let matched = null;
  await expect
    .poll(async () => {
      const history = await telemetryHistory(page);
      matched = history.find(
        t => t.sequence > afterSequence && t.overallPeak > threshold,
      ) || null;
      return matched ? matched.overallPeak : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(threshold);
  return matched;
}

async function waitForReceipt(page, afterId = 0, accepted = true) {
  let receipt;
  await expect.poll(async () => {
    receipt = await page.evaluate(() => window.__moondspPlayerReceipt);
    return receipt?.id > afterId;
  }).toBe(true);
  expect(receipt.accepted).toBe(accepted);
  return receipt;
}

async function startScheduler(page) {
  await page.goto('/');
  await page.click('#btnScheduler');
  return waitForReceipt(page);
}

test.describe('Scheduler Initialization', () => {
  test('Scheduler starts and produces audio', async ({ page }) => {
    // 1. Click the "Scheduler" button and wait for audio running status
    await startScheduler(page);

    // 2. Wait for at least one non-silent telemetry block. Scheduler output
    // is rhythmic, so the latest block can legitimately be silent after a
    // successful pulse; checking history avoids racing an instantaneous gap.
    const telemetry = await waitForAnyTelemetryPeak(page);
    expect(telemetry.overallPeak).toBeGreaterThan(0);
  });

});

test.describe('Pattern Text Input', () => {
  test('Eval a drum pattern via text input', async ({ page }) => {
    await startScheduler(page);
    const previous = await page.evaluate(() => window.__moondspPlayerReceipt.id);
    await page.locator('#patternInput').fill('s("bd sd hh sd")');
    await page.click('button:has-text("Eval")');

    // Poll for audio after the accepted edit. Scheduler output is rhythmic,
    // so use telemetry history rather than the latest block only.
    await waitForReceipt(page, previous);
    const baseline = (await currentTelemetry(page))?.sequence || 0;
    await waitForAnyTelemetryPeak(page, 0, baseline);
  });

  test('Eval a note pattern via Enter key', async ({ page }) => {
    await startScheduler(page);
    const previous = await page.evaluate(() => window.__moondspPlayerReceipt.id);
    await page.locator('#patternInput').fill('note("60 64 67")');
    await page.locator('#patternInput').press('Enter');

    // Poll for audio signal — same reason as drum pattern test above.
    await waitForReceipt(page, previous);
    const baseline = (await currentTelemetry(page))?.sequence || 0;
    await waitForAnyTelemetryPeak(page, 0, baseline);
  });

  test('Invalid syntax rejects without stopping playback', async ({ page }) => {
    await startScheduler(page);
    const previous = await page.evaluate(() => window.__moondspPlayerReceipt.id);

    // Type invalid pattern
    await page.locator('#patternInput').fill('invalid!!!');
    await page.click('button:has-text("Eval")');

    const rejected = await waitForReceipt(page, previous, false);
    expect(rejected.state).toBe('Playing');
  });

  test('Unknown drum name shows error', async ({ page }) => {
    await startScheduler(page);
    const previous = await page.evaluate(() => window.__moondspPlayerReceipt.id);
    // Type pattern with unknown drum name
    await page.locator('#patternInput').fill('s("snare")');
    await page.click('button:has-text("Eval")');

    const rejected = await waitForReceipt(page, previous, false);
    expect(rejected.state).toBe('Playing');
  });
});

test.describe('BPM and Gain Controls', () => {
  test('BPM controls reflect source receipts and change the real AudioWorklet tempo', async ({ page }) => {
    const initial = await startScheduler(page);
    await expect(page.locator('#bpmValue')).toHaveText(String(initial.tempo));
    await expect(page.locator('#bpmSlider')).toHaveValue(String(initial.tempo));
    await page.locator('#patternInput').fill('bpm(320.125); note("60")');
    await page.click('button:has-text("Eval")');
    await waitForReceipt(page, initial.id);
    await expect(page.locator('#bpmValue')).toHaveText('320.125');
    await expect(page.locator('#bpmSlider')).toHaveValue('320.125');

    await setRangeValue(page, '#bpmSlider', 180);
    await page.evaluate(() => {
      window.__moondspNode.port.postMessage({ type: 'player-play', id: 987654321 });
    });
    await expect.poll(async () =>
      (await page.evaluate(() => window.__moondspPlayerReceipt))?.id,
    ).toBe(987654321);
    const actual = await page.evaluate(() => window.__moondspPlayerReceipt);
    expect(actual.accepted).toBe(true);
    expect(actual.tempo).toBe(180);
    await expect(page.locator('#bpmValue')).toHaveText('180');
    await expect(page.locator('#bpmSlider')).toHaveValue('180');
  });

  test('Gain slider at zero silences output', async ({ page }) => {
    await startScheduler(page);

    // Wait for audio to start.
    await waitForAnyTelemetryPeak(page);

    // Set gain to 0
    await setRangeValue(page, '#schedulerGainSlider', 0);

    // No fixed sleep: expect.poll already retries until peaks drop, and the
    // prior 500ms waitForTimeout was belt-and-suspenders that only served to
    // mask CI-side jitter (the retry-masked flake this replaces). A longer
    // poll timeout is the deterministic equivalent — the gain ramp takes
    // roughly one telemetry interval (~21ms) to propagate.
    await expect
      .poll(async () => {
        const telemetry = await currentTelemetry(page);
        return telemetry ? telemetry.overallPeak : 1;
      }, { timeout: 10_000 })
      .toBeLessThan(0.001);
  });
});
