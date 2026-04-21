///|
using @dsp {type AudioBuffer, type DspContext, type Waveform}

///|
using @graph {type CompiledDsp, type DspNode}

///|
test "is_voice_finished returns false during active envelope" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let nodes = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=5.0, decay_ms=5.0, sustain=0.5, release_ms=50.0),
    DspNode::mul(0, 1),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
  ignore(compiled.gate_on(1))
  let buf = AudioBuffer::filled(16)
  compiled.process(ctx, buf)
  assert_true(!compiled.is_voice_finished())
}

///|
test "is_voice_finished returns true after envelope completes release" {
  let ctx = DspContext::new(sample_rate=1000.0, block_size=8)
  let nodes = [
    DspNode::oscillator(Waveform::Sine, 100.0),
    DspNode::adsr(attack_ms=0.0, decay_ms=0.0, sustain=1.0, release_ms=1.0),
    DspNode::mul(0, 1),
    DspNode::output(2),
  ]
  let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
  ignore(compiled.gate_on(1))
  let buf = AudioBuffer::filled(8)
  compiled.process(ctx, buf)
  ignore(compiled.gate_off(1))
  for i = 0; i < 10; i = i + 1 {
    compiled.process(ctx, buf)
  }
  assert_true(compiled.is_voice_finished())
}

///|
test "is_voice_finished returns true for graph with no ADSR when output is silent" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [DspNode::constant(0.0), DspNode::output(0)]
  let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
  let buf = AudioBuffer::filled(4)
  compiled.process(ctx, buf)
  assert_true(compiled.is_voice_finished())
}

///|
test "is_voice_finished returns false when delay tail is audible" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let nodes = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=0.0, decay_ms=0.0, sustain=1.0, release_ms=0.0),
    DspNode::mul(0, 1),
    DspNode::delay(2, 4800, delay_samples=16, feedback=0.9),
    DspNode::output(3),
  ]
  let compiled = CompiledDsp::compile(nodes, ctx).unwrap()
  ignore(compiled.gate_on(1))
  let buf = AudioBuffer::filled(16)
  compiled.process(ctx, buf)
  ignore(compiled.gate_off(1))
  compiled.process(ctx, buf)
  assert_true(!compiled.is_voice_finished())
}

///|
test "voice pool constructor accepts valid template" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx)
  assert_true(pool is Some(_))
  assert_true(pool.unwrap().active_voice_count() == 0)
}

///|
test "voice pool constructor rejects invalid template" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let nodes : Array[DspNode] = []
  let pool = VoicePool::new(nodes, ctx)
  assert_true(pool is None)
}

///|
test "voice pool constructor rejects template with orphan ADSR" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  // ADSR at index 1 is unwired — gain reads from osc (0), not adsr (1).
  // Without the orphan-ADSR guard, VoicePool::note_on would silently no-op
  // `gate_on(1)` and voices would play with a flat envelope.
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=5.0, decay_ms=5.0, sustain=0.5, release_ms=50.0),
    DspNode::gain(0, 1.0),
    DspNode::output(2),
  ]
  let pool = VoicePool::new(template, ctx)
  assert_true(pool is None)
}

///|
test "voice pool constructor accepts wired-ADSR template via envelope_gain" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=5.0, decay_ms=5.0, sustain=0.5, release_ms=50.0),
    DspNode::envelope_gain(0, 1, 1.0),
    DspNode::output(2),
  ]
  let pool = VoicePool::new(template, ctx)
  assert_true(pool is Some(_))
}

///|
test "set_template rejects template with orphan ADSR" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let wired_template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=5.0, decay_ms=5.0, sustain=0.5, release_ms=50.0),
    DspNode::envelope_gain(0, 1, 1.0),
    DspNode::output(2),
  ]
  let pool = VoicePool::new(wired_template, ctx).unwrap()
  let orphan_template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=5.0, decay_ms=5.0, sustain=0.5, release_ms=50.0),
    DspNode::gain(0, 1.0),
    DspNode::output(2),
  ]
  assert_true(!pool.set_template(orphan_template))
}

