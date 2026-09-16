const { test, expect } = require('@playwright/test');

test.use({ launchOptions: { args: ['--disable-audio-output', '--autoplay-policy=user-gesture-required'] } });
test.setTimeout(30_000);

const GRAPH = {
  nodes: [
    { type: 'oscillator', waveform: 'sine', frequency: 220 },
    { type: 'gain', input: 0, gain: 0.15 },
    { type: 'output', input: 1 },
  ],
};

async function open(page) {
  await page.goto('/graph-example.html');
  await page.evaluate(() => {
    window.__audioPower = import('/audio-power.js');
    window.__audioPower.then(({ AudioPower }) => { window.__AudioPower = AudioPower; });
  });
  await expect.poll(() => page.evaluate(() => typeof window.__AudioPower)).toBe('function');
}

async function installNodeCounter(page) {
  await page.addInitScript(() => {
    window.__nodeCount = 0;
    const Native = window.AudioWorkletNode;
    window.AudioWorkletNode = class extends Native {
      constructor(...args) {
        super(...args);
        window.__nodeCount += 1;
      }
    };
  });
}

async function audible(page) {
  return page.evaluate(() => {
    const { context } = window.__active;
    const engine = window.__engine;
    const analyser = context.createAnalyser();
    analyser.fftSize = 2048;
    engine.output.connect(analyser);
    analyser.connect(context.destination);
    const samples = new Float32Array(analyser.fftSize);
    window.__rms = () => {
      analyser.getFloatTimeDomainData(samples);
      return Math.sqrt(samples.reduce((sum, sample) => sum + sample * sample, 0) / samples.length);
    };
  });
}

async function turnOn(page, body = `async ({ engine }) => { const graph = await engine.mount(${JSON.stringify(GRAPH)}); await graph.play(); return graph; }`) {
  return page.evaluate(async source => {
    const power = window.__power ?? window.__AudioPower();
    const original = (0, eval)(`(${source})`);
    const setup = async audio => { window.__engine = audio.engine; return original(audio); };
    const powered = power.turnOn(setup);
    window.__power = power;
    window.__active = powered;
    window.__ready = powered.ready;
    window.__ended = powered.ended;
    window.__ready.catch(() => {});
    window.__ended.catch(() => {});
    return { contextState: powered.context.state };
  }, body);
}

async function turnOff(page) {
  return page.evaluate(() => window.__active.turnOff());
}

// The direct tests intentionally use only AudioPower's public values. Native globals
// are wrapped solely to make real worklet/context races deterministic.
test('1. one gesture preserves admission through delayed Wasm and produces audible output', async ({ page }) => {
  await open(page);
  let release;
  let requested;
  const wasm = new Promise(resolve => { release = resolve; });
  const request = new Promise(resolve => { requested = resolve; });
  await page.route('**/*.wasm', async route => { requested(); await wasm; await route.continue(); });
  await page.evaluate(() => {
    const button = document.createElement('button');
    button.textContent = 'start';
    document.body.append(button);
    button.onclick = async () => {
      const power = window.__AudioPower();
      const value = { marker: 'setup-value' };
      const powered = power.turnOn(async ({ engine }) => {
        window.__engine = engine;
        window.__setupValue = value;
        const graph = await engine.mount({ nodes: [
          { type: 'oscillator', waveform: 'sine', frequency: 220 },
          { type: 'gain', input: 0, gain: 0.15 },
          { type: 'output', input: 1 },
        ] });
        await graph.play();
        return value;
      });
      window.__power = power; window.__active = powered;
      window.__ready = powered.ready; window.__ended = powered.ended;
      window.__ready.catch(() => {}); window.__ended.catch(() => {});
    };
  });
  await page.getByRole('button', { name: 'start' }).click();
  await request;
  const client = await page.context().newCDPSession(page);
  const withoutGesture = expression => client.send('Runtime.evaluate', {
    expression, returnByValue: true, userGesture: false, awaitPromise: true,
  }).then(result => result.result.value);
  await expect.poll(() => withoutGesture('navigator.userActivation.isActive'), { timeout: 8000 }).toBe(false);
  release();
  expect(await withoutGesture('window.__ready.then(value => value === window.__setupValue)')).toBe(true);
  expect(await withoutGesture('window.__active.context.state')).toBe('running');
  await client.detach();
  await audible(page);
  await expect.poll(() => page.evaluate(() => window.__active.context.state)).toBe('running');
  await expect.poll(() => page.evaluate(() => window.__rms()), { timeout: 8_000 }).toBeGreaterThan(0.01);
  expect(await page.evaluate(() => window.__ready.then(value => value === window.__setupValue))).toBe(true);
  await turnOff(page);
});

