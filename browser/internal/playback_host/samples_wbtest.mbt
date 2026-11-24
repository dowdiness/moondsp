///|
/// Energy of `blocks` blocks of a sampler note on sample 0 of the browser
/// store, with its low-pass at `lpf_hz` and its voice gain at `gain`. The
/// note's controls are set as graph params, because no score plays samples yet
/// (ADR-0026 stage 4 waits for ADR-0023).
fn sampler_energy(
  pool : @moondsp.BoundVoicePool,
  ctx : @moondsp.DspContext,
  lpf_hz~ : Double = 18000.0,
  gain~ : Double = 1.0,
  blocks~ : Int32 = 8,
) -> Double raise {
  pool.kill_all()
  let handle = pool
    .note_on_graph_controls([
      @moondsp.GraphControl::set_param(0, @moondsp.GraphParamSlot::Value0, 0.0),
      @moondsp.GraphControl::set_param(
        2,
        @moondsp.GraphParamSlot::Value0,
        lpf_hz,
      ),
    ])
    .unwrap()
  assert_true(pool.set_voice_gain_result(handle, gain) is Ok(_))
  let left = @moondsp.AudioBuffer::filled(128)
  let right = @moondsp.AudioBuffer::filled(128)
  let mut energy = 0.0
  for _ in 0..<blocks {
    left.fill(0.0)
    right.fill(0.0)
    pool.process(ctx, left, right)
    for i in 0..<128 {
      energy = energy + left.get(i) * left.get(i)
    }
  }
  energy
}

///|
test "the sampler pool is silent until its sample loads, then lpf and gain shape it" {
  assert_eq(init_sample_store(), SAMPLE_CAPACITY)
  // Making it again keeps the one store.
  assert_eq(init_sample_store(), SAMPLE_CAPACITY)
  let ctx = sample_context(48000.0, 128)
  let pool = make_sample_pool(test_sampler, ctx).unwrap()
  assert_true(pool.binding(Lpf) is Some(_))
  assert_true(pool.binding(Note) is Some(_))
  assert_true(!sample_loaded(0))
  assert_eq(sampler_energy(pool, ctx), 0.0)
  // A noise burst, so the low-pass has highs to remove.
  let length = 4800
  let mut state = 12345
  assert_eq(sample_load_begin(0, length, 60.0), 0)
  for offset in 0..<length {
    state = (state * 1103515245 + 12345) & 0x7fffffff
    sample_load_write(
      offset,
      Float::from_double(state.to_double() / 1073741824.0 - 1.0),
    )
  }
  // Pending, not yet committed: still silence.
  assert_eq(sampler_energy(pool, ctx), 0.0)
  assert_true(sample_load_commit())
  assert_true(sample_loaded(0))
  let open = sampler_energy(pool, ctx)
  let filtered = sampler_energy(pool, ctx, lpf_hz=300.0)
  let quieter = sampler_energy(pool, ctx, gain=0.5)
  assert_true(open > 1.0)
  assert_true(filtered < open * 0.2)
  assert_true((quieter / open - 0.25).abs() < 0.01)
}

///|
test "sample loads report the limit they exceed" {
  ignore(init_sample_store())
  assert_eq(sample_load_begin(SAMPLE_ENTRIES, 4, 60.0), 1)
  assert_eq(sample_load_begin(1, SAMPLE_MAX_LENGTH + 1, 60.0), 2)
  assert_eq(sample_bank_name(0), "ping")
  assert_eq(sample_bank_name(sample_bank_count()), "")
}
