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

///|
/// Load a one-second 440 Hz sine, the bank's `ping` at its root of A4, into
/// sample number `entry`.
fn load_sine_for_test(entry : Int32) -> Unit raise {
  assert_eq(sample_load_begin(entry, 48000, 0.0), 0)
  for i in 0..<48000 {
    sample_load_write(
      i,
      Float::from_double(
        @math.sin(2.0 * @math.PI * 440.0 * i.to_double() / 48000.0),
      ),
    )
  }
  assert_true(sample_load_commit())
}

///|
/// Energy of the score `text` over 48 blocks, on a player whose pools read
/// the browser's sample store.
fn sample_score_energy(text : String) -> Double raise {
  ignore(init_sample_store())
  rendered_synth_energy(text)
}

///|
test "scores play bank samples through s and .s, shaped by lpf and gain" {
  ignore(init_sample_store())
  // Nothing has loaded `burst` yet: its notes start and play silence.
  assert_true(!sample_loaded(@score.Sample::parse("burst").unwrap().number()))
  assert_eq(sample_score_energy("s(\"burst\").slow(40)"), 0.0)
  load_sine_for_test(@score.Sample::parse("ping").unwrap().number())
  let one_shot = sample_score_energy("s(\"ping\").slow(40)")
  let pitched = sample_score_energy("note(\"69\").slow(40).s(\"ping\")")
  let quieter = sample_score_energy("s(\"ping\").slow(40).gain(0.25)")
  let low_passed = sample_score_energy("s(\"ping\").slow(40).lpf(100)")
  assert_true(one_shot > 10.0)
  // `s("ping")` plays at the root, 69, so the two scores render alike.
  assert_true((pitched / one_shot - 1.0).abs() < 0.01)
  assert_true((quieter / one_shot - 0.25).abs() < 0.01)
  assert_true(low_passed < one_shot * 0.1)
  // An octave below the root reads the waveform at half speed: 220 Hz,
  // which a 300 Hz low-pass keeps and which passes it less than 440 Hz.
  let low = sample_score_energy("note(\"57\").slow(40).s(\"ping\").lpf(300)")
  let root = sample_score_energy("note(\"69\").slow(40).s(\"ping\").lpf(300)")
  assert_true(low > root * 2.0)
}