test('2. turning off during Wasm aborts readiness and closes the owned context', async ({ page }) => {
  await open(page);
  let release;
  let requested;
  const wasm = new Promise(resolve => { release = resolve; });
  const requestedPromise = new Promise(resolve => { requested = resolve; });
  await page.route('**/*.wasm', async route => { requested(); await wasm; await route.continue(); });
  await turnOn(page);
  await requestedPromise;
  const result = await page.evaluate(async () => {
    const ready = window.__ready.then(() => 'ok', error => error.name);
    const off = window.__active.turnOff();
    const ended = window.__ended;
    window.__lateReady = ready;
    window.__lateEnded = ended;
    return await off;
  });
  expect(result).toBeUndefined();
  release();
  await expect.poll(() => page.evaluate(() => window.__lateReady)).toBe('AbortError');
  await expect.poll(() => page.evaluate(() => window.__active.context.state)).toBe('closed');
  await expect.poll(() => page.evaluate(() => window.__lateEnded)).toEqual({ reason: 'turnedOff' });
});

test('3. turning off during a held real mount does not await or publish the mount', async ({ page }) => {
  await open(page);
  await page.addInitScript(() => {
    const Native = window.AudioWorkletNode;
    window.AudioWorkletNode = class extends Native {
      constructor(...args) {
        super(...args);
        const post = this.port.postMessage.bind(this.port);
        this.port.postMessage = (message, ...rest) => {
          if (message.type === 'mount') {
            const receive = this.port.onmessage;
            this.port.onmessage = event => {
              if (event.data.id === message.id) {
                window.__releaseMount = () => receive(event);
              } else receive(event);
            };
          }
          post(message, ...rest);
        };
      }
    };
  });
  await open(page);
  await turnOn(page);
  await expect.poll(() => page.evaluate(() => typeof window.__releaseMount)).toBe('function');
  const off = await page.evaluate(() => window.__active.turnOff());
  expect(off).toBeUndefined();
  await expect.poll(() => page.evaluate(() => window.__active.context.state)).toBe('closed');
  await page.evaluate(() => window.__releaseMount());
  await expect.poll(() => page.evaluate(() => window.__ready.then(() => 'ok', e => e.name))).toBe('AbortError');
});

test('4. processor failure is retained as GraphEngineError and cleanup follows', async ({ page }) => {
  await open(page);
  await turnOn(page);
  await expect.poll(() => page.evaluate(() => window.__ready.then(() => true, () => false))).toBe(true);
  const result = await page.evaluate(async () => {
    window.__engine.output.onprocessorerror(new Event('processorerror'));
    const end = await window.__ended;
    const exit = await window.__engine.wait();
    const { GraphEngineError } = await import('/graph-engine.js');
    return {
      reason: end.reason,
      code: end.error.code,
      sameError: end.error === exit.error,
      typed: end.error instanceof GraphEngineError,
    };
  });
  expect(result).toEqual({ reason: 'failed', code: 'PROCESSOR_FAILED', sameError: true, typed: true });
  await expect.poll(() => page.evaluate(() => window.__active.context.state)).toBe('closed');
});

test('5. replacement waits for the cumulative predecessor retirement barrier', async ({ page }) => {
  await installNodeCounter(page);
  await open(page);
  await turnOn(page);
  await page.evaluate(() => window.__ready);
  await page.evaluate(() => {
    window.__a = window.__active;
    const context = window.__a.context;
    const close = context.close.bind(context);
    const gate = new Promise(resolve => { window.__releaseA = resolve; });
    context.close = () => close().then(() => gate);
    window.__engine.output.onprocessorerror(new Event('processorerror'));
  });
  await page.evaluate(() => window.__a.ended);
  await turnOn(page);
  await expect.poll(() => page.evaluate(() => window.__active.context.state)).toBe('suspended');
  // B retires while still awaiting A. Its own cleanup can finish independently.
  await page.evaluate(async () => {
    window.__b = window.__active;
    await window.__b.turnOff();
  });
  await turnOn(page);
  await expect.poll(() => page.evaluate(() => window.__active.context.state)).toBe('suspended');
  expect(await page.evaluate(() => window.__nodeCount)).toBe(1);
  await page.evaluate(() => window.__releaseA());
  await page.evaluate(() => window.__ready);
  expect(await page.evaluate(() => window.__nodeCount)).toBe(2);
  // Neither retired capability can affect the replacement.
  await page.evaluate(() => Promise.all([window.__a.turnOff(), window.__b.turnOff()]));
  expect(await page.evaluate(() => window.__active.context.state)).toBe('running');
  await audible(page);
  await expect.poll(() => page.evaluate(() => window.__rms()), { timeout: 8_000 }).toBeGreaterThan(0.01);
  await turnOff(page);
});

