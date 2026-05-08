const { test, expect } = require('@playwright/test');

const PAN_CENTER_GAIN = 0.7071067811865476;
const HOT_SWAP_CROSSFADE_SAMPLES = 128;
const TOPOLOGY_EDIT_CROSSFADE_SAMPLES = 1024;

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

async function firstTelemetry(page) {
  return page.evaluate(() => window.__moondspFirstTelemetry);
}

async function currentTelemetry(page) {
  return page.evaluate(() => window.__moondspTelemetry);
}

async function hotSwapQueued(page) {
  return page.evaluate(() => window.__moondspHotSwapQueued);
}

async function stereoHotSwapQueued(page) {
  return page.evaluate(() => window.__moondspStereoHotSwapQueued);
}

async function topologyEditQueued(page) {
  return page.evaluate(() => window.__moondspTopologyEditQueued);
}

async function stereoTopologyEditQueued(page) {
  return page.evaluate(() => window.__moondspStereoTopologyEditQueued);
}

async function telemetryHistory(page) {
  return page.evaluate(() => window.__moondspTelemetryHistory);
}

function previewEnergy(samples) {
  return samples.reduce((sum, sample) => sum + Math.abs(sample), 0);
}

function previewVariation(samples) {
  let total = 0;
  for (let index = 1; index < samples.length; index += 1) {
    total += Math.abs(samples[index] - samples[index - 1]);
  }
  return total;
}

function hotSwapExpectedSample(index) {
  const progress = index / HOT_SWAP_CROSSFADE_SAMPLES;
  const oldGain = Math.cos(progress * Math.PI * 0.5);
  const newGain = Math.sin(progress * Math.PI * 0.5);
  return (0.25 * oldGain) + (0.75 * newGain);
}

function topologyInsertExpectedSample(index, oldValue, newValue) {
  const progress = index / TOPOLOGY_EDIT_CROSSFADE_SAMPLES;
  const oldGain = Math.cos(progress * Math.PI * 0.5);
  const newGain = Math.sin(progress * Math.PI * 0.5);
  return (oldValue * oldGain) + (newValue * newGain);
}

function topologyDeleteExpectedSample(index, oldValue, newValue) {
  const progress = index / TOPOLOGY_EDIT_CROSSFADE_SAMPLES;
  const oldGain = Math.cos(progress * Math.PI * 0.5);
  const newGain = Math.sin(progress * Math.PI * 0.5);
  return (oldValue * oldGain) + (newValue * newGain);
}

function stereoHotSwapExpectedSample(index) {
  return hotSwapExpectedSample(index) * PAN_CENTER_GAIN;
}

function stereoTopologyEditExpectedLeft(index, oldValue, newValue) {
  const progress = index / HOT_SWAP_CROSSFADE_SAMPLES;
  const oldGain = Math.cos(progress * Math.PI * 0.5);
  const newGain = Math.sin(progress * Math.PI * 0.5);
  return (oldValue * oldGain) + (newValue * newGain);
}

function stereoTopologyEditExpectedRight(index, oldValue, newValue) {
  const progress = index / HOT_SWAP_CROSSFADE_SAMPLES;
  const oldGain = Math.cos(progress * Math.PI * 0.5);
  const newGain = Math.sin(progress * Math.PI * 0.5);
  return (oldValue * oldGain) + (newValue * newGain);
}

async function startAudio(page, path) {
  await page.goto(path);
  await page.click('#startBtn');
}

