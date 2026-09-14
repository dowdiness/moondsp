# DSP primitives

`dsp` provides the stateful building blocks used to generate and process audio.
It owns sample buffers, oscillators, envelopes, filters, delays, mixing, pan,
and parameter smoothing. Graph compilation belongs to the `graph` package.

## Process one block

`DspContext` carries the sample rate and block size. `AudioBuffer` wraps a
`FixedArray[Double]` used for one block of samples.

```mbt check
///|
test "render one oscillator block" {
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let output = context.make_buffer()
  let oscillator = @dsp.Oscillator::new()

  oscillator.process_waveform(
    context~,
    output~,
    waveform=@dsp.Waveform::Sine,
    freq_hz=440.0,
  )

  assert_eq(output.length(), 128)
  assert_true(output.any(sample => sample != 0.0))
  assert_true(
    output.all(sample => @dsp.is_finite(sample) && sample.abs() <= 1.0),
  )
}
```

Most processors write into an existing buffer. Create state and buffers before
the audio callback, then reuse them for every block.

## Buffers and ownership

Use `AudioBuffer::filled(size)` or `DspContext::make_buffer()` to allocate a new
buffer. `AudioBuffer::new(samples)` copies a `FixedArray`; `AudioBuffer::adopt`
wraps it without copying.

```mbt check
///|
test "gain processes a buffer in place" {
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let buffer = @dsp.AudioBuffer::filled(4, init=0.5)
  let gain = @dsp.Gain::new()

  gain.process(context~, buffer~, amount=0.4)

  assert_true(buffer.all(sample => (sample - 0.2).abs() < 0.000001))
}
```

Writes through `set` and `fill` normalize non-finite samples to zero. Processors
also respect the smaller of the context block size and the buffer length.

## Available primitives

| Primitive | Purpose |
|---|---|
| `Oscillator` | Sine, saw, square, and triangle waveforms |
| `Noise` | Seeded white-noise source |
| `Adsr` | Gate-driven attack, decay, sustain, and release |
| `Biquad` | Low-pass, high-pass, and band-pass filtering |
| `DelayLine` | Integer-sample delay with feedback |
| `Gain` | In-place level scaling |
| `Mix` | Add one buffer into another |
| `Clip` | Hard-limit samples to a threshold |
| `Pan` | Equal-power mono-to-stereo pan |
| `ParamSmoother` | Smooth control changes across samples |
| `StereoReverb` | Shared stereo reverb processing |

Stateful processors provide `reset()` when their history must be cleared.

## Build a manual signal chain

The primitive API is useful for fixed processing paths and custom hosts. This
example generates a saw wave, filters it, and pans it to stereo:

```mbt check
///|
test "process a mono source into stereo" {
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=16)
  let mono = context.make_buffer()
  let left = context.make_buffer()
  let right = context.make_buffer()
  let oscillator = @dsp.Oscillator::new()
  let filter = @dsp.Biquad::new()
  let pan = @dsp.Pan::new()

  oscillator.process_waveform(
    context~,
    output=mono,
    waveform=@dsp.Waveform::Saw,
    freq_hz=220.0,
  )
  assert_true(filter.update(context, @dsp.BiquadMode::LowPass, 1200.0, 0.707))
  filter.process(context, mono)
  pan.process(
    context~,
    input=mono,
    left_output=left,
    right_output=right,
    position=-0.5,
  )

  assert_true(left.any(sample => sample != 0.0))
  assert_true(right.any(sample => sample != 0.0))
  assert_true(left.all(@dsp.is_finite))
  assert_true(right.all(@dsp.is_finite))
}
```

Use the `graph` package when the signal path must be authored, optimized,
compiled, or replaced at runtime.

## Delay and feedback

`DelayLine` allocates its circular buffer at construction. Processing and
parameter updates reuse that storage. Feedback is clamped to the supported safe
range.

```mbt check
///|
test "delay returns an impulse after its delay" {
  let delay = @dsp.DelayLine::new(8, delay_samples=2, feedback=0.0)

  assert_true(delay.tick(1.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 1.0)
}
```

A feedback loop always needs stored state. Do not build an instantaneous cycle;
use `DelayLine` or the graph package's feedback model to provide the delay.

## Real-time allocation rule

The processing path is designed to reuse preallocated state:

- construct processors before playback;
- allocate output and scratch buffers before the callback;
- reuse the same buffers for each block;
- update parameters on existing processors;
- do not create arrays, maps, processors, or closures in the sample loop.

This rule covers calls such as `process()` and `tick()`. Constructors,
`AudioBuffer::filled`, and `DspContext::make_buffer` allocate and belong on the
control side.

## Finally Tagless patches

The open traits describe DSP programs without choosing a representation:

- `ArithSym` — constants, multiplication, mixing, and clipping;
- `DspSym` — oscillators, noise, envelopes, gain, and output;
- `FilterSym` — biquad filters;
- `DelaySym` — delay lines;
- `StereoSym` and its combined traits — stereo operations.

A generic patch can be interpreted by any type that implements the required
traits:

```mbt nocheck
///|
fn[T : @dsp.FilterSym] filtered_tone() -> T {
  let frequency = @dsp.ArithSym::constant(220.0)
  let oscillator = @dsp.DspSym::oscillator(frequency, @dsp.Waveform::Saw)
  let filtered = @dsp.FilterSym::biquad(
    oscillator,
    @dsp.BiquadMode::LowPass,
    1200.0,
    0.707,
  )
  @dsp.DspSym::output(@dsp.DspSym::gain(filtered, 0.25))
}
```

The graph package supplies the concrete graph representation and compiler. A
custom interpreter can implement the same traits for analysis or another
backend.

## Package boundary

`dsp` contains reusable sample-processing code only. It does not know about
pattern time, voices, graph topology, AudioWorklet messages, or CLAP hosts.

- [Technical reference](../docs/technical-reference.md) — runtime behavior and
  real-time constraints.
- [Blueprint](../docs/blueprint.md) — the larger engine architecture.
- [`graph/`](../graph/) — compiled graphs, hot-swap, and topology editing.
