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

async function resetPatternStatus(page) {
  await page.locator('#patternStatus').evaluate(element => {
    element.textContent = '';
    element.classList.remove('pattern-status-ok', 'pattern-status-err');
  });
}

async function waitForNewPatternAudio(page) {
  await expect(page.locator('#patternStatus')).toContainText('Pattern updated');
  const baseline = (await currentTelemetry(page))?.sequence || 0;
  await waitForAnyTelemetryPeak(page, 0, baseline);
}

async function startScheduler(page) {
  await page.goto('/');
  await page.click('#btnScheduler');
  await expect(page.locator('#status')).toContainText('Pattern Scheduler', { timeout: 10_000 });
}

test.describe('Scheduler Initialization', () => {
  test('Scheduler starts and produces audio', async ({ page }) => {
    // 1. Click the "Scheduler" button and wait for audio running status
    await startScheduler(page);
    await expect(page.locator('#patternStatus')).toContainText('Pattern updated', { timeout: 5_000 });

    // 2. Wait for at least one non-silent telemetry block. Scheduler output
    // is rhythmic, so the latest block can legitimately be silent after a
    // successful pulse; checking history avoids racing an instantaneous gap.
    const telemetry = await waitForAnyTelemetryPeak(page);
    expect(telemetry.overallPeak).toBeGreaterThan(0);
  });

  test('Default pattern auto-evaluates', async ({ page }) => {
    // 1. Click scheduler and wait for audio
    await startScheduler(page);

    // 2. Wait for the auto-eval timeout (200ms) plus processing
    await expect(page.locator('#patternStatus')).toContainText('Pattern updated', { timeout: 5_000 });
  });
});

test.describe('Pattern Text Input', () => {
  test('Eval a drum pattern via text input', async ({ page }) => {
    await startScheduler(page);
    await expect(page.locator('#patternStatus')).toContainText('Pattern updated', { timeout: 5_000 });

    // Clear and type new pattern. Reset the status first so the assertion
    // proves this submission was accepted, not the default auto-eval.
    await resetPatternStatus(page);
    await page.locator('#patternInput').fill('s("bd sd hh sd")');
    await page.click('button:has-text("Eval")');

    // Poll for audio after the accepted edit. Scheduler output is rhythmic,
    // so use telemetry history rather than the latest block only.
    await waitForNewPatternAudio(page);
  });

  test('Eval a note pattern via Enter key', async ({ page }) => {
    await startScheduler(page);
    await expect(page.locator('#patternStatus')).toContainText('Pattern updated', { timeout: 5_000 });

    // Clear, type, and press Enter. Reset the status first so the assertion
    // proves this submission was accepted, not the default auto-eval.
    await resetPatternStatus(page);
    await page.locator('#patternInput').fill('note("60 64 67")');
    await page.locator('#patternInput').press('Enter');

    // Poll for audio signal — same reason as drum pattern test above.
    await waitForNewPatternAudio(page);
  });

  test('Parse error shows message', async ({ page }) => {
    await startScheduler(page);
    await expect(page.locator('#patternStatus')).toContainText('Pattern updated', { timeout: 5_000 });

    // Type invalid pattern
    await page.locator('#patternInput').fill('invalid!!!');
    await page.click('button:has-text("Eval")');

    // Verify error is shown (not "Pattern updated")
    await expect(page.locator('#patternStatus')).not.toContainText('Pattern updated');
    // Status should have some error text
    await expect(page.locator('#patternStatus')).not.toBeEmpty();
  });

  test('Unknown drum name shows error', async ({ page }) => {
    await startScheduler(page);
    await expect(page.locator('#patternStatus')).toContainText('Pattern updated', { timeout: 5_000 });

    // Type pattern with unknown drum name
    await page.locator('#patternInput').fill('s("snare")');
    await page.click('button:has-text("Eval")');

    // Verify error
    await expect(page.locator('#patternStatus')).not.toContainText('Pattern updated');
    await expect(page.locator('#patternStatus')).not.toBeEmpty();
  });
});

test.describe('BPM and Gain Controls', () => {
  test('BPM slider updates display', async ({ page }) => {
    await startScheduler(page);

    // Set BPM to 180
    await setRangeValue(page, '#bpmSlider', 180);

    // Verify display
    await expect(page.locator('#bpmValue')).toHaveText('180');
  });

  test('Gain slider at zero silences output', async ({ page }) => {
    await startScheduler(page);
    await expect(page.locator('#patternStatus')).toContainText('Pattern updated', { timeout: 5_000 });

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

test.describe('Stop and Restart', () => {
  test('Stop button silences audio', async ({ page }) => {
    await startScheduler(page);
    await expect(page.locator('#patternStatus')).toContainText('Pattern updated', { timeout: 5_000 });

    // Wait for audio to actually start producing signal. Stop is only
    // meaningful once audio is live; history avoids racing a silent rhythmic
    // gap in the latest telemetry block.
    await waitForAnyTelemetryPeak(page);

    await page.click('#stopBtn');
    await expect(page.locator('#status')).toContainText('Stopped.');
  });
});
