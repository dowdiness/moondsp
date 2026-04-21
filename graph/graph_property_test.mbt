///|
/// Property-based tests for graph processing determinism.
///
/// These tests establish the invariant that compiling and processing the same
/// graph topology twice produces sample-identical output. This is the safety
/// net for refactoring the process loops: if the unified dispatch diverges
/// from the current dispatch, these tests catch it.
///
/// Coverage: acyclic mono, acyclic stereo, binary combinators, ADSR envelope,
/// mono feedback cycles, stereo feedback cycles, hot-swap, runtime controls,
/// debug-vs-normal equivalence (both acyclic and feedback).

///|
const PROP_SAMPLE_RATE : Double = 48000.0

///|
const PROP_BLOCK_SIZE : Int = 128

///|
const PROP_NUM_BLOCKS : Int = 3

///|
/// Waveform options for random selection.
const PROP_WAVEFORM_COUNT : Int = 4

///|
fn prop_waveform(seed : Int) -> Waveform {
  match seed.abs() % PROP_WAVEFORM_COUNT {
    0 => Waveform::Sine
    1 => Waveform::Saw
    2 => Waveform::Square
    _ => Waveform::Triangle
  }
}

///|
/// BiquadMode options for random selection.
const PROP_BIQUAD_MODE_COUNT : Int = 3

///|
fn prop_biquad_mode(seed : Int) -> BiquadMode {
  match seed.abs() % PROP_BIQUAD_MODE_COUNT {
    0 => BiquadMode::LowPass
    1 => BiquadMode::HighPass
    _ => BiquadMode::BandPass
  }
}

///|
/// Generate a valid mono graph from a seed.
///
/// Strategy: build a linear chain of random processing nodes from a source
/// (oscillator, noise, or constant) through optional processors (gain, clip,
/// biquad, delay) to an Output node. Every generated graph compiles
/// successfully — the test aborts on compilation failure.
fn gen_mono_graph(seed : Int) -> Array[DspNode] {
  let s = seed.abs()
  let nodes : Array[DspNode] = []
  // Source node selection
  let source_kind = s % 4
  match source_kind {
    0 => {
      // Oscillator with fixed frequency
      let freq = 110.0 + (s % 880).to_double()
      nodes.push(DspNode::oscillator(prop_waveform(s / 4), freq))
    }
    1 =>
      // Noise
      nodes.push(DspNode::noise(s.reinterpret_as_uint()))
    2 => {
      // Constant
      let val = (s % 200).to_double() / 200.0 - 0.5
      nodes.push(DspNode::constant(val))
    }
    _ => {
      // FM oscillator: constant freq → oscillator
      let mod_freq = 1.0 + (s % 20).to_double()
      nodes.push(DspNode::constant(mod_freq))
      let carrier_wf = prop_waveform(s / 7)
      nodes.push(DspNode::oscillator_from(0, carrier_wf))
    }
  }
  // Processing chain — add 0 to 4 processors based on seed bits
  let chain_bits = s / 5 % 16 // 4 bits → up to 4 processors
  let mut last = nodes.length() - 1
  if chain_bits % 2 >= 1 {
    // Gain
    let gain_val = 0.1 + (s % 9).to_double() * 0.1
    nodes.push(DspNode::gain(last, gain_val))
    last = nodes.length() - 1
  }
  if chain_bits / 2 % 2 >= 1 {
    // Clip
    let threshold = 0.1 + (s % 9).to_double() * 0.1
    nodes.push(DspNode::clip(last, threshold))
    last = nodes.length() - 1
  }
  if chain_bits / 4 % 2 >= 1 {
    // Biquad
    let cutoff = 200.0 + (s % 4000).to_double()
    let q = 0.5 + (s % 10).to_double() * 0.1
    nodes.push(
      DspNode::biquad(
        input=last,
        mode=prop_biquad_mode(s / 3),
        cutoff_hz=cutoff,
        q~,
      ),
    )
    last = nodes.length() - 1
  }
  if chain_bits / 8 % 2 >= 1 {
    // Delay
    let max_samples = 4 + s % 60
    let delay_samples = 1 + s % max_samples
    let feedback = (s % 8).to_double() * 0.1
    nodes.push(DspNode::delay(last, max_samples, delay_samples~, feedback~))
    last = nodes.length() - 1
  }
  // Terminal
  nodes.push(DspNode::output(last))
  nodes
}

