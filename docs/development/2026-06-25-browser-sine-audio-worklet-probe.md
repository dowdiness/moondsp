# Browser Sine AudioWorklet crackle probe

Issues: #211, #212

## Purpose

This diagnostic separates browser true-Sine/`CompiledDsp` oscillator math from
AudioWorklet render-callback streaming. Earlier batch browser wasm-gc probes
called the crackle-probe exports from the page thread and were clean, but that
left the real AudioWorklet callback boundary untested.

## Probe matrix

The test-only processor in `web/crackle-probe-processor.js` loads
`moonbit_dsp_test.wasm` and calls the streaming probe API once per render
quantum:

```text
crackle_probe_stream_init(route, waveform, freq, sampleRate, blockSize)
crackle_probe_stream_process()
```

Each quantum posts per-block metrics back to Playwright. The local run covered:

| Waveform | Routes |
| --- | --- |
| Sine | 0 direct tick loop, 1 direct process, 2 compiled static oscillator, 3 compiled `Value0` oscillator, 4 compiled static `oscillator_from`, 5 compiled controlled `oscillator_from`, 6 `BoundVoicePool` note binding, 7 browser synth shape |
| Triangle | 7 browser synth shape |

The retained batch page-thread probe still covers Sine routes 0..7 and Triangle
routes 2..7.

## Local result

Validation command:

```bash
NEW_MOON_MOD=0 ./node_modules/.bin/playwright test playwright-tests/crackle-probe.spec.js --reporter=line
```

The AudioWorklet streaming probe was clean locally:

- no non-finite samples after buffer writes;
- no `CompiledDsp`/voice-pool sanitizer hits;
- no residual or block-boundary anomalies for routes with a direct oscillator
  reference;
- browser synth-shape Sine route streamed cleanly with non-trivial output.

## Conclusion

For the probed routes, browser wasm-gc graph math and AudioWorklet
render-quantum streaming are not reproducing the true-Sine crackle. If this
stays green in CI, the next boundary for #212 is actual scheduler event timing
and pattern playback in the real browser route, not oscillator or graph math.

This does **not** close #211: real playback still intentionally keeps the
Triangle fallback until true-Sine note playback is proven stable end-to-end.