test('browser demo first render proves CompiledStereoDsp feedback recurrence', async ({ page }) => {
  await startAudio(page, '/?freq=0&delaySamples=0');
  await expect(page.locator('#status')).toContainText('CompiledStereoDsp block runtime');
  // The `mix(3,5)` + `gain(0.3)` z^-1 feedback loop, with freq=0 the
  // oscillator drops out, so the loop solves
  //   x = 1.0 + 0.3 * x  →  x = 1/0.7 ≈ 1.4286
  //   post-gain: 0.3 * 1.4286 ≈ 0.4286
  //   post-pan-center: 0.4286 * (1/√2) ≈ 0.30305
  // The feed-forward path alone settles at 0.3 * (1/√2) ≈ 0.2121.
  // Lower bound 0.25 > 0.2121 is the discriminator that proves recurrence;
  // upper bound 0.35 > 0.30305 plateau ensures the loop is bounded (feedback
  // gain < 1), not runaway.
  //
  // Poll directly for actual convergence in the target band [0.25, 0.35].
  // Earlier attempts pinned to sequence=2 (~48ms) or sequence ≥ 8 (~218ms),
  // both proxies for "settled by now" — flaky on CI because Chrome's first-run
  // wasm/JIT warmup stretches effective settling past any fixed block count.
  // Waiting for leftPreview[0] to actually land in the band is robust: the
  // feed-forward path alone peaks at ~0.2121 (below 0.25), so any sample
  // above 0.25 proves feedback recurrence regardless of how many blocks elapsed.
  let telemetry;
  let attempts = 0;
  await expect
    .poll(async () => {
      attempts += 1;
      const history = await telemetryHistory(page);
      if (!history) return null;
      const match = history.find(
        t => t.freq === 0 && t.leftPreview[0] > 0.25 && t.leftPreview[0] < 0.35,
      );
      if (match) telemetry = match;
      return match || null;
    }, { timeout: 10_000 })
    .toBeTruthy();

  // Diagnostic on out-of-band: surface recent telemetry so a real
  // regression (feedback loop broken) is distinguishable from the
  // CI worklet-warmup flake we just stretched past.
  if (telemetry.leftPreview[0] <= 0.25 || telemetry.leftPreview[0] >= 0.35) {
    const history = await telemetryHistory(page);
    const recent = history.slice(-8).map(t => ({
      sequence: t.sequence,
      freq: t.freq,
      lp0: Number(t.leftPreview[0]?.toFixed?.(6) ?? t.leftPreview[0]),
    }));
    throw new Error(
      `Feedback recurrence sample out of band [0.25, 0.35]: ` +
      `leftPreview[0]=${telemetry.leftPreview[0]} at sequence=${telemetry.sequence}, ` +
      `attempts=${attempts}, recent=${JSON.stringify(recent)}`,
    );
  }

  expect(telemetry.freq).toBeCloseTo(0, 9);
  expect(telemetry.leftPreview[0]).toBeGreaterThan(0.25);
  expect(telemetry.leftPreview[0]).toBeLessThan(0.35);
  expect(telemetry.rightPreview[0]).toBeCloseTo(telemetry.leftPreview[0], 9);
});

test('browser demo first render proves StereoDelay startup offset on feedback graph', async ({ page }) => {
  await startAudio(page, '/?delaySamples=0');
  await expect
    .poll(async () => (await firstTelemetry(page))?.sequence || 0, { timeout: 10_000 })
    .toBeGreaterThan(0);
  const zeroDelayTelemetry = await firstTelemetry(page);
  const zeroDelayEnergy = previewEnergy(zeroDelayTelemetry.leftPreview);

  await startAudio(page, '/?delaySamples=24');
  await expect
    .poll(async () => (await firstTelemetry(page))?.sequence || 0, { timeout: 10_000 })
    .toBeGreaterThan(0);
  const delayedTelemetry = await firstTelemetry(page);
  const delayedLeftEnergy = previewEnergy(delayedTelemetry.leftPreview);
  const delayedRightEnergy = previewEnergy(delayedTelemetry.rightPreview);

  expect(zeroDelayEnergy).toBeGreaterThan(0.001);
  expect(delayedLeftEnergy).toBeLessThan(0.000000001);
  expect(delayedRightEnergy).toBeLessThan(0.000000001);
});