///|
/// Generate a valid stereo graph from a seed.
///
/// Builds a mono chain, then adds Pan → optional stereo processors →
/// StereoOutput.
fn gen_stereo_graph(seed : Int) -> Array[DspNode] {
  let s = seed.abs()
  let nodes : Array[DspNode] = []
  // Source node: oscillator or noise
  let source_kind = s % 3
  match source_kind {
    0 => {
      let freq = 110.0 + (s % 880).to_double()
      nodes.push(DspNode::oscillator(prop_waveform(s / 4), freq))
    }
    1 => nodes.push(DspNode::noise(s.reinterpret_as_uint()))
    _ => {
      let val = (s % 200).to_double() / 200.0 - 0.5
      nodes.push(DspNode::constant(val))
    }
  }
  let mut last = nodes.length() - 1
  // Optional mono gain before pan
  if s / 3 % 2 == 0 {
    let gain_val = 0.1 + (s % 9).to_double() * 0.1
    nodes.push(DspNode::gain(last, gain_val))
    last = nodes.length() - 1
  }
  // Pan to stereo
  let pan_pos = ((s % 20).to_double() - 10.0) / 10.0 // [-1.0, 1.0]
  nodes.push(DspNode::pan(last, pan_pos))
  last = nodes.length() - 1
  // Optional stereo processors — 4 bits select gain, clip, biquad, delay
  let stereo_bits = s / 7 % 16
  if stereo_bits % 2 >= 1 {
    let gain_val = 0.1 + (s % 9).to_double() * 0.1
    nodes.push(DspNode::stereo_gain(last, gain_val))
    last = nodes.length() - 1
  }
  if stereo_bits / 2 % 2 >= 1 {
    let threshold = 0.1 + (s % 9).to_double() * 0.1
    nodes.push(DspNode::stereo_clip(last, threshold))
    last = nodes.length() - 1
  }
  if stereo_bits / 4 % 2 >= 1 {
    let cutoff = 200.0 + (s % 4000).to_double()
    let q = 0.5 + (s % 10).to_double() * 0.1
    nodes.push(DspNode::stereo_biquad(last, prop_biquad_mode(s / 3), cutoff, q))
    last = nodes.length() - 1
  }
  if stereo_bits / 8 % 2 >= 1 {
    let max_samples = 4 + s % 60
    let delay_samples = 1 + s % max_samples
    let feedback = (s % 8).to_double() * 0.1
    nodes.push(
      DspNode::stereo_delay(last, max_samples, delay_samples~, feedback~),
    )
    last = nodes.length() - 1
  }
  // StereoOutput
  nodes.push(DspNode::stereo_output(last))
  nodes
}

///|
/// Generate a valid graph with two mixed sources from a seed.
fn gen_binary_graph(seed : Int) -> Array[DspNode] {
  let s = seed.abs()
  let nodes : Array[DspNode] = []
  // Source A
  let freq_a = 110.0 + (s % 440).to_double()
  nodes.push(DspNode::oscillator(prop_waveform(s), freq_a))
  // Source B
  let source_b = s / 3 % 3
  match source_b {
    0 => {
      let freq_b = 220.0 + (s % 660).to_double()
      nodes.push(DspNode::oscillator(prop_waveform(s / 5), freq_b))
    }
    1 => nodes.push(DspNode::noise((s * 7).reinterpret_as_uint()))
    _ => {
      let val = (s % 100).to_double() / 100.0
      nodes.push(DspNode::constant(val))
    }
  }
  // Binary combinator
  if s % 2 == 0 {
    nodes.push(DspNode::mix(0, 1))
  } else {
    nodes.push(DspNode::mul(0, 1))
  }
  // Optional gain
  let mut last = 2
  if s / 11 % 2 == 0 {
    let gain_val = 0.1 + (s % 9).to_double() * 0.1
    nodes.push(DspNode::gain(last, gain_val))
    last = nodes.length() - 1
  }
  nodes.push(DspNode::output(last))
  nodes
}

///|
/// Generate a graph with ADSR envelope (stateful, time-varying).
fn gen_adsr_graph(seed : Int) -> Array[DspNode] {
  let s = seed.abs()
  let attack_ms = 0.5 + (s % 10).to_double() * 0.5
  let decay_ms = 0.5 + (s / 3 % 10).to_double() * 0.5
  let sustain = 0.1 + (s / 7 % 9).to_double() * 0.1
  let release_ms = 0.5 + (s / 11 % 20).to_double() * 0.5
  let freq = 220.0 + (s % 440).to_double()
  [
    DspNode::adsr(attack_ms~, decay_ms~, sustain~, release_ms~),
    DspNode::oscillator(prop_waveform(s), freq),
    DspNode::mul(0, 1),
    DspNode::output(2),
  ]
}