///|
test "set_template rejection leaves previous template intact" {
  // Regression guard: a failed set_template must not partially mutate state.
  // note_on must still work against the original (wired) template after the
  // rejected attempt.
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let wired_template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=5.0, decay_ms=5.0, sustain=0.5, release_ms=50.0),
    DspNode::envelope_gain(0, 1, 1.0),
    DspNode::output(2),
  ]
  let pool = VoicePool::new(wired_template, ctx).unwrap()
  let orphan_template = [
    DspNode::oscillator(Waveform::Sine, 440.0),
    DspNode::adsr(attack_ms=5.0, decay_ms=5.0, sustain=0.5, release_ms=50.0),
    DspNode::gain(0, 1.0),
    DspNode::output(2),
  ]
  assert_true(!pool.set_template(orphan_template))
  // Pool should still be usable with the original template.
  assert_true(pool.note_on([]) is Some(_))
  assert_true(pool.active_voice_count() == 1)
}

///|
test "set_template accepts valid template" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx).unwrap()
  let new_nodes = [DspNode::constant(880.0), DspNode::output(0)]
  assert_true(pool.set_template(new_nodes))
}

///|
test "set_template rejects invalid template" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx).unwrap()
  assert_true(!pool.set_template([]))
}

///|
test "note_on allocates a voice and returns valid handle" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let handle = pool.note_on([])
  assert_true(handle is Some(_))
  assert_true(pool.active_voice_count() == 1)
}

///|
test "note_on fills pool to capacity" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  for i = 0; i < 4; i = i + 1 {
    let h = pool.note_on([])
    assert_true(h is Some(_))
  }
  assert_true(pool.active_voice_count() == 4)
}

///|
test "note_on steals oldest active when pool is full" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=2).unwrap()
  let h1 = pool.note_on([]).unwrap()
  ignore(pool.note_on([]))
  let h3 = pool.note_on([]).unwrap()
  // h1's slot was stolen
  assert_true(h3.slot == h1.slot)
}

///|
test "note_off transitions voice to Releasing" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let nodes = [
    DspNode::constant(440.0),
    DspNode::adsr(attack_ms=5.0, decay_ms=5.0, sustain=0.5, release_ms=50.0),
    DspNode::output(1),
  ]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let handle = pool.note_on([]).unwrap()
  assert_true(pool.voice_state(handle) is VoiceState::Active)
  assert_true(pool.note_off(handle))
  assert_true(pool.voice_state(handle) is VoiceState::Releasing)
}

///|
test "stale handle note_off returns false" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=1).unwrap()
  let h1 = pool.note_on([]).unwrap()
  ignore(pool.note_on([]))
  assert_true(!pool.note_off(h1))
}

///|
test "stale handle voice_state returns Idle" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=1).unwrap()
  let h1 = pool.note_on([]).unwrap()
  ignore(pool.note_on([]))
  assert_true(pool.voice_state(h1) is VoiceState::Idle)
}

///|
test "set_voice_pan with stale handle returns false" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=1).unwrap()
  let h1 = pool.note_on([]).unwrap()
  ignore(pool.note_on([]))
  assert_true(!pool.set_voice_pan(h1, 0.5))
}

///|
test "drum template sd: noise envelope decays to silence via envelope_gain" {
  // Exact sd_template from browser_scheduler: noise → biquad → adsr → envelope_gain → output
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  let nodes = [
    DspNode::noise(12345U),
    DspNode::biquad(
      input=0,
      mode=@graph.BiquadMode::BandPass,
      cutoff_hz=800.0,
      q=2.0,
    ),
    DspNode::adsr(attack_ms=1.0, decay_ms=80.0, sustain=0.0, release_ms=50.0),
    DspNode::envelope_gain(1, 2, 1.0),
    DspNode::output(3),
  ]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let handle = pool.note_on([]).unwrap()
  // First block: should have non-zero output (attack/decay phase)
  let left1 = AudioBuffer::filled(128)
  let right1 = AudioBuffer::filled(128)
  pool.process(ctx, left1, right1)
  let mut has_nonzero = false
  for i = 0; i < 128; i = i + 1 {
    if left1.get(i).abs() > 0.001 {
      has_nonzero = true
      break
    }
  }
  assert_true(has_nonzero)
  // After note_off + several blocks, output should decay to silence
  assert_true(pool.note_off(handle))
  for j = 0; j < 50; j = j + 1 {
    let left = AudioBuffer::filled(128)
    let right = AudioBuffer::filled(128)
    pool.process(ctx, left, right)
  }
  // Voice should be reclaimed (Idle) — envelope finished
  assert_true(pool.voice_state(handle) is VoiceState::Idle)
}

