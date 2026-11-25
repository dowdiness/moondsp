///|
test "the sampler is silent until its sample commits" {
  assert_eq(init_sample_store(), SAMPLE_CAPACITY)
  // Making it again keeps the one store.
  assert_eq(init_sample_store(), SAMPLE_CAPACITY)
  let ping = @score.Sample::parse("ping").unwrap().number()
  assert_true(!sample_loaded(ping))
  assert_eq(sample_score_energy("s(\"ping\").slow(40)"), 0.0)
  // A noise burst.
  let length = 4800
  let mut state = 12345
  assert_eq(sample_load_begin(ping, length, 60.0), 0)
  for offset in 0..<length {
    state = (state * 1103515245 + 12345) & 0x7fffffff
    sample_load_write(
      offset,
      Float::from_double(state.to_double() / 1073741824.0 - 1.0),
    )
  }
  // Pending, not yet committed: still silence.
  assert_eq(sample_score_energy("s(\"ping\").slow(40)"), 0.0)
  assert_true(sample_load_commit())
  assert_true(sample_loaded(ping))
  assert_true(sample_score_energy("s(\"ping\").slow(40)") > 1.0)
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

///|
test "begin, end and speed slice and pace a sample from the score" {
  load_sine_for_test(@score.Sample::parse("ping").unwrap().number())
  // The window is 48 blocks, 6,144 samples, of the one-second sine.
  let whole = sample_score_energy("s(\"ping\").slow(40)")
  // `end(0.05)` stops after 2,400 samples; `begin(0.98)` plays the last 960.
  let ended = sample_score_energy("s(\"ping\").slow(40).end(0.05)")
  let begun = sample_score_energy("s(\"ping\").slow(40).begin(0.98)")
  assert_true((ended / whole - 2400.0 / 6144.0).abs() < 0.02)
  assert_true((begun / whole - 960.0 / 6144.0).abs() < 0.02)
  // Backwards from the end fills the window as forwards does.
  let backwards = sample_score_energy("s(\"ping\").slow(40).speed(-1)")
  assert_true((backwards / whole - 1.0).abs() < 0.02)
  // Twice as fast reads 440 Hz as 880 Hz: still a full window of sine.
  let fast = sample_score_energy("s(\"ping\").slow(40).speed(2)")
  assert_true((fast / whole - 1.0).abs() < 0.02)
  // Within `end(0.05)`, speed 2 reads its 2,400 samples in 1,200 and speed
  // 0.5 in 4,800, so speed reaches the sampler voice.
  let ended_fast = sample_score_energy(
    "s(\"ping\").slow(40).end(0.05).speed(2)",
  )
  let ended_slow = sample_score_energy(
    "s(\"ping\").slow(40).end(0.05).speed(0.5)",
  )
  assert_true((ended_fast / ended - 0.5).abs() < 0.02)
  assert_true((ended_slow / ended - 2.0).abs() < 0.04)
  assert_eq(
    sample_score_energy("s(\"ping\").slow(40).begin(0.5).end(0.25)"),
    0.0,
  )
}