///|
/// Generate a valid mono feedback cycle graph from a seed.
///
/// Pattern: Constant → Mix(const, back_edge) → Gain → Output
/// where Gain feeds back to Mix's input1 via a z^-1 back-edge.
/// The gain is clamped to (0, 1) to keep the feedback stable.
fn gen_mono_feedback_graph(seed : Int) -> Array[DspNode] {
  let s = seed.abs()
  let constant_val = 0.1 + (s % 9).to_double() * 0.1
  // Feedback gain in (0, 0.95) — stable range
  let feedback_gain = 0.05 + (s % 18).to_double() * 0.05
  let variant = s % 3
  match variant {
    0 =>
      // Simple: Constant → Mix(0, 2) → Gain → Output
      // Back-edge: node 2 (Gain output) → node 1 (Mix input1)
      [
        DspNode::constant(constant_val),
        DspNode::mix(0, 2),
        DspNode::gain(1, feedback_gain),
        DspNode::output(2),
      ]
    1 => {
      // With biquad in feedback path:
      // Constant → Mix(0, 3) → Biquad → Gain → Output
      let cutoff = 500.0 + (s % 3000).to_double()
      let q = 0.5 + (s % 10).to_double() * 0.1
      [
        DspNode::constant(constant_val),
        DspNode::mix(0, 3),
        DspNode::biquad(
          input=1,
          mode=prop_biquad_mode(s / 3),
          cutoff_hz=cutoff,
          q~,
        ),
        DspNode::gain(2, feedback_gain),
        DspNode::output(3),
      ]
    }
    _ => {
      // With delay in feedback path:
      // Constant → Mix(0, 3) → Delay → Gain → Output
      let max_samples = 4 + s % 60
      let delay_samples = 1 + s % max_samples
      [
        DspNode::constant(constant_val),
        DspNode::mix(0, 3),
        DspNode::delay(1, max_samples, delay_samples~, feedback=0.0),
        DspNode::gain(2, feedback_gain),
        DspNode::output(3),
      ]
    }
  }
}

///|
/// Generate a valid stereo feedback cycle graph from a seed.
///
/// Pattern: Constant → Mix(const, stereo_mixdown) → Gain → Pan → StereoGain
///          → StereoMixDown → Output(Gain)
/// The StereoMixDown feeds back to Mix's input1 crossing the mono/stereo boundary.
fn gen_stereo_feedback_graph(seed : Int) -> Array[DspNode] {
  let s = seed.abs()
  let constant_val = 0.1 + (s % 9).to_double() * 0.1
  let feedback_gain = 0.05 + (s % 18).to_double() * 0.05
  let stereo_gain_val = 0.1 + (s / 3 % 9).to_double() * 0.1
  let pan_pos = ((s % 20).to_double() - 10.0) / 10.0
  // Constant → Mix(0, 5) → Gain → Pan → StereoGain → StereoMixDown → StereoOutput(4)
  // Back-edge: StereoMixDown(5) → Mix(1) input1
  [
    DspNode::constant(constant_val),
    DspNode::mix(0, 5),
    DspNode::gain(1, feedback_gain),
    DspNode::pan(2, pan_pos),
    DspNode::stereo_gain(3, stereo_gain_val),
    DspNode::stereo_mixdown(4),
    DspNode::stereo_output(4),
  ]
}

///|
/// Compare two AudioBuffers sample-by-sample up to `count` samples.
/// Returns true if all samples are identical (bitwise equal).
fn buffers_identical(a : AudioBuffer, b : AudioBuffer, count : Int) -> Bool {
  for i = 0; i < count; i = i + 1 {
    if a.get(i) != b.get(i) {
      return false
    }
  }
  true
}

