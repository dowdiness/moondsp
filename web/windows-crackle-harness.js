(() => {
  const form = document.querySelector('#controls');
  const stopButton = document.querySelector('#stop');
  const saveButton = document.querySelector('#save');
  const status = document.querySelector('#status');
  const resultView = document.querySelector('#result');
  let activeContext = null;
  let activeNode = null;
  let lastResult = null;

  const stop = async () => {
    const node = activeNode;
    activeNode = null;
    if (node) {
      node.disconnect();
    }
    const context = activeContext;
    activeContext = null;
    if (context) {
      await context.close();
    }
    status.value = 'Stopped';
  };

  form.elements.preset.addEventListener('change', () => {
    form.elements.pattern.value = form.elements.preset.value;
  });

  stopButton.addEventListener('click', () => {
    stop().catch((error) => {
      status.value = String(error);
    });
  });

  saveButton.addEventListener('click', () => {
    if (!lastResult) {
      status.value = 'Run a case before saving.';
      return;
    }
    const blob = new Blob([`${JSON.stringify(lastResult, null, 2)}\n`], {
      type: 'application/json',
    });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = `moondsp-crackle-${new Date().toISOString().replaceAll(':', '-')}.json`;
    link.click();
    URL.revokeObjectURL(link.href);
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    await stop();
    const data = new FormData(form);
    const config = {
      route: String(data.get('route')),
      waveform: String(data.get('waveform')),
      gain: Number(data.get('gain')),
      requestedSampleRate: String(data.get('sampleRate')),
      latencyHint: String(data.get('latencyHint')),
      pattern: String(data.get('pattern')),
    };
    const contextOptions = { latencyHint: config.latencyHint };
    if (config.requestedSampleRate === '48000') {
      contextOptions.sampleRate = 48_000;
    }
    try {
      const response = await fetch('moonbit_dsp_test.wasm');
      if (!response.ok) {
        throw new Error(`test wasm fetch failed: ${response.status}`);
      }
      const wasmModule = await WebAssembly.compile(await response.arrayBuffer());
      const context = new AudioContext(contextOptions);
      activeContext = context;
      const messages = [];
      const processorUrl = config.route === 'scheduler'
        ? 'scheduler-probe-processor.js'
        : 'crackle-probe-processor.js';
      await context.audioWorklet.addModule(processorUrl);
      const processorOptions = config.route === 'scheduler'
        ? {
          wasmModule,
          patternText: config.pattern,
          maxBlocks: 4096,
          initialBpm: 120,
          initialGain: config.gain,
          initExportName: config.waveform === 'sine'
            ? 'init_scheduler_sine_graph'
            : 'init_scheduler_graph',
        }
        : {
          wasmModule,
          routeId: 0,
          waveformId: config.waveform === 'sine' ? 0 : 3,
          freqHz: 261.6255653005986,
          outputGain: config.gain,
          blockCount: 4096,
        };
      const node = new AudioWorkletNode(
        context,
        config.route === 'scheduler'
          ? 'moondsp-scheduler-probe'
          : 'moondsp-crackle-probe',
        {
          numberOfInputs: 0,
          numberOfOutputs: 1,
          outputChannelCount: [2],
          processorOptions,
        },
      );
      activeNode = node;
      node.port.onmessage = ({ data: message }) => {
        messages.push(message);
        if (message?.type === 'error') {
          status.value = `Error: ${message.message}`;
        }
        if (message?.type === 'done') {
          lastResult = {
            capturedAt: new Date().toISOString(),
            userAgent: navigator.userAgent,
            platform: navigator.userAgentData?.platform || navigator.platform,
            config,
            actualSampleRate: context.sampleRate,
            baseLatency: context.baseLatency,
            outputLatency: context.outputLatency ?? null,
            terminalTelemetry: message,
            blockTelemetry: messages.filter((entry) => entry?.type === 'block-metrics'),
          };
          resultView.textContent = JSON.stringify(lastResult, null, 2);
          status.value = 'Run complete. Save the JSON and record the audible result separately.';
        }
      };
      node.connect(context.destination);
      await context.resume();
      status.value = `Running ${config.route}/${config.waveform} at ${context.sampleRate} Hz…`;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      try {
        await stop();
      } catch {
        // Preserve the operation error below even if context cleanup fails.
      }
      status.value = errorMessage;
    }
  });
})();
