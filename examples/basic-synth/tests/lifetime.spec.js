import { test, expect } from '@playwright/test';

async function powerOn(page) {
  await page.getByRole('button', { name: 'Power on audio', exact: true }).click();
  await expect(page.getByRole('button', { name: 'C4, computer key A', exact: true })).toBeEnabled();
}

test.beforeEach(async ({ page }) => {
  // Capture the real node; fault injection calls the browser error handler,
  // rather than replacing the engine or pretending to crash the DSP.
  await page.addInitScript(() => {
    const NativeNode = window.AudioWorkletNode;
    window.AudioWorkletNode = class extends NativeNode {
      constructor(...args) {
        super(...args);
        window.synthNode = this;
      }
    };
  });
  await page.goto('/');
  await expect(page.getByRole('button', { name: 'Power on audio', exact: true })).toBeEnabled();
});

test('processor failure is visible without another control action and retry restores the UI', async ({ page }) => {
  await powerOn(page);
  await page.evaluate(() => {
    window.synthNode.onprocessorerror(new Event('processorerror'));
  });
  await expect(page.getByRole('alert')).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('PROCESSOR_FAILED');
  await expect(page.getByRole('slider', { name: /Volume/ })).toBeDisabled();

  await powerOn(page);
  await expect(page.getByRole('alert')).toBeHidden();
  await page.getByRole('button', { name: 'Power off audio', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Power on audio', exact: true })).toBeEnabled();
  await expect(page.getByRole('alert')).toBeHidden();
});

test('caller context closure is normal termination and late failure cannot damage a replacement', async ({ page }) => {
  await powerOn(page);
  await page.evaluate(async () => {
    window.retiredFailure = window.synthNode.onprocessorerror;
    await window.synthNode.context.close();
  });
  await expect(page.getByRole('button', { name: 'Power on audio', exact: true })).toBeEnabled();
  await expect(page.getByRole('alert')).toBeHidden();
  await powerOn(page);
  await page.evaluate(() => window.retiredFailure(new Event('processorerror')));
  await expect(page.getByRole('alert')).toBeHidden();
  await page.getByRole('button', { name: 'Power off audio', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Power on audio', exact: true })).toBeEnabled();
});

test('power off during Wasm loading returns the UI to idle and permits a fresh start', async ({ page }) => {
  let releaseDownload;
  let markRequested;
  const download = new Promise(resolve => { releaseDownload = resolve; });
  const requested = new Promise(resolve => { markRequested = resolve; });
  await page.route('**/*.wasm', async route => {
    markRequested();
    await download;
    await route.continue();
  });
  await page.reload();
  await page.getByRole('button', { name: 'Power on audio', exact: true }).click();
  await requested;
  await page.getByRole('button', { name: 'Power off audio', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Power on audio', exact: true })).toBeEnabled();
  releaseDownload();
  await page.unrouteAll({ behavior: 'wait' });

  await powerOn(page);
  await expect(page.getByRole('alert')).toBeHidden();
  await page.getByRole('button', { name: 'Power off audio', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Power on audio', exact: true })).toBeEnabled();
});

test('power off during a pending mount permits retry without a late UI update', async ({ page }) => {
  await page.addInitScript(() => {
    const NativeNode = window.AudioWorkletNode;
    let held = false;
    window.AudioWorkletNode = class extends NativeNode {
      constructor(...args) {
        super(...args);
        const send = this.port.postMessage.bind(this.port);
        this.port.postMessage = (message, ...rest) => {
          if (!held && message.type === 'mount') {
            held = true;
            window.releaseMount = () => send(message, ...rest);
          } else send(message, ...rest);
        };
      }
    };
  });
  await page.reload();
  await page.getByRole('button', { name: 'Power on audio', exact: true }).click();
  await expect.poll(() => page.evaluate(() => typeof window.releaseMount)).toBe('function');
  await page.getByRole('button', { name: 'Power off audio', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Power on audio', exact: true })).toBeEnabled();
  await powerOn(page);
  await page.evaluate(() => window.releaseMount());
  await expect(page.getByRole('alert')).toBeHidden();
  await page.getByRole('button', { name: 'Power off audio', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Power on audio', exact: true })).toBeEnabled();
});

test('a retired resume completion cannot block or change a replacement session', async ({ page }) => {
  await powerOn(page);
  // Keep the real resume call, delaying only its completion as seen by the app.
  await page.evaluate(async () => {
    const context = window.synthNode.context;
    await context.suspend();
    const resume = context.resume.bind(context);
    context.resume = () => resume().then(() => new Promise(resolve => {
      window.releaseResume = resolve;
    }));
  });
  await page.getByRole('button', { name: 'Power on audio', exact: true }).click();
  await expect.poll(() => page.evaluate(() => typeof window.releaseResume)).toBe('function');
  await page.getByRole('button', { name: 'Power off audio', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Power on audio', exact: true })).toBeEnabled();
  await powerOn(page);
  await page.evaluate(() => window.releaseResume());
  await expect(page.getByRole('button', { name: 'C4, computer key A', exact: true })).toBeEnabled();
  await expect(page.getByRole('alert')).toBeHidden();
  await page.getByRole('button', { name: 'Power off audio', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Power on audio', exact: true })).toBeEnabled();
});

test('one Power on gesture reaches audible playback after activation expires during loading', async ({ page }) => {
  // Playwright evaluate() grants a user gesture. These reads must not renew it.
  const client = await page.context().newCDPSession(page);
  const withoutGesture = async expression => {
    const response = await client.send('Runtime.evaluate', { expression, returnByValue: true, userGesture: false });
    return response.result.value;
  };
  let releaseDownload;
  let markRequested;
  const download = new Promise(resolve => { releaseDownload = resolve; });
  const requested = new Promise(resolve => { markRequested = resolve; });
  await page.route('**/*.wasm', async route => {
    markRequested();
    await download;
    await route.continue();
  });
  await page.getByRole('button', { name: 'Power on audio', exact: true }).click();
  await requested;
  await expect.poll(() => withoutGesture('navigator.userActivation.isActive'), { timeout: 8000 }).toBe(false);
  releaseDownload();
  await page.unrouteAll({ behavior: 'wait' });
  await expect.poll(() => withoutGesture('document.querySelector(\'[aria-label=\"C4, computer key A\"]\').disabled')).toBe(false);
  await client.detach();
  await page.evaluate(() => {
    const analyser = window.synthNode.context.createAnalyser();
    window.synthNode.connect(analyser);
    const samples = new Float32Array(analyser.fftSize);
    window.rms = () => {
      analyser.getFloatTimeDomainData(samples);
      return Math.sqrt(samples.reduce((sum, sample) => sum + sample * sample, 0) / samples.length);
    };
  });
  await page.keyboard.down('a');
  await expect.poll(() => page.evaluate(() => window.rms())).toBeGreaterThan(0.01);
  await page.keyboard.up('a');
  await expect.poll(() => page.evaluate(() => window.rms())).toBeLessThan(0.00001);
  await page.getByRole('button', { name: 'Power off audio', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Power on audio', exact: true })).toBeEnabled();
});
