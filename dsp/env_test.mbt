///|
test "adsr starts in idle stage" {
  let env = Adsr::new(attack_ms=5.0, decay_ms=5.0, sustain=0.5, release_ms=10.0)
  assert_true(env.stage() is EnvStage::Idle)
  assert_true(env.level() == 0.0)
}

///|
test "adsr gate_on triggers attack" {
  let env = Adsr::new(attack_ms=5.0, decay_ms=5.0, sustain=0.5, release_ms=10.0)
  env.gate_on()
  assert_true(env.stage() is EnvStage::Attack)
}

///|
test "adsr transitions through all stages" {
  let env = Adsr::new(attack_ms=1.0, decay_ms=1.0, sustain=0.5, release_ms=1.0)
  let ctx = DspContext::new(sample_rate=1000.0, block_size=8)
  let buf = AudioBuffer::filled(8)
  env.gate_on()
  env.process(ctx, buf)
  assert_true(env.stage() is EnvStage::Sustain)
  env.gate_off()
  assert_true(env.stage() is EnvStage::Release)
  env.process(ctx, buf)
  assert_true(env.stage() is EnvStage::Idle)
}

///|
test "adsr zero attack reaches peak immediately" {
  let env = Adsr::new(attack_ms=0.0, decay_ms=5.0, sustain=0.5, release_ms=10.0)
  let ctx = DspContext::new(sample_rate=48000.0, block_size=1)
  let buf = AudioBuffer::filled(1)
  env.gate_on()
  env.process(ctx, buf)
  assert_true(buf.get(0) >= 0.99)
}

///|
test "adsr reset returns to idle" {
  let env = Adsr::new(attack_ms=5.0, decay_ms=5.0, sustain=0.5, release_ms=10.0)
  env.gate_on()
  assert_true(env.stage() is EnvStage::Attack)
  env.reset()
  assert_true(env.stage() is EnvStage::Idle)
  assert_true(env.level() == 0.0)
}

///|
test "adsr zero-time attack/decay/release skips via loop not recursion" {
  let env = Adsr::new(attack_ms=0.0, decay_ms=0.0, sustain=0.5, release_ms=0.0)
  let ctx = DspContext::new(sample_rate=48000.0, block_size=1)
  let buf = AudioBuffer::filled(1)
  // After gate_on + tick: should skip attack and decay, land on sustain
  env.gate_on()
  env.process(ctx, buf)
  assert_true(env.stage() is EnvStage::Sustain)
  assert_true(buf.get(0) == 0.5)
  // After gate_off + tick: should skip release, land on idle
  env.gate_off()
  env.process(ctx, buf)
  assert_true(env.stage() is EnvStage::Idle)
  assert_true(buf.get(0) == 0.0)
}

///|
test "prop: adsr output in [0, 1]" {
  @qc.quick_check_fn(
    fn(params : (Double, Double, Double, Double)) {
      let (raw_a, raw_d, raw_s, raw_r) = params
      let attack_ms = raw_a.abs() * 100.0
      let decay_ms = raw_d.abs() * 100.0
      let sustain = raw_s.abs()
      let sustain_clamped = if sustain > 1.0 { 1.0 } else { sustain }
      let release_ms = raw_r.abs() * 100.0
      if attack_ms.is_nan() ||
        decay_ms.is_nan() ||
        release_ms.is_nan() ||
        sustain_clamped.is_nan() {
        return true
      }
      let env = Adsr::new(
        attack_ms~,
        decay_ms~,
        sustain=sustain_clamped,
        release_ms~,
      )
      let ctx = DspContext::new(sample_rate=48000.0, block_size=64)
      let buf = AudioBuffer::filled(64)
      env.gate_on()
      env.process(ctx, buf)
      for i = 0; i < 64; i = i + 1 {
        let v = buf.get(i)
        if v < -0.001 || v > 1.001 {
          return false
        }
      }
      env.gate_off()
      env.process(ctx, buf)
      for i = 0; i < 64; i = i + 1 {
        let v = buf.get(i)
        if v < -0.001 || v > 1.001 {
          return false
        }
      }
      true
    },
    max_success=100,
  )
}