test('browser demo retunes stereo feedback gain and reacts to pan', async ({ page }) => {
  await startAudio(page, '/');
  await expect(page.locator('#status')).toContainText('CompiledStereoDsp block runtime');
  await expect
    .poll(async () => (await currentTelemetry(page))?.sequence || 0, { timeout: 10_000 })
    .toBeGreaterThan(0);
  const initialTelemetry = await currentTelemetry(page);

  await setRangeValue(page, '#gainSlider', 50);
  await expect(page.locator('#gainValue')).toHaveText('50');
  // Wait for gain=0.5 to propagate through the one-pole smoother and peak to rise
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return 0;
      }
      return telemetry.sequence > initialTelemetry.sequence &&
        Math.abs(telemetry.gain - 0.5) < 0.000001
        ? telemetry.overallPeak
        : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0.6);
  const retunedTelemetry = await currentTelemetry(page);
  expect(retunedTelemetry.gain).toBeCloseTo(0.5, 6);
  expect(retunedTelemetry.overallPeak).toBeGreaterThan(0.6);
  expect(retunedTelemetry.overallPeak).toBeLessThan(1.01);
  expect(retunedTelemetry.leftPreview.every(Number.isFinite)).toBeTruthy();

  await setRangeValue(page, '#freqSlider', 660);
  await expect(page.locator('#freqValue')).toHaveText('660');
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return 0;
      }
      return Math.abs(telemetry.freq - 660) < 0.000001 ? telemetry.overallPeak : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0.01);

  await setRangeValue(page, '#delaySlider', 0);
  await expect(page.locator('#delayValue')).toHaveText('0');
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return -1;
      }
      return Math.abs(telemetry.delaySamples);
    }, { timeout: 10_000 })
    .toBeLessThan(0.000001);

  // Capture the EXACT telemetry block that satisfies the poll threshold.
  // A follow-up `currentTelemetry(page)` would race: a new block can arrive
  // between the poll match and the fetch, yielding a different (possibly
  // lower) previewVariation for the "captured" value, which then makes the
  // later `highCutoffVariation > lowCutoffVariation` assertion flake.
  await setRangeValue(page, '#cutoffSlider', 180);
  await expect(page.locator('#cutoffValue')).toHaveText('180');
  let lowCutoffTelemetry = null;
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return 0;
      }
      if (Math.abs(telemetry.cutoff - 180) >= 0.000001) {
        return 0;
      }
      const variation = previewVariation(telemetry.leftPreview);
      if (variation > 0.0001) {
        lowCutoffTelemetry = telemetry;
      }
      return variation;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0.0001);
  const lowCutoffVariation = previewVariation(lowCutoffTelemetry.leftPreview);

  await setRangeValue(page, '#cutoffSlider', 4000);
  await expect(page.locator('#cutoffValue')).toHaveText('4000');
  let highCutoffTelemetry = null;
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return 0;
      }
      if (Math.abs(telemetry.cutoff - 4000) >= 0.000001) {
        return 0;
      }
      const variation = previewVariation(telemetry.leftPreview);
      const delta = variation - lowCutoffVariation;
      if (delta > 0.0005) {
        highCutoffTelemetry = telemetry;
      }
      return delta;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0.0005);
  const highCutoffVariation = previewVariation(highCutoffTelemetry.leftPreview);

  expect(previewEnergy(lowCutoffTelemetry.leftPreview)).toBeGreaterThan(0.01);
  expect(highCutoffVariation).toBeGreaterThan(lowCutoffVariation);

  await setRangeValue(page, '#panSlider', -100);
  await expect(page.locator('#panValue')).toHaveText('L100');
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return 0;
      }
      return telemetry.pan <= -1 &&
        telemetry.sequence > retunedTelemetry.sequence
        ? telemetry.leftPeak - telemetry.rightPeak
        : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0.8);

  await setRangeValue(page, '#panSlider', 0);
  await expect(page.locator('#panValue')).toHaveText('center');
  await expect
    .poll(async () => {
      const { left, right } = await renderPeaks(page);
      return Math.abs(left - right);
    }, { timeout: 10_000 })
    .toBeLessThan(0.05);

  await setRangeValue(page, '#panSlider', 100);
  await expect(page.locator('#panValue')).toHaveText('R100');
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return 0;
      }
      return telemetry.pan >= 1 ? telemetry.rightPeak - telemetry.leftPeak : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0.8);
});

test('browser demo falls back to CompiledDsp when stereo init fails', async ({ page }) => {
  await startAudio(page, '/?forceStereoInitFailure=1&freq=440');
  await expect(page.locator('#status')).toContainText('CompiledDsp block runtime');
  await expect(page.locator('#status')).not.toContainText('Processor init failed');
  await expect
    .poll(async () => (await firstTelemetry(page))?.sequence || 0, { timeout: 10_000 })
    .toBeGreaterThan(0);
  const initialTelemetry = await firstTelemetry(page);

  expect(initialTelemetry.leftPreview[0]).toBeCloseTo(0.3, 6);
  expect(initialTelemetry.leftPreview[1]).toBeCloseTo(0.39, 6);
  expect(initialTelemetry.leftPreview[2]).toBeCloseTo(0.417, 6);
  expect(initialTelemetry.leftPreview[3]).toBeCloseTo(0.4251, 6);
  expect(initialTelemetry.rightPreview[0]).toBeCloseTo(initialTelemetry.leftPreview[0], 9);
  expect(initialTelemetry.rightPreview[3]).toBeCloseTo(initialTelemetry.leftPreview[3], 9);

  await setRangeValue(page, '#gainSlider', 50);
  await expect(page.locator('#gainValue')).toHaveText('50');
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return 0;
      }
      return telemetry.sequence > initialTelemetry.sequence &&
        Math.abs(telemetry.gain - 0.5) < 0.000001
        ? telemetry.sequence
        : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0);
  const retunedTelemetry = await currentTelemetry(page);

  expect(retunedTelemetry.gain).toBeCloseTo(0.5, 6);
  expect(retunedTelemetry.leftPreview[0]).toBeGreaterThan(0.7);
  expect(retunedTelemetry.leftPreview[3]).toBeGreaterThan(0.95);
  expect(retunedTelemetry.leftPreview.every(Number.isFinite)).toBeTruthy();
  expect(retunedTelemetry.overallPeak).toBeGreaterThan(0.95);
  expect(retunedTelemetry.overallPeak).toBeLessThan(1.01);
});

