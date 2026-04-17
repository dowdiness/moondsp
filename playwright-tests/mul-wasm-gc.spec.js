const { test, expect } = require('@playwright/test');

// Counter-evidence to the former "Mul produces near-zero in wasm-gc" memory.
// Instantiates moonbit_dsp_test.wasm directly in the page context (no
// AudioWorklet) and calls mul_adsr_peak, which builds
// [osc(Sine, 440), adsr(5,5,0.5,50) ms, mul(0,1), output(2)],
// gate_on(1), processes one 128-sample block, and returns max abs sample.
// With Mul working, peak should be clearly non-trivial (> 0.3); the old
// "broken Mul" symptom reported peak ~0.003.
test('Mul in wasm-gc release: [osc, adsr(ms), mul, output] produces non-zero peak', async ({ page }) => {
  await page.goto('/');
  const peak = await page.evaluate(async () => {
    const response = await fetch('moonbit_dsp_test.wasm');
    if (!response.ok) {
      return { error: `fetch failed: ${response.status}` };
    }
    const bytes = await response.arrayBuffer();
    const module = await WebAssembly.compile(bytes);
    const exports = WebAssembly.Module.exports(module).map((e) => e.name);
    const imports = {
      spectest: { print_char() {} },
      'moonbit:ffi': {
        make_closure(funcref, closure) {
          return funcref.bind(null, closure);
        },
      },
    };
    const instance = await WebAssembly.instantiate(module, imports);
    if (typeof instance.exports.mul_adsr_peak !== 'function') {
      return { error: 'mul_adsr_peak export missing', exports };
    }
    return { value: instance.exports.mul_adsr_peak(48000, 128) };
  });
  expect(peak.error, peak.error || '').toBeFalsy();
  expect(peak.value).toBeGreaterThan(0.3);
  expect(peak.value).toBeLessThanOrEqual(1.0);
});