///|
fn samples_identical(a : Array[Double], b : Array[Double]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Compile a mono graph, abort on failure. Generators produce valid graphs,
/// so compilation failure indicates a generator bug, not expected rejection.
fn compile_mono(nodes : Array[DspNode]) -> CompiledDsp {
  let context = DspContext::new(
    sample_rate=PROP_SAMPLE_RATE,
    block_size=PROP_BLOCK_SIZE,
  )
  CompiledDsp::compile(nodes, context).unwrap()
}

///|
/// Compile a stereo graph, abort on failure.
fn compile_stereo(nodes : Array[DspNode]) -> CompiledStereoDsp {
  let context = DspContext::new(
    sample_rate=PROP_SAMPLE_RATE,
    block_size=PROP_BLOCK_SIZE,
  )
  CompiledStereoDsp::compile(nodes, context).unwrap()
}

///|
/// Process a mono compiled graph for N blocks, return all samples.
fn run_mono(compiled : CompiledDsp, num_blocks : Int) -> Array[Double] {
  let context = DspContext::new(
    sample_rate=PROP_SAMPLE_RATE,
    block_size=PROP_BLOCK_SIZE,
  )
  let output = AudioBuffer::filled(PROP_BLOCK_SIZE)
  let samples : Array[Double] = Array::new(
    capacity=num_blocks * PROP_BLOCK_SIZE,
  )
  for _block = 0; _block < num_blocks; _block = _block + 1 {
    compiled.process(context, output)
    for s = 0; s < PROP_BLOCK_SIZE; s = s + 1 {
      samples.push(output.get(s))
    }
  }
  samples
}

///|
/// Process a stereo compiled graph for N blocks, return (left, right) samples.
fn run_stereo(
  compiled : CompiledStereoDsp,
  num_blocks : Int,
) -> (Array[Double], Array[Double]) {
  let context = DspContext::new(
    sample_rate=PROP_SAMPLE_RATE,
    block_size=PROP_BLOCK_SIZE,
  )
  let left = AudioBuffer::filled(PROP_BLOCK_SIZE)
  let right = AudioBuffer::filled(PROP_BLOCK_SIZE)
  let left_samples : Array[Double] = Array::new(
    capacity=num_blocks * PROP_BLOCK_SIZE,
  )
  let right_samples : Array[Double] = Array::new(
    capacity=num_blocks * PROP_BLOCK_SIZE,
  )
  for _block = 0; _block < num_blocks; _block = _block + 1 {
    compiled.process(context, left, right)
    for s = 0; s < PROP_BLOCK_SIZE; s = s + 1 {
      left_samples.push(left.get(s))
      right_samples.push(right.get(s))
    }
  }
  (left_samples, right_samples)
}

// ---------------------------------------------------------------------------
// Property: mono acyclic graph processing is deterministic
// ---------------------------------------------------------------------------

///|
test "prop: mono linear chain — compile twice, process identically" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_mono_graph(seed)
      let a = run_mono(compile_mono(nodes), PROP_NUM_BLOCKS)
      let b = run_mono(compile_mono(nodes), PROP_NUM_BLOCKS)
      samples_identical(a, b)
    },
    max_success=200,
  )
}

///|
test "prop: mono binary combinator — compile twice, process identically" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_binary_graph(seed)
      let a = run_mono(compile_mono(nodes), PROP_NUM_BLOCKS)
      let b = run_mono(compile_mono(nodes), PROP_NUM_BLOCKS)
      samples_identical(a, b)
    },
    max_success=200,
  )
}

///|
test "prop: mono ADSR graph — compile twice, process identically" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_adsr_graph(seed)
      let context = DspContext::new(
        sample_rate=PROP_SAMPLE_RATE,
        block_size=PROP_BLOCK_SIZE,
      )
      let compiled_a = CompiledDsp::compile(nodes, context).unwrap()
      let compiled_b = CompiledDsp::compile(nodes, context).unwrap()
      ignore(compiled_a.gate_on(0))
      ignore(compiled_b.gate_on(0))
      let out_a = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let out_b = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let mut identical = true
      for _block = 0; _block < PROP_NUM_BLOCKS; _block = _block + 1 {
        compiled_a.process(context, out_a)
        compiled_b.process(context, out_b)
        if !buffers_identical(out_a, out_b, PROP_BLOCK_SIZE) {
          identical = false
        }
      }
      ignore(compiled_a.gate_off(0))
      ignore(compiled_b.gate_off(0))
      for _block = 0; _block < PROP_NUM_BLOCKS; _block = _block + 1 {
        compiled_a.process(context, out_a)
        compiled_b.process(context, out_b)
        if !buffers_identical(out_a, out_b, PROP_BLOCK_SIZE) {
          identical = false
        }
      }
      identical
    },
    max_success=100,
  )
}

// ---------------------------------------------------------------------------
// Property: stereo acyclic graph processing is deterministic
// ---------------------------------------------------------------------------

///|
test "prop: stereo graph — compile twice, process identically" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_stereo_graph(seed)
      let (la, ra) = run_stereo(compile_stereo(nodes), PROP_NUM_BLOCKS)
      let (lb, rb) = run_stereo(compile_stereo(nodes), PROP_NUM_BLOCKS)
      samples_identical(la, lb) && samples_identical(ra, rb)
    },
    max_success=200,
  )
}

// ---------------------------------------------------------------------------
// Property: mono feedback graph processing is deterministic
// ---------------------------------------------------------------------------

///|
test "prop: mono feedback cycle — compile twice, process identically" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_mono_feedback_graph(seed)
      let a = run_mono(compile_mono(nodes), PROP_NUM_BLOCKS)
      let b = run_mono(compile_mono(nodes), PROP_NUM_BLOCKS)
      samples_identical(a, b)
    },
    max_success=200,
  )
}