///|
test "process produces stereo output from mono voices" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  ignore(pool.note_on([]))
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pool.process(ctx, left, right)
  for i = 0; i < 4; i = i + 1 {
    assert_true(left.get(i) > 0.0)
    assert_true(right.get(i) > 0.0)
    assert_true((left.get(i) - right.get(i)).abs() < 0.0001)
  }
}

///|
test "process pans hard left" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let handle = pool.note_on([]).unwrap()
  ignore(pool.set_voice_pan(handle, -1.0))
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pool.process(ctx, left, right)
  for i = 0; i < 4; i = i + 1 {
    assert_true(left.get(i) > 0.9)
    assert_true(right.get(i).abs() < 0.0001)
  }
}

///|
test "process reclaims finished releasing voices" {
  let ctx = DspContext::new(sample_rate=1000.0, block_size=8)
  let nodes = [
    DspNode::constant(0.0),
    DspNode::adsr(attack_ms=0.0, decay_ms=0.0, sustain=1.0, release_ms=0.0),
    DspNode::output(1),
  ]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  let handle = pool.note_on([]).unwrap()
  let left = AudioBuffer::filled(8)
  let right = AudioBuffer::filled(8)
  pool.process(ctx, left, right)
  assert_true(pool.active_voice_count() == 1)
  assert_true(pool.note_off(handle))
  left.fill(0.0)
  right.fill(0.0)
  pool.process(ctx, left, right)
  assert_true(pool.active_voice_count() == 0)
}

///|
test "process mixes multiple voices" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  ignore(pool.note_on([]))
  ignore(pool.note_on([]))
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pool.process(ctx, left, right)
  let one_voice_left = AudioBuffer::filled(4)
  let one_voice_right = AudioBuffer::filled(4)
  let pool2 = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  ignore(pool2.note_on([]))
  pool2.process(ctx, one_voice_left, one_voice_right)
  for i = 0; i < 4; i = i + 1 {
    assert_true((left.get(i) - 2.0 * one_voice_left.get(i)).abs() < 0.001)
  }
}

///|
test "new voices use updated template after set_template" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes_a = [DspNode::constant(1.0), DspNode::output(0)]
  let nodes_b = [DspNode::constant(2.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes_a, ctx, max_voices=4).unwrap()
  let _h1 = pool.note_on([]).unwrap()
  let left1 = AudioBuffer::filled(4)
  let right1 = AudioBuffer::filled(4)
  pool.process(ctx, left1, right1)
  let first_output = left1.get(0)
  assert_true(pool.set_template(nodes_b))
  let _h2 = pool.note_on([]).unwrap()
  let left2 = AudioBuffer::filled(4)
  let right2 = AudioBuffer::filled(4)
  pool.process(ctx, left2, right2)
  assert_true(left2.get(0) > first_output * 1.5)
}

///|
test "stealing prefers releasing over active" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let nodes = [
    DspNode::constant(440.0),
    DspNode::adsr(attack_ms=5.0, decay_ms=5.0, sustain=0.5, release_ms=100.0),
    DspNode::output(1),
  ]
  let pool = VoicePool::new(nodes, ctx, max_voices=2).unwrap()
  let h1 = pool.note_on([]).unwrap()
  let h2 = pool.note_on([]).unwrap()
  let left = AudioBuffer::filled(16)
  let right = AudioBuffer::filled(16)
  pool.process(ctx, left, right)
  assert_true(pool.note_off(h1))
  assert_true(pool.voice_state(h1) is VoiceState::Releasing)
  assert_true(pool.voice_state(h2) is VoiceState::Active)
  let h3 = pool.note_on([]).unwrap()
  assert_true(h3.slot == h1.slot)
}

///|
test "VoicePool process sanitizes final mixdown output" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=4)
  let nodes = [DspNode::constant(1.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=2).unwrap()
  ignore(pool.note_on([]))
  let left = AudioBuffer::filled(4)
  let right = AudioBuffer::filled(4)
  pool.process(ctx, left, right)
  // Clean constant output should have zero sanitized count
  assert_eq(pool.last_sanitized_count(), 0)
  // Verify output is non-zero (voice was active)
  assert_true(left.get(0) > 0.0)
}