test('6. duplicate turn-on is invalid, while a separate owner is independent', async ({ page }) => {
  await page.addInitScript(() => {
    const Native = window.AudioContext;
    window.__contextCount = 0;
    window.AudioContext = class extends Native {
      constructor(...args) {
        super(...args);
        window.__contextCount += 1;
      }
    };
  });
  await open(page);
  const result = await page.evaluate(() => {
    const first = window.__AudioPower();
    const setup = async ({ engine }) => { const graph = await engine.mount({ nodes: [{ type: 'oscillator', waveform: 'sine', frequency: 220 }, { type: 'output', input: 0 }] }); await graph.play(); return graph; };
    const powered = first.turnOn(setup);
    powered.ready.catch(() => {}); powered.ended.catch(() => {});
    let error;
    try { first.turnOn(setup); } catch (caught) { error = caught; }
    const afterDuplicate = window.__contextCount;
    const second = window.__AudioPower();
    const other = second.turnOn(setup);
    other.ready.catch(() => {}); other.ended.catch(() => {});
    window.__power = first; window.__active = powered; window.__other = other;
    return { name: error?.name, afterDuplicate, total: window.__contextCount };
  });
  expect(result.name).toBe('InvalidStateError');
  expect(result.afterDuplicate).toBe(1);
  expect(result.total).toBe(2);
  await page.evaluate(() => Promise.all([window.__active.ready, window.__other.ready]));
  await turnOff(page);
  expect(await page.evaluate(() => window.__other.context.state)).toBe('running');
  await page.evaluate(() => window.__other.turnOff());
});

test('7. immediate external close gates admission before setup and worklet creation', async ({ page }) => {
  await open(page);
  await installNodeCounter(page);
  await page.addInitScript(() => {
    const native = AudioContext.prototype.resume;
    let first = true;
    AudioContext.prototype.resume = function () {
      const result = native.call(this);
      if (!first) return result;
      first = false;
      window.__admissionStarted = true;
      window.__admissionGate = new Promise(resolve => { window.__releaseAdmission = resolve; });
      return result.then(() => window.__admissionGate);
    };
  });
  await open(page);
  const result = await page.evaluate(() => {
    window.__setupCalls = 0;
    const power = window.__AudioPower();
    const powered = power.turnOn(async ({ engine }) => { window.__setupCalls += 1; return engine; });
    powered.ready.catch(() => {}); powered.ended.catch(() => {});
    window.__power = power; window.__active = powered; window.__ready = powered.ready; window.__ended = powered.ended;
    return powered.context.close().then(() => 'closed');
  });
  expect(result).toBe('closed');
  await expect.poll(() => page.evaluate(() => window.__admissionStarted)).toBe(true);
  await page.evaluate(() => window.__releaseAdmission());
  await expect.poll(() => page.evaluate(() => window.__ready.then(() => 'ok', e => e.name))).toBe('AbortError');
  expect(await page.evaluate(() => ({ setup: window.__setupCalls, nodes: window.__nodeCount }))).toEqual({ setup: 0, nodes: 0 });
  await expect.poll(() => page.evaluate(() => window.__ended)).toEqual({ reason: 'turnedOff' });
});

test('8. external close after setup entered aborts held setup and engine cleanup', async ({ page }) => {
  await open(page);
  await page.evaluate(() => {
    window.__entered = new Promise(resolve => { window.__enterSetup = resolve; });
    const power = window.__AudioPower();
    const powered = power.turnOn(async ({ engine, powerOff }) => {
      window.__capturedEngine = engine;
      window.__powerOff = powerOff;
      window.__enterSetup();
      await new Promise(resolve => { window.__releaseSetup = resolve; });
      return { late: true };
    });
    powered.ready.catch(() => {}); powered.ended.catch(() => {});
    window.__power = power; window.__active = powered; window.__ready = powered.ready; window.__ended = powered.ended;
  });
  await page.evaluate(() => window.__entered);
  await page.evaluate(() => window.__active.context.close());
  await expect.poll(() => page.evaluate(() => window.__powerOff.aborted)).toBe(true);
  await expect.poll(() => page.evaluate(() => window.__ready.then(() => 'ok', e => e.name))).toBe('AbortError');
  await expect.poll(() => page.evaluate(() => window.__ended)).toEqual({ reason: 'turnedOff' });
  await expect.poll(() => page.evaluate(() => window.__capturedEngine.wait().then(value => value.type))).toBe('closed');
  await page.evaluate(() => window.__releaseSetup());
  await expect.poll(() => page.evaluate(() => window.__ready.then(() => 'ok', e => e.name))).toBe('AbortError');
});

