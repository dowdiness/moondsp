///|
test "sanitize_buffer: clean buffer returns 0" {
  let buf = AudioBuffer::filled(4)
  buf.set(0, 0.5)
  buf.set(1, -0.3)
  buf.set(2, 1.0)
  buf.set(3, 0.0)
  let count = sanitize_buffer(buf, 4)
  assert_eq(count, 0)
  assert_eq(buf.get(0), 0.5)
  assert_eq(buf.get(3), 0.0)
}

///|
test "sanitize_buffer: NaN replaced with 0.0" {
  let buf = AudioBuffer::filled(4)
  buf.set(0, 0.5)
  buf.set(1, @double.not_a_number)
  buf.set(2, @double.not_a_number)
  buf.set(3, 0.5)
  let count = sanitize_buffer(buf, 4)
  assert_eq(count, 2)
  assert_eq(buf.get(0), 0.5)
  assert_eq(buf.get(1), 0.0)
  assert_eq(buf.get(2), 0.0)
  assert_eq(buf.get(3), 0.5)
}

///|
test "sanitize_buffer: +Inf and -Inf replaced" {
  let buf = AudioBuffer::filled(4)
  buf.set(0, @double.infinity)
  buf.set(1, @double.neg_infinity)
  buf.set(2, 0.5)
  buf.set(3, @double.not_a_number)
  let count = sanitize_buffer(buf, 4)
  assert_eq(count, 3)
  assert_eq(buf.get(0), 0.0)
  assert_eq(buf.get(1), 0.0)
  assert_eq(buf.get(2), 0.5)
  assert_eq(buf.get(3), 0.0)
}

///|
test "sanitize_buffer: sample_count clamped to buffer length" {
  let buf = AudioBuffer::filled(2)
  buf.set(0, @double.not_a_number)
  buf.set(1, 0.5)
  let count = sanitize_buffer(buf, 100)
  assert_eq(count, 1)
  assert_eq(buf.get(0), 0.0)
  assert_eq(buf.get(1), 0.5)
}

///|
test "sanitize_buffer: zero sample_count returns 0" {
  let buf = AudioBuffer::filled(4)
  buf.set(0, @double.not_a_number)
  let count = sanitize_buffer(buf, 0)
  assert_eq(count, 0)
  assert_true(buf.get(0).is_nan())
}

///|
test "sanitize_buffer: idempotent — sanitized buffer returns 0" {
  let buf = AudioBuffer::filled(4)
  buf.set(0, @double.not_a_number)
  buf.set(1, @double.infinity)
  let first = sanitize_buffer(buf, 4)
  assert_eq(first, 2)
  let second = sanitize_buffer(buf, 4)
  assert_eq(second, 0)
}