test('browser demo proves CompiledDspHotSwap crossfade in the worklet', async ({ page }) => {
  await startAudio(page, '/?hotSwapMono=1');
  await expect(page.locator('#status')).toContainText('CompiledDspHotSwap block runtime');
  await expect
    .poll(async () => (await firstTelemetry(page))?.sequence || 0, { timeout: 10_000 })
    .toBeGreaterThan(0);
  const initialTelemetry = await firstTelemetry(page);

  expect(initialTelemetry.leftPreview.every(sample => Math.abs(sample - 0.25) < 0.000001)).toBeTruthy();
  expect(initialTelemetry.rightPreview.every(sample => Math.abs(sample - 0.25) < 0.000001)).toBeTruthy();

  await page.evaluate(() => {
    window.__moondspNode.port.postMessage({ type: 'queue-hot-swap' });
  });
  await expect
    .poll(async () => (await hotSwapQueued(page))?.telemetrySequence ?? -1, { timeout: 10_000 })
    .toBeGreaterThanOrEqual(initialTelemetry.sequence);
  const queueAck = await hotSwapQueued(page);

  await expect
    .poll(async () => {
      const history = await telemetryHistory(page);
      const match = history.find((telemetry) =>
        telemetry.sequence > queueAck.telemetrySequence &&
        telemetry.leftPreview.some(sample => sample > 0.250001 && sample < 0.75));
      return match?.sequence || 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(queueAck.telemetrySequence);
  const crossfadeTelemetry = (await telemetryHistory(page)).find((telemetry) =>
    telemetry.sequence > queueAck.telemetrySequence &&
    telemetry.leftPreview.some(sample => sample > 0.250001 && sample < 0.75));

  for (let index = 0; index < crossfadeTelemetry.leftPreview.length; index += 1) {
    expect(crossfadeTelemetry.leftPreview[index]).toBeCloseTo(hotSwapExpectedSample(index), 6);
    expect(crossfadeTelemetry.rightPreview[index]).toBeCloseTo(hotSwapExpectedSample(index), 6);
  }
  expect(crossfadeTelemetry.leftPreview[1]).toBeGreaterThan(crossfadeTelemetry.leftPreview[0]);
  expect(crossfadeTelemetry.leftPreview[7]).toBeLessThan(0.4);

  await expect
    .poll(async () => {
      const history = await telemetryHistory(page);
      const match = history.find((telemetry) =>
        telemetry.sequence > crossfadeTelemetry.sequence &&
        telemetry.leftPreview.every(sample => Math.abs(sample - 0.75) < 0.000001));
      return match?.sequence || 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(crossfadeTelemetry.sequence);
  const settledTelemetry = (await telemetryHistory(page)).find((telemetry) =>
    telemetry.sequence > crossfadeTelemetry.sequence &&
    telemetry.leftPreview.every(sample => Math.abs(sample - 0.75) < 0.000001));

  expect(settledTelemetry.leftPreview.every(sample => Math.abs(sample - 0.75) < 0.000001)).toBeTruthy();
  expect(settledTelemetry.rightPreview.every(sample => Math.abs(sample - 0.75) < 0.000001)).toBeTruthy();
  expect(settledTelemetry.overallPeak).toBeCloseTo(0.75, 6);
});

test('browser demo proves CompiledDspTopologyController insert delete roundtrip in the worklet', async ({ page }) => {
  await startAudio(page, '/?topologyEditMono=1');
  await expect(page.locator('#status')).toContainText('CompiledDspTopologyController block runtime');
  await setRangeValue(page, '#gainSlider', 100);
  await expect(page.locator('#gainValue')).toHaveText('100');
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return 0;
      }
      return Math.abs(telemetry.gain - 1.0) < 0.000001 ? telemetry.sequence : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0);
  const initialTelemetry = await currentTelemetry(page);

  expect(initialTelemetry.leftPreview.every(sample => Math.abs(sample - 1.0) < 0.000001)).toBeTruthy();
  expect(initialTelemetry.rightPreview.every(sample => Math.abs(sample - 1.0) < 0.000001)).toBeTruthy();

  // Set gain BEFORE queueing the topology edit to avoid a race where the
  // crossfade completes before the gain message reaches the AudioWorklet.
  await setRangeValue(page, '#gainSlider', 50);
  await expect(page.locator('#gainValue')).toHaveText('50');
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) return 0;
      return Math.abs(telemetry.gain - 0.5) < 0.000001 ? telemetry.sequence : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0);

  await page.evaluate(() => {
    window.__moondspNode.port.postMessage({ type: 'queue-topology-edit' });
  });
  await expect
    .poll(async () => (await topologyEditQueued(page))?.telemetrySequence ?? -1, { timeout: 10_000 })
    .toBeGreaterThanOrEqual(initialTelemetry.sequence);
  const queueAck = await topologyEditQueued(page);

  await expect
    .poll(async () => {
      const history = await telemetryHistory(page);
      const match = history.find((telemetry) =>
        telemetry.sequence > queueAck.telemetrySequence &&
        Math.abs(telemetry.gain - 0.5) < 0.000001 &&
        Math.abs(telemetry.leftPreview[0] - 0.5) < 0.000001 &&
        telemetry.leftPreview.some(sample => sample > 0.5001));
      return match?.sequence || 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(queueAck.telemetrySequence);
  const crossfadeTelemetry = (await telemetryHistory(page)).find((telemetry) =>
    telemetry.sequence > queueAck.telemetrySequence &&
    Math.abs(telemetry.gain - 0.5) < 0.000001 &&
    Math.abs(telemetry.leftPreview[0] - 0.5) < 0.000001 &&
    telemetry.leftPreview.some(sample => sample > 0.5001));

  for (let index = 0; index < crossfadeTelemetry.leftPreview.length; index += 1) {
    expect(crossfadeTelemetry.leftPreview[index]).toBeCloseTo(topologyInsertExpectedSample(index, 0.5, 0.25), 6);
    expect(crossfadeTelemetry.rightPreview[index]).toBeCloseTo(topologyInsertExpectedSample(index, 0.5, 0.25), 6);
  }
  expect(crossfadeTelemetry.leftPreview[1]).toBeGreaterThan(crossfadeTelemetry.leftPreview[0]);
  expect(crossfadeTelemetry.leftPreview[7]).toBeLessThan(0.51);

  await expect
    .poll(async () => {
      const history = await telemetryHistory(page);
      const match = history.find((telemetry) =>
        telemetry.sequence > crossfadeTelemetry.sequence &&
        Math.abs(telemetry.gain - 0.5) < 0.000001 &&
        telemetry.leftPreview.every(sample => Math.abs(sample - 0.25) < 0.000001));
      return match?.sequence || 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(crossfadeTelemetry.sequence);
  const insertedTelemetry = (await telemetryHistory(page)).find((telemetry) =>
    telemetry.sequence > crossfadeTelemetry.sequence &&
    Math.abs(telemetry.gain - 0.5) < 0.000001 &&
    telemetry.leftPreview.every(sample => Math.abs(sample - 0.25) < 0.000001));

  expect(insertedTelemetry.leftPreview.every(sample => Math.abs(sample - 0.25) < 0.000001)).toBeTruthy();
  expect(insertedTelemetry.rightPreview.every(sample => Math.abs(sample - 0.25) < 0.000001)).toBeTruthy();
  expect(insertedTelemetry.overallPeak).toBeCloseTo(0.25, 6);

  await page.evaluate(() => {
    window.__moondspNode.port.postMessage({ type: 'queue-topology-delete-edit' });
  });
  await expect
    .poll(async () => (await topologyEditQueued(page))?.telemetrySequence ?? -1, { timeout: 10_000 })
    .toBeGreaterThanOrEqual(insertedTelemetry.sequence);
  const deleteQueueAck = await topologyEditQueued(page);

  await expect
    .poll(async () => {
      const history = await telemetryHistory(page);
      const match = history.find((telemetry) =>
        telemetry.sequence > deleteQueueAck.telemetrySequence &&
        Math.abs(telemetry.leftPreview[0] - 0.25) < 0.000001 &&
        telemetry.leftPreview.some(sample => sample > 0.251));
      return match?.sequence || 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(deleteQueueAck.telemetrySequence);
  const deleteCrossfadeTelemetry = (await telemetryHistory(page)).find((telemetry) =>
    telemetry.sequence > deleteQueueAck.telemetrySequence &&
    Math.abs(telemetry.leftPreview[0] - 0.25) < 0.000001 &&
    telemetry.leftPreview.some(sample => sample > 0.251));

  for (let index = 0; index < deleteCrossfadeTelemetry.leftPreview.length; index += 1) {
    expect(deleteCrossfadeTelemetry.leftPreview[index]).toBeCloseTo(topologyDeleteExpectedSample(index, 0.25, 0.5), 6);
    expect(deleteCrossfadeTelemetry.rightPreview[index]).toBeCloseTo(topologyDeleteExpectedSample(index, 0.25, 0.5), 6);
  }

  await expect
    .poll(async () => {
      const history = await telemetryHistory(page);
      const match = history.find((telemetry) =>
        telemetry.sequence > deleteCrossfadeTelemetry.sequence &&
        Math.abs(telemetry.gain - 0.5) < 0.000001 &&
        telemetry.leftPreview.every(sample => Math.abs(sample - 0.5) < 0.000001));
      return match?.sequence || 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(deleteCrossfadeTelemetry.sequence);
  const settledTelemetry = (await telemetryHistory(page)).find((telemetry) =>
    telemetry.sequence > deleteCrossfadeTelemetry.sequence &&
    Math.abs(telemetry.gain - 0.5) < 0.000001 &&
    telemetry.leftPreview.every(sample => Math.abs(sample - 0.5) < 0.000001));

  expect(settledTelemetry.leftPreview.every(sample => Math.abs(sample - 0.5) < 0.000001)).toBeTruthy();
  expect(settledTelemetry.rightPreview.every(sample => Math.abs(sample - 0.5) < 0.000001)).toBeTruthy();
  expect(settledTelemetry.overallPeak).toBeCloseTo(0.5, 6);
});

test('browser demo proves CompiledStereoDspTopologyController crossfade in the worklet', async ({ page }) => {
  await startAudio(page, '/?topologyEditStereo=1');
  await expect(page.locator('#status')).toContainText('CompiledStereoDspTopologyController block runtime');
  await setRangeValue(page, '#gainSlider', 100);
  await expect(page.locator('#gainValue')).toHaveText('100');
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return 0;
      }
      return Math.abs(telemetry.gain - 1.0) < 0.000001 ? telemetry.sequence : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0);
  const initialTelemetry = await currentTelemetry(page);

  expect(
    initialTelemetry.leftPreview.every(
      sample => Math.abs(sample - PAN_CENTER_GAIN) < 0.000001,
    ),
  ).toBeTruthy();
  expect(
    initialTelemetry.rightPreview.every(
      sample => Math.abs(sample - PAN_CENTER_GAIN) < 0.000001,
    ),
  ).toBeTruthy();

  // Set gain BEFORE queueing the topology edit to avoid a race where the
  // crossfade completes before the gain message reaches the AudioWorklet.
  await setRangeValue(page, '#gainSlider', 50);
  await expect(page.locator('#gainValue')).toHaveText('50');
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) return 0;
      return Math.abs(telemetry.gain - 0.5) < 0.000001 ? telemetry.sequence : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0);

  await page.evaluate(() => {
    window.__moondspNode.port.postMessage({ type: 'queue-stereo-topology-edit' });
  });
  await expect
    .poll(async () => (await stereoTopologyEditQueued(page))?.telemetrySequence ?? -1, { timeout: 10_000 })
    .toBeGreaterThanOrEqual(initialTelemetry.sequence);
  const queueAck = await stereoTopologyEditQueued(page);

  await expect
    .poll(async () => {
      const history = await telemetryHistory(page);
      const match = history.find((telemetry) =>
        telemetry.sequence > queueAck.telemetrySequence &&
        Math.abs(telemetry.gain - 0.5) < 0.000001 &&
        Math.abs(telemetry.leftPreview[0] - (0.5 * PAN_CENTER_GAIN)) < 0.000001 &&
        telemetry.leftPreview[1] < telemetry.leftPreview[0] &&
        telemetry.rightPreview[1] > telemetry.rightPreview[0]);
      return match?.sequence || 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(queueAck.telemetrySequence);
  const crossfadeTelemetry = (await telemetryHistory(page)).find((telemetry) =>
    telemetry.sequence > queueAck.telemetrySequence &&
    Math.abs(telemetry.gain - 0.5) < 0.000001 &&
    Math.abs(telemetry.leftPreview[0] - (0.5 * PAN_CENTER_GAIN)) < 0.000001 &&
    telemetry.leftPreview[1] < telemetry.leftPreview[0] &&
    telemetry.rightPreview[1] > telemetry.rightPreview[0]);

  for (let index = 0; index < crossfadeTelemetry.leftPreview.length; index += 1) {
    expect(crossfadeTelemetry.leftPreview[index]).toBeCloseTo(
      stereoTopologyEditExpectedLeft(index, 0.5 * PAN_CENTER_GAIN, 0.0),
      6,
    );
    expect(crossfadeTelemetry.rightPreview[index]).toBeCloseTo(
      stereoTopologyEditExpectedRight(index, 0.5 * PAN_CENTER_GAIN, 0.5),
      6,
    );
  }

  await expect
    .poll(async () => {
      const history = await telemetryHistory(page);
      const match = history.find((telemetry) =>
        telemetry.sequence > crossfadeTelemetry.sequence &&
        Math.abs(telemetry.gain - 0.5) < 0.000001 &&
        telemetry.leftPreview.every(sample => Math.abs(sample) < 0.000001) &&
        telemetry.rightPreview.every(sample => Math.abs(sample - 0.5) < 0.000001));
      return match?.sequence || 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(crossfadeTelemetry.sequence);
  const settledTelemetry = (await telemetryHistory(page)).find((telemetry) =>
    telemetry.sequence > crossfadeTelemetry.sequence &&
    Math.abs(telemetry.gain - 0.5) < 0.000001 &&
    telemetry.leftPreview.every(sample => Math.abs(sample) < 0.000001) &&
    telemetry.rightPreview.every(sample => Math.abs(sample - 0.5) < 0.000001));

  expect(settledTelemetry.leftPeak).toBeCloseTo(0.0, 6);
  expect(settledTelemetry.rightPeak).toBeCloseTo(0.5, 6);
  expect(settledTelemetry.overallPeak).toBeCloseTo(0.5, 6);
});

test('browser demo proves exit deliverable FM synthesis in the worklet', async ({ page }) => {
  await startAudio(page, '/?exitDeliverable=1');
  await expect(page.locator('#status')).toContainText('Exit Deliverable FM Synthesis');
  await expect
    .poll(async () => (await firstTelemetry(page))?.sequence || 0, { timeout: 10_000 })
    .toBeGreaterThan(0);
  const initialTelemetry = await firstTelemetry(page);

  // Exit deliverable should produce non-zero output (FM synthesis)
  expect(previewEnergy(initialTelemetry.leftPreview)).toBeGreaterThan(0.001);
  // Mono graph duplicates to both channels
  expect(initialTelemetry.rightPreview[0]).toBeCloseTo(initialTelemetry.leftPreview[0], 9);
  expect(initialTelemetry.rightPreview[3]).toBeCloseTo(initialTelemetry.leftPreview[3], 9);
  expect(initialTelemetry.leftPreview.every(Number.isFinite)).toBeTruthy();

  // Verify LFO rate control reaches the processor
  await setRangeValue(page, '#freqSlider', 10);
  await expect(page.locator('#freqValue')).toHaveText('10');
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return 0;
      }
      return Math.abs(telemetry.freq - 10) < 0.000001 ? telemetry.sequence : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0);
  const lfoTelemetry = await currentTelemetry(page);
  expect(lfoTelemetry.freq).toBeCloseTo(10, 6);
  expect(previewEnergy(lfoTelemetry.leftPreview)).toBeGreaterThan(0.001);

  // Verify gain control reaches the processor
  await setRangeValue(page, '#gainSlider', 10);
  await expect(page.locator('#gainValue')).toHaveText('10');
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return 0;
      }
      return Math.abs(telemetry.gain - 0.1) < 0.000001 &&
        telemetry.sequence > lfoTelemetry.sequence
        ? telemetry.overallPeak
        : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0.001);
  const lowGainTelemetry = await currentTelemetry(page);
  expect(lowGainTelemetry.overallPeak).toBeLessThan(initialTelemetry.overallPeak);

  // Verify cutoff control reaches the processor
  await setRangeValue(page, '#cutoffSlider', 200);
  await expect(page.locator('#cutoffValue')).toHaveText('200');
  await expect
    .poll(async () => {
      const telemetry = await currentTelemetry(page);
      if (!telemetry) {
        return 0;
      }
      return Math.abs(telemetry.cutoff - 200) < 0.000001 &&
        telemetry.sequence > lowGainTelemetry.sequence
        ? previewVariation(telemetry.leftPreview)
        : 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(0.0001);
});

test('browser demo proves CompiledStereoDspHotSwap crossfade in the worklet', async ({ page }) => {
  await startAudio(page, '/?hotSwapStereo=1');
  await expect(page.locator('#status')).toContainText('CompiledStereoDspHotSwap block runtime');
  await expect
    .poll(async () => (await firstTelemetry(page))?.sequence || 0, { timeout: 10_000 })
    .toBeGreaterThan(0);
  const initialTelemetry = await firstTelemetry(page);

  expect(
    initialTelemetry.leftPreview.every(
      sample => Math.abs(sample - (0.25 * PAN_CENTER_GAIN)) < 0.000001,
    ),
  ).toBeTruthy();
  expect(
    initialTelemetry.rightPreview.every(
      sample => Math.abs(sample - (0.25 * PAN_CENTER_GAIN)) < 0.000001,
    ),
  ).toBeTruthy();

  await page.evaluate(() => {
    window.__moondspNode.port.postMessage({ type: 'queue-stereo-hot-swap' });
  });
  await expect
    .poll(async () => (await stereoHotSwapQueued(page))?.telemetrySequence ?? -1, { timeout: 10_000 })
    .toBeGreaterThanOrEqual(initialTelemetry.sequence);
  const queueAck = await stereoHotSwapQueued(page);

  await expect
    .poll(async () => {
      const history = await telemetryHistory(page);
      const match = history.find((telemetry) =>
        telemetry.sequence > queueAck.telemetrySequence &&
        telemetry.leftPreview.some(sample =>
          sample > (0.25 * PAN_CENTER_GAIN + 0.000001) &&
          sample < (0.75 * PAN_CENTER_GAIN)));
      return match?.sequence || 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(queueAck.telemetrySequence);
  const crossfadeTelemetry = (await telemetryHistory(page)).find((telemetry) =>
    telemetry.sequence > queueAck.telemetrySequence &&
    telemetry.leftPreview.some(sample =>
      sample > (0.25 * PAN_CENTER_GAIN + 0.000001) &&
      sample < (0.75 * PAN_CENTER_GAIN)));

  for (let index = 0; index < crossfadeTelemetry.leftPreview.length; index += 1) {
    expect(crossfadeTelemetry.leftPreview[index]).toBeCloseTo(stereoHotSwapExpectedSample(index), 6);
    expect(crossfadeTelemetry.rightPreview[index]).toBeCloseTo(stereoHotSwapExpectedSample(index), 6);
  }

  await expect
    .poll(async () => {
      const history = await telemetryHistory(page);
      const match = history.find((telemetry) =>
        telemetry.sequence > crossfadeTelemetry.sequence &&
        telemetry.leftPreview.every(
          sample => Math.abs(sample - (0.75 * PAN_CENTER_GAIN)) < 0.000001,
        ) &&
        telemetry.rightPreview.every(
          sample => Math.abs(sample - (0.75 * PAN_CENTER_GAIN)) < 0.000001,
        ));
      return match?.sequence || 0;
    }, { timeout: 10_000 })
    .toBeGreaterThan(crossfadeTelemetry.sequence);
  const settledTelemetry = (await telemetryHistory(page)).find((telemetry) =>
    telemetry.sequence > crossfadeTelemetry.sequence &&
    telemetry.leftPreview.every(
      sample => Math.abs(sample - (0.75 * PAN_CENTER_GAIN)) < 0.000001,
    ) &&
    telemetry.rightPreview.every(
      sample => Math.abs(sample - (0.75 * PAN_CENTER_GAIN)) < 0.000001,
    ));

  expect(settledTelemetry.overallPeak).toBeCloseTo(0.75 * PAN_CENTER_GAIN, 6);
});