test('9. setup failure preserves sentinel identity and a replacement succeeds', async ({ page }) => {
  await open(page);
  const result = await page.evaluate(async () => {
    const power = window.__AudioPower();
    const sentinel = new Error('sentinel setup failure');
    const first = power.turnOn(async () => { throw sentinel; });
    first.ready.catch(() => {}); first.ended.catch(() => {});
    const readyError = await first.ready.catch(error => error);
    const ended = await first.ended;
    const second = power.turnOn(async ({ engine }) => engine);
    second.ready.catch(() => {}); second.ended.catch(() => {});
    const replacement = await second.ready;
    await second.turnOff();
    return { same: readyError === sentinel, endedError: ended.error === sentinel, replacement: typeof replacement };
  });
  expect(result).toEqual({ same: true, endedError: true, replacement: 'object' });
});

test('10. turn-off and ended are idempotent retained promises/results', async ({ page }) => {
  await open(page);
  await turnOn(page);
  await expect.poll(() => page.evaluate(() => window.__ready.then(() => true, () => false))).toBe(true);
  const result = await page.evaluate(async () => {
    const a = window.__active.turnOff();
    const b = window.__active.turnOff();
    const early = window.__ended;
    await a;
    const late = await window.__ended;
    return { sameOff: a === b, sameEnded: early === window.__ended, frozen: Object.isFrozen(late), sameResult: late === await window.__ended, result: late };
  });
  expect(result).toEqual({ sameOff: true, sameEnded: true, frozen: true, sameResult: true, result: { reason: 'turnedOff' } });
});

test('11. resume before readiness rejects without invoking native resume', async ({ page }) => {
  await open(page);
  const result = await page.evaluate(async () => {
    let calls = 0;
    const native = AudioContext.prototype.resume;
    AudioContext.prototype.resume = function (...args) { calls += 1; return native.apply(this, args); };
    const power = window.__AudioPower();
    let entered;
    const setupEntered = new Promise(resolve => { entered = resolve; });
    const powered = power.turnOn(async () => {
      entered();
      return new Promise(() => {});
    });
    powered.ready.catch(() => {}); powered.ended.catch(() => {});
    await setupEntered;
    const before = calls;
    window.__active = powered;
    return powered.resume().then(() => 'ok', error => ({ name: error.name, calls: calls - before }));
  });
  expect(result).toEqual({ name: 'InvalidStateError', calls: 0 });
  await turnOff(page);
});

test('12. concurrent resume shares promise and retirement rejects stale completion', async ({ page }) => {
  await open(page);
  await turnOn(page);
  await expect.poll(() => page.evaluate(() => window.__ready.then(() => true, () => false))).toBe(true);
  const result = await page.evaluate(async () => {
    const context = window.__active.context;
    await context.suspend();
    const native = context.resume.bind(context);
    let release;
    const gate = new Promise(resolve => { release = resolve; });
    context.resume = () => native().then(() => gate);
    const a = window.__active.resume();
    const b = window.__active.resume();
    const off = window.__active.turnOff();
    const resumed = a.then(() => 'ok', error => error.name);
    const replacement = window.__power.turnOn(async ({ engine }) => engine);
    replacement.ready.catch(() => {});
    release();
    const resume = await resumed;
    await off;
    const replacementReady = await replacement.ready;
    const running = replacement.context.state;
    await window.__active.turnOff();
    const staleOffState = replacement.context.state;
    await replacement.turnOff();
    return { same: a === b, resume, running, staleOffState, hasEngine: typeof replacementReady.mount };
  });
  expect(result).toEqual({ same: true, resume: 'AbortError', running: 'running', staleOffState: 'running', hasEngine: 'function' });
});

for (const legacy of [false, true]) {
  for (const kind of ['Error', 'DOMException']) {
    test(`cross-realm ${kind} retains identity and cause (${legacy ? 'legacy recognition' : 'native brand check'})`, async ({ page }) => {
      await open(page);
      const result = await page.evaluate(async ({ legacy, kind }) => {
        if (legacy) Error.isError = undefined;
        else if (typeof Error.isError !== 'function') throw new Error('Native brand check unavailable');
        const iframe = document.createElement('iframe');
        document.body.append(iframe);
        const cause = { detail: 'original cause' };
        const sentinel = new iframe.contentWindow[kind]('cross-realm sentinel');
        sentinel.cause = cause;
        const power = window.__AudioPower();
        const audio = power.turnOn(async () => { throw sentinel; });
        const error = await audio.ready.catch(error => error);
        const end = await audio.ended;
        await audio.turnOff();
        iframe.remove();
        return {
          readyIdentity: error === sentinel,
          endedIdentity: end.reason === 'failed' && end.error === sentinel,
          causeIdentity: error.cause === cause,
          closed: audio.context.state === 'closed',
        };
      }, { legacy, kind });
      expect(result).toEqual({ readyIdentity: true, endedIdentity: true, causeIdentity: true, closed: true });
    });
  }
}
