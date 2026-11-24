///|
test "sine retains rounded wrap and scalar overflow behavior" {
  let oscillator = Oscillator()
  let _ = oscillator.tick(freq_hz=-1UL.reinterpret_as_double(), sample_rate=1.0)
  assert_eq(oscillator.phase(), 1.0)
  assert_eq(
    oscillator.tick(freq_hz=0.0, sample_rate=1.0).reinterpret_as_uint64(),
    @math.sin(2.0 * @math.PI).reinterpret_as_uint64(),
  )
  oscillator.reset()
  let _ = oscillator.tick(freq_hz=1.0e308, sample_rate=1.0e-308)
  assert_true(oscillator.tick(freq_hz=1.0, sample_rate=48000.0).is_nan())
  oscillator.reset()
  assert_eq(oscillator.tick(freq_hz=440.0, sample_rate=48000.0), 0.0)
}