///|
test "prop: mono feedback cycle — runtime retune is deterministic" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let s = seed.abs()
      let nodes = gen_mono_feedback_graph(s)
      let context = DspContext::new(
        sample_rate=PROP_SAMPLE_RATE,
        block_size=PROP_BLOCK_SIZE,
      )
      let compiled_a = CompiledDsp::compile(nodes, context).unwrap()
      let compiled_b = CompiledDsp::compile(nodes, context).unwrap()
      // The gain node is always the last before Output in our feedback graphs
      let gain_index = nodes.length() - 2
      let new_gain = 0.05 + (s / 13 % 18).to_double() * 0.05
      let out_a = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let out_b = AudioBuffer::filled(PROP_BLOCK_SIZE)
      // Process one block, then retune, then process again
      compiled_a.process(context, out_a)
      compiled_b.process(context, out_b)
      if !buffers_identical(out_a, out_b, PROP_BLOCK_SIZE) {
        return false
      }
      ignore(
        compiled_a.apply_control(
          GraphControl::set_param(gain_index, GraphParamSlot::Value0, new_gain),
        ),
      )
      ignore(
        compiled_b.apply_control(
          GraphControl::set_param(gain_index, GraphParamSlot::Value0, new_gain),
        ),
      )
      compiled_a.process(context, out_a)
      compiled_b.process(context, out_b)
      buffers_identical(out_a, out_b, PROP_BLOCK_SIZE)
    },
    max_success=200,
  )
}

// ---------------------------------------------------------------------------
// Property: stereo feedback graph processing is deterministic
// ---------------------------------------------------------------------------

///|
test "prop: stereo feedback cycle — compile twice, process identically" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_stereo_feedback_graph(seed)
      let (la, ra) = run_stereo(compile_stereo(nodes), PROP_NUM_BLOCKS)
      let (lb, rb) = run_stereo(compile_stereo(nodes), PROP_NUM_BLOCKS)
      samples_identical(la, lb) && samples_identical(ra, rb)
    },
    max_success=200,
  )
}

// ---------------------------------------------------------------------------
// Property: hot-swap preserves determinism
// ---------------------------------------------------------------------------

///|
test "prop: mono hot-swap — same swap sequence produces identical output" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let s = seed.abs()
      let nodes_initial = gen_mono_graph(s)
      let nodes_replacement = gen_mono_graph(s + 1000)
      let context = DspContext::new(
        sample_rate=PROP_SAMPLE_RATE,
        block_size=PROP_BLOCK_SIZE,
      )
      let crossfade = 64 + s % 128
      let hs_a = CompiledDspHotSwap::from_graph(
        compile_mono(nodes_initial),
        crossfade_samples=crossfade,
      )
      let hs_b = CompiledDspHotSwap::from_graph(
        compile_mono(nodes_initial),
        crossfade_samples=crossfade,
      )
      let out_a = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let out_b = AudioBuffer::filled(PROP_BLOCK_SIZE)
      hs_a.process(context, out_a)
      hs_b.process(context, out_b)
      if !buffers_identical(out_a, out_b, PROP_BLOCK_SIZE) {
        return false
      }
      ignore(hs_a.queue_swap(compile_mono(nodes_replacement)))
      ignore(hs_b.queue_swap(compile_mono(nodes_replacement)))
      let mut identical = true
      for _block = 0; _block < 4; _block = _block + 1 {
        hs_a.process(context, out_a)
        hs_b.process(context, out_b)
        if !buffers_identical(out_a, out_b, PROP_BLOCK_SIZE) {
          identical = false
        }
      }
      identical
    },
    max_success=100,
  )
}

///|
test "prop: stereo hot-swap — same swap sequence produces identical output" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let s = seed.abs()
      let nodes_initial = gen_stereo_graph(s)
      let nodes_replacement = gen_stereo_graph(s + 1000)
      let context = DspContext::new(
        sample_rate=PROP_SAMPLE_RATE,
        block_size=PROP_BLOCK_SIZE,
      )
      let crossfade = 64 + s % 128
      let hs_a = CompiledStereoDspHotSwap::from_graph(
        compile_stereo(nodes_initial),
        crossfade_samples=crossfade,
      )
      let hs_b = CompiledStereoDspHotSwap::from_graph(
        compile_stereo(nodes_initial),
        crossfade_samples=crossfade,
      )
      let la = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let ra = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let lb = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let rb = AudioBuffer::filled(PROP_BLOCK_SIZE)
      hs_a.process(context, la, ra)
      hs_b.process(context, lb, rb)
      if !buffers_identical(la, lb, PROP_BLOCK_SIZE) ||
        !buffers_identical(ra, rb, PROP_BLOCK_SIZE) {
        return false
      }
      ignore(hs_a.queue_swap(compile_stereo(nodes_replacement)))
      ignore(hs_b.queue_swap(compile_stereo(nodes_replacement)))
      let mut identical = true
      for _block in 0..<4 {
        hs_a.process(context, la, ra)
        hs_b.process(context, lb, rb)
        if !buffers_identical(la, lb, PROP_BLOCK_SIZE) ||
          !buffers_identical(ra, rb, PROP_BLOCK_SIZE) {
          identical = false
        }
      }
      identical
    },
    max_success=100,
  )
}

