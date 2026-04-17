// spec: specs/scheduler-pattern.md
// seed: playwright-tests/seed.spec.ts

const { test, expect } = require('@playwright/test');

async function setRangeValue(page, selector, value) {
  await page.locator(selector).evaluate((element, nextValue) => {
    element.value = String(nextValue);
    element.dispatchEvent(new Event('input', { bubbles: true }));
  }, value);
}

async function renderPeaks(page) {
  const [overall, left, right] = await Promise.all([
    page.locator('#renderPeakValue').textContent(),
    page.locator('#renderLeftPeakValue').textContent(),
    page.locator('#renderRightPeakValue').textContent(),
  ]);
  return {
    overall: Number.parseFloat(overall || '0'),
    left: Number.parseFloat(left || '0'),
    right: Number.parseFloat(right || '0'),
  };
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

    // 2. Wait for audio to process and telemetry to arrive
    await expect
      .poll(async () => {
        const peaks = await renderPeaks(page);
        return peaks.overall;
      }, { timeout: 10_000 })
      .toBeGreaterThan(0);

    // 3. Verify signal is flowing
    const peaks = await renderPeaks(page);
    expect(peaks.overall).toBeGreaterThan(0);
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

    // Clear and type new pattern
    await page.locator('#patternInput').fill('s("bd sd hh sd")');
    await page.click('button:has-text("Eval")');

    // Verify pattern was accepted
    await expect(page.locator('#patternStatus')).toContainText('Pattern updated');

    // Poll for audio signal — peaks reflect the most recent audio block, so
    // a 300ms hardcoded wait can miss the signal on slow workers.
    await expect
      .poll(async () => {
        const peaks = await renderPeaks(page);
        return peaks.overall;
      }, { timeout: 10_000 })
      .toBeGreaterThan(0);
  });

  test('Eval a note pattern via Enter key', async ({ page }) => {
    await startScheduler(page);
    await expect(page.locator('#patternStatus')).toContainText('Pattern updated', { timeout: 5_000 });

    // Clear, type, and press Enter
    await page.locator('#patternInput').fill('note("60 64 67")');
    await page.locator('#patternInput').press('Enter');

    // Verify pattern was accepted
    await expect(page.locator('#patternStatus')).toContainText('Pattern updated');

    // Poll for audio signal — same reason as drum pattern test above.
    await expect
      .poll(async () => {
        const peaks = await renderPeaks(page);
        return peaks.overall;
      }, { timeout: 10_000 })
      .toBeGreaterThan(0);
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

    // Wait for audio to start
    await expect
      .poll(async () => {
        const peaks = await renderPeaks(page);
        return peaks.overall;
      }, { timeout: 10_000 })
      .toBeGreaterThan(0);

    // Set gain to 0
    await setRangeValue(page, '#schedulerGainSlider', 0);

    // No fixed sleep: expect.poll already retries until peaks drop, and the
    // prior 500ms waitForTimeout was belt-and-suspenders that only served to
    // mask CI-side jitter (the retry-masked flake this replaces). A longer
    // poll timeout is the deterministic equivalent — the gain ramp takes
    // roughly one telemetry interval (~21ms) to propagate.
    await expect
      .poll(async () => {
        const peaks = await renderPeaks(page);
        return peaks.overall;
      }, { timeout: 10_000 })
      .toBeLessThan(0.001);
  });
});

test.describe('Stop and Restart', () => {
  test('Stop button silences audio', async ({ page }) => {
    await startScheduler(page);
    await expect(page.locator('#patternStatus')).toContainText('Pattern updated', { timeout: 5_000 });

    // Wait for audio to actually start producing signal, rather than a fixed
    // 300ms timeout that can miss the signal on slow workers (the retry-masked
    // flake this replaces). Stop is only meaningful once audio is live.
    await expect
      .poll(async () => {
        const peaks = await renderPeaks(page);
        return peaks.overall;
      }, { timeout: 10_000 })
      .toBeGreaterThan(0);

    await page.click('#stopBtn');
    await expect(page.locator('#status')).toContainText('Stopped.');
  });
});
