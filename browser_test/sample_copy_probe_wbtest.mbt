///|
test "sample copy probe writes into the reserved waveform only" {
  assert_eq(sample_copy_reserve(-1), -1)
  assert_eq(sample_copy_reserve(3), 3)
  sample_copy_write(0, 0.5)
  sample_copy_write(2, -0.25)
  sample_copy_write(3, 9.0)
  sample_copy_write(-1, 9.0)
  assert_eq(sample_copy_sample(0), 0.5)
  assert_eq(sample_copy_sample(1), 0.0)
  assert_eq(sample_copy_sample(2), -0.25)
  assert_eq(sample_copy_sample(3), 0.0)
  assert_eq(sample_copy_checksum(), 0.25)
  assert_eq(sample_copy_reserve(2), 2)
  assert_eq(sample_copy_checksum(), 0.0)
}