// ---------------------------------------------------------------------------
// Property: runtime controls produce deterministic results
// ---------------------------------------------------------------------------

///|
test "prop: runtime param update is deterministic across compilations" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let s = seed.abs()
      let freq = 200.0 + (s % 600).to_double()
      let gain_val = 0.1 + (s % 9).to_double() * 0.1
      let new_gain = 0.05 + (s / 7 % 9).to_double() * 0.1
      let nodes = [
        DspNode::oscillator(Waveform::Sine, freq),
        DspNode::gain(0, gain_val),
        DspNode::output(1),
      ]
      let context = DspContext::new(
        sample_rate=PROP_SAMPLE_RATE,
        block_size=PROP_BLOCK_SIZE,
      )
      let compiled_a = CompiledDsp::compile(nodes, context).unwrap()
      let compiled_b = CompiledDsp::compile(nodes, context).unwrap()
      ignore(
        compiled_a.apply_control(
          GraphControl::set_param(1, GraphParamSlot::Value0, new_gain),
        ),
      )
      ignore(
        compiled_b.apply_control(
          GraphControl::set_param(1, GraphParamSlot::Value0, new_gain),
        ),
      )
      let out_a = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let out_b = AudioBuffer::filled(PROP_BLOCK_SIZE)
      compiled_a.process(context, out_a)
      compiled_b.process(context, out_b)
      buffers_identical(out_a, out_b, PROP_BLOCK_SIZE)
    },
    max_success=200,
  )
}

///|
/// Broader runtime control: biquad cutoff/Q, delay_samples, and gate
/// transitions all produce deterministic output across two compilations.
test "prop: runtime control variants are deterministic" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let s = seed.abs()
      let variant = s % 3
      let context = DspContext::new(
        sample_rate=PROP_SAMPLE_RATE,
        block_size=PROP_BLOCK_SIZE,
      )
      let out_a = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let out_b = AudioBuffer::filled(PROP_BLOCK_SIZE)
      match variant {
        0 => {
          // Biquad cutoff + Q update
          let cutoff = 500.0 + (s % 3000).to_double()
          let q = 0.5 + (s % 10).to_double() * 0.1
          let new_cutoff = 200.0 + (s / 3 % 4000).to_double()
          let new_q = 0.5 + (s / 7 % 10).to_double() * 0.1
          let nodes = [
            DspNode::oscillator(Waveform::Saw, 440.0),
            DspNode::biquad(
              input=0,
              mode=BiquadMode::LowPass,
              cutoff_hz=cutoff,
              q~,
            ),
            DspNode::output(1),
          ]
          let ca = CompiledDsp::compile(nodes, context).unwrap()
          let cb = CompiledDsp::compile(nodes, context).unwrap()
          ca.process(context, out_a)
          cb.process(context, out_b)
          ignore(
            ca.apply_control(
              GraphControl::set_param(1, GraphParamSlot::Value0, new_cutoff),
            ),
          )
          ignore(
            cb.apply_control(
              GraphControl::set_param(1, GraphParamSlot::Value0, new_cutoff),
            ),
          )
          ignore(
            ca.apply_control(
              GraphControl::set_param(1, GraphParamSlot::Value1, new_q),
            ),
          )
          ignore(
            cb.apply_control(
              GraphControl::set_param(1, GraphParamSlot::Value1, new_q),
            ),
          )
          ca.process(context, out_a)
          cb.process(context, out_b)
          buffers_identical(out_a, out_b, PROP_BLOCK_SIZE)
        }
        1 => {
          // Delay samples update
          let max_samples = 8 + s % 56
          let initial_delay = 1 + s % (max_samples / 2)
          let new_delay = 1 + s / 3 % max_samples
          let nodes = [
            DspNode::oscillator(Waveform::Sine, 220.0),
            DspNode::delay(
              0,
              max_samples,
              delay_samples=initial_delay,
              feedback=0.3,
            ),
            DspNode::output(1),
          ]
          let ca = CompiledDsp::compile(nodes, context).unwrap()
          let cb = CompiledDsp::compile(nodes, context).unwrap()
          ca.process(context, out_a)
          cb.process(context, out_b)
          ignore(
            ca.apply_control(
              GraphControl::set_param(
                1,
                GraphParamSlot::DelaySamples,
                new_delay.to_double(),
              ),
            ),
          )
          ignore(
            cb.apply_control(
              GraphControl::set_param(
                1,
                GraphParamSlot::DelaySamples,
                new_delay.to_double(),
              ),
            ),
          )
          ca.process(context, out_a)
          cb.process(context, out_b)
          buffers_identical(out_a, out_b, PROP_BLOCK_SIZE)
        }
        _ => {
          // Gate on/off transitions
          let attack_ms = 1.0 + (s % 5).to_double()
          let decay_ms = 1.0 + (s / 3 % 5).to_double()
          let sustain = 0.2 + (s / 7 % 8).to_double() * 0.1
          let release_ms = 2.0 + (s / 11 % 10).to_double()
          let nodes = [
            DspNode::adsr(attack_ms~, decay_ms~, sustain~, release_ms~),
            DspNode::oscillator(Waveform::Sine, 440.0),
            DspNode::mul(0, 1),
            DspNode::output(2),
          ]
          let ca = CompiledDsp::compile(nodes, context).unwrap()
          let cb = CompiledDsp::compile(nodes, context).unwrap()
          ignore(ca.gate_on(0))
          ignore(cb.gate_on(0))
          ca.process(context, out_a)
          cb.process(context, out_b)
          if !buffers_identical(out_a, out_b, PROP_BLOCK_SIZE) {
            return false
          }
          ignore(ca.gate_off(0))
          ignore(cb.gate_off(0))
          ca.process(context, out_a)
          cb.process(context, out_b)
          buffers_identical(out_a, out_b, PROP_BLOCK_SIZE)
        }
      }
    },
    max_success=200,
  )
}

