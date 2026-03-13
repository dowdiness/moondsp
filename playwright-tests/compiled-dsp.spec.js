const { test, expect } = require('@playwright/test');

async function setRangeValue(page, selector, value) {
  await page.locator(selector).evaluate((element, nextValue) => {
    element.value = String(nextValue);
    element.dispatchEvent(new Event('input', { bubbles: true }));
  }, value);
}

async function meterWidth(page, selector) {
  return page.locator(selector).evaluate((element) => {
    const width = element.style.width || '0';
    return Number.parseFloat(width);
  });
}

async function stereoWidths(page) {
  const [left, right] = await Promise.all([
    meterWidth(page, '#leftMeterFill'),
    meterWidth(page, '#rightMeterFill'),
  ]);
  return { left, right };
}

async function startAudio(page, path) {
  await page.goto(path);
  await page.click('#startBtn');
}

test('browser demo reports CompiledStereoDsp mode and reacts to pan', async ({ page }) => {
  await startAudio(page, '/');
  await expect(page.locator('#status')).toContainText('CompiledStereoDsp block runtime');

  await expect.poll(() => meterWidth(page, '#meterFill'), { timeout: 10_000 }).toBeGreaterThan(0.5);

  await setRangeValue(page, '#gainSlider', 55);
  await setRangeValue(page, '#freqSlider', 660);
  await expect(page.locator('#gainValue')).toHaveText('55');
  await expect(page.locator('#freqValue')).toHaveText('660');

  await setRangeValue(page, '#panSlider', -100);
  await expect(page.locator('#panValue')).toHaveText('-100');
  await expect
    .poll(async () => {
      const { left, right } = await stereoWidths(page);
      return left - right;
    }, { timeout: 10_000 })
    .toBeGreaterThan(15);

  await setRangeValue(page, '#panSlider', 0);
  await expect(page.locator('#panValue')).toHaveText('0');
  await expect
    .poll(async () => {
      const { left, right } = await stereoWidths(page);
      return Math.abs(left - right);
    }, { timeout: 10_000 })
    .toBeLessThan(8);

  await setRangeValue(page, '#panSlider', 100);
  await expect(page.locator('#panValue')).toHaveText('100');
  await expect
    .poll(async () => {
      const { left, right } = await stereoWidths(page);
      return right - left;
    }, { timeout: 10_000 })
    .toBeGreaterThan(15);
});

test('browser demo falls back to CompiledDsp when stereo init fails', async ({ page }) => {
  await startAudio(page, '/?forceStereoInitFailure=1');
  await expect(page.locator('#status')).toContainText('CompiledDsp block runtime');
  await expect(page.locator('#status')).not.toContainText('Processor init failed');
  await expect.poll(() => meterWidth(page, '#meterFill'), { timeout: 10_000 }).toBeGreaterThan(0.5);

  await setRangeValue(page, '#gainSlider', 40);
  await setRangeValue(page, '#freqSlider', 550);
  await expect(page.locator('#gainValue')).toHaveText('40');
  await expect(page.locator('#freqValue')).toHaveText('550');
  await expect.poll(() => meterWidth(page, '#meterFill'), { timeout: 10_000 }).toBeGreaterThan(0.5);
});
