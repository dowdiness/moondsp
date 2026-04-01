///|
test "noise is deterministic given same seed" {
  let noise1 = Noise::new(42U)
  let noise2 = Noise::new(42U)
  let ctx = DspContext::new(48000.0, 8)
  let buf1 = AudioBuffer::filled(8)
  let buf2 = AudioBuffer::filled(8)
  noise1.process(ctx, buf1)
  noise2.process(ctx, buf2)
  for i = 0; i < 8; i = i + 1 {
    assert_true(buf1.get(i) == buf2.get(i))
  }
}

///|
test "different seeds produce different sequences" {
  let noise1 = Noise::new(1U)
  let noise2 = Noise::new(2U)
  let mut differs = false
  for i = 0; i < 16; i = i + 1 {
    if noise1.tick() != noise2.tick() {
      differs = true
      break
    }
  }
  assert_true(differs)
}

///|
test "noise reset reproduces original sequence" {
  let noise = Noise::new(42U)
  let first = noise.tick()
  let second = noise.tick()
  noise.reset(42U)
  assert_true(noise.tick() == first)
  assert_true(noise.tick() == second)
}

///|
test "prop: noise output in [-1, 1]" {
  @qc.quick_check_fn(
    fn(raw_seed : UInt) {
      let seed = if raw_seed == 0U { 1U } else { raw_seed }
      let noise = Noise::new(seed)
      for i = 0; i < 256; i = i + 1 {
        let sample = noise.tick()
        if sample < -1.0 || sample > 1.0 {
          return false
        }
      }
      true
    },
    max_success=100,
  )
}