// ---------------------------------------------------------------------------
// Property: all generated graphs produce finite output
// ---------------------------------------------------------------------------

///|
test "prop: mono graphs produce finite output" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_mono_graph(seed)
      let compiled = compile_mono(nodes)
      let output = AudioBuffer::filled(PROP_BLOCK_SIZE)
      compiled.process(
        DspContext::new(
          sample_rate=PROP_SAMPLE_RATE,
          block_size=PROP_BLOCK_SIZE,
        ),
        output,
      )
      let mut all_finite = true
      for s = 0; s < PROP_BLOCK_SIZE; s = s + 1 {
        if !is_finite(output.get(s)) {
          all_finite = false
        }
      }
      all_finite
    },
    max_success=200,
  )
}

///|
test "prop: stereo graphs produce finite output" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_stereo_graph(seed)
      let compiled = compile_stereo(nodes)
      let left = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let right = AudioBuffer::filled(PROP_BLOCK_SIZE)
      compiled.process(
        DspContext::new(
          sample_rate=PROP_SAMPLE_RATE,
          block_size=PROP_BLOCK_SIZE,
        ),
        left,
        right,
      )
      let mut all_finite = true
      for s = 0; s < PROP_BLOCK_SIZE; s = s + 1 {
        if !is_finite(left.get(s)) || !is_finite(right.get(s)) {
          all_finite = false
        }
      }
      all_finite
    },
    max_success=200,
  )
}

///|
test "prop: mono feedback graphs produce finite output" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_mono_feedback_graph(seed)
      let compiled = compile_mono(nodes)
      let context = DspContext::new(
        sample_rate=PROP_SAMPLE_RATE,
        block_size=PROP_BLOCK_SIZE,
      )
      let output = AudioBuffer::filled(PROP_BLOCK_SIZE)
      // Process multiple blocks — feedback can diverge over time
      let mut all_finite = true
      for _block = 0; _block < PROP_NUM_BLOCKS; _block = _block + 1 {
        compiled.process(context, output)
        for s = 0; s < PROP_BLOCK_SIZE; s = s + 1 {
          if !is_finite(output.get(s)) {
            all_finite = false
          }
        }
      }
      all_finite
    },
    max_success=200,
  )
}

///|
test "prop: stereo feedback graphs produce finite output" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_stereo_feedback_graph(seed)
      let compiled = compile_stereo(nodes)
      let context = DspContext::new(
        sample_rate=PROP_SAMPLE_RATE,
        block_size=PROP_BLOCK_SIZE,
      )
      let left = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let right = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let mut all_finite = true
      for _block = 0; _block < PROP_NUM_BLOCKS; _block = _block + 1 {
        compiled.process(context, left, right)
        for s = 0; s < PROP_BLOCK_SIZE; s = s + 1 {
          if !is_finite(left.get(s)) || !is_finite(right.get(s)) {
            all_finite = false
          }
        }
      }
      all_finite
    },
    max_success=200,
  )
}

// ---------------------------------------------------------------------------
// Property: debug mode produces same output as production mode
// ---------------------------------------------------------------------------

///|
test "prop: debug mode produces same output as normal mode (acyclic)" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_mono_graph(seed)
      let compiled_normal = compile_mono(nodes)
      let compiled_debug = compile_mono(nodes)
      compiled_debug.enable_debug_validation()
      let out_normal = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let out_debug = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let context = DspContext::new(
        sample_rate=PROP_SAMPLE_RATE,
        block_size=PROP_BLOCK_SIZE,
      )
      let mut identical = true
      for _block = 0; _block < PROP_NUM_BLOCKS; _block = _block + 1 {
        compiled_normal.process(context, out_normal)
        compiled_debug.process(context, out_debug)
        if !buffers_identical(out_normal, out_debug, PROP_BLOCK_SIZE) {
          identical = false
        }
      }
      identical
    },
    max_success=200,
  )
}

///|
test "prop: stereo debug mode produces same output as normal mode (acyclic)" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_stereo_graph(seed)
      let compiled_normal = compile_stereo(nodes)
      let compiled_debug = compile_stereo(nodes)
      compiled_debug.enable_debug_validation()
      let left_normal = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let right_normal = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let left_debug = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let right_debug = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let context = DspContext::new(
        sample_rate=PROP_SAMPLE_RATE,
        block_size=PROP_BLOCK_SIZE,
      )
      let mut identical = true
      for _block = 0; _block < PROP_NUM_BLOCKS; _block = _block + 1 {
        compiled_normal.process(context, left_normal, right_normal)
        compiled_debug.process(context, left_debug, right_debug)
        if !buffers_identical(left_normal, left_debug, PROP_BLOCK_SIZE) ||
          !buffers_identical(right_normal, right_debug, PROP_BLOCK_SIZE) {
          identical = false
        }
      }
      identical
    },
    max_success=200,
  )
}

///|
/// Debug mode produces bit-identical output to production for mono feedback
/// graphs. Debug validates once per block, then delegates to the same
/// per-sample feedback path as production.
test "prop: debug mode equals production for mono feedback graphs" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_mono_feedback_graph(seed)
      let compiled_debug = compile_mono(nodes)
      let compiled_prod = compile_mono(nodes)
      guard compiled_debug.has_feedback_edges() else { return true }
      compiled_debug.enable_debug_validation()
      let out_debug = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let out_prod = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let context = DspContext::new(
        sample_rate=PROP_SAMPLE_RATE,
        block_size=PROP_BLOCK_SIZE,
      )
      let mut identical = true
      for _block = 0; _block < PROP_NUM_BLOCKS; _block = _block + 1 {
        compiled_debug.process(context, out_debug)
        compiled_prod.process(context, out_prod)
        if !buffers_identical(out_debug, out_prod, PROP_BLOCK_SIZE) {
          identical = false
        }
      }
      identical
    },
    max_success=200,
  )
}

///|
/// Debug mode produces bit-identical output to production for stereo feedback
/// graphs. Debug validates once per block, then delegates to the same
/// per-sample feedback path as production.
test "prop: debug mode equals production for stereo feedback graphs" {
  @qc.quick_check_fn(
    fn(seed : Int) {
      let nodes = gen_stereo_feedback_graph(seed)
      let compiled_debug = compile_stereo(nodes)
      let compiled_prod = compile_stereo(nodes)
      guard compiled_debug.has_feedback_edges() else { return true }
      compiled_debug.enable_debug_validation()
      let left_debug = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let right_debug = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let left_prod = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let right_prod = AudioBuffer::filled(PROP_BLOCK_SIZE)
      let context = DspContext::new(
        sample_rate=PROP_SAMPLE_RATE,
        block_size=PROP_BLOCK_SIZE,
      )
      let mut identical = true
      for _block = 0; _block < PROP_NUM_BLOCKS; _block = _block + 1 {
        compiled_debug.process(context, left_debug, right_debug)
        compiled_prod.process(context, left_prod, right_prod)
        if !buffers_identical(left_debug, left_prod, PROP_BLOCK_SIZE) ||
          !buffers_identical(right_debug, right_prod, PROP_BLOCK_SIZE) {
          identical = false
        }
      }
      identical
    },
    max_success=200,
  )
}
