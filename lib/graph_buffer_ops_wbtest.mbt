///|
test "copy_buffer: source shorter than target zero-fills remainder" {
  let src = AudioBuffer::filled(2, init=0.8)
  let tgt = AudioBuffer::filled(4)
  copy_buffer(src, tgt, 4)
  inspect(tgt.get(0), content="0.8")
  inspect(tgt.get(1), content="0.8")
  inspect(tgt.get(2), content="0")
  inspect(tgt.get(3), content="0")
}

///|
test "copy_buffer: same length copies all samples" {
  let src = AudioBuffer::filled(4, init=0.5)
  let tgt = AudioBuffer::filled(4, init=1.0)
  copy_buffer(src, tgt, 4)
  assert_true(tgt.as_fixed_array().every(sample => sample == 0.5))
}

///|
test "copy_buffer: sample_count less than source length" {
  let src = AudioBuffer::filled(4, init=0.9)
  let tgt = AudioBuffer::filled(4, init=1.0)
  copy_buffer(src, tgt, 2)
  inspect(tgt.get(0), content="0.9")
  inspect(tgt.get(1), content="0.9")
  inspect(tgt.get(2), content="0")
  inspect(tgt.get(3), content="0")
}

///|
test "fill_constant_buffer: partial fill zero-fills remainder" {
  let buf = AudioBuffer::filled(4)
  fill_constant_buffer(buf, 2, 0.7)
  inspect(buf.get(0), content="0.7")
  inspect(buf.get(1), content="0.7")
  inspect(buf.get(2), content="0")
  inspect(buf.get(3), content="0")
}

///|
test "fill_constant_buffer: full fill" {
  let buf = AudioBuffer::filled(4)
  fill_constant_buffer(buf, 4, 0.3)
  assert_true(buf.as_fixed_array().every(sample => sample == 0.3))
}

///|
test "apply_gain_buffer: gain zero produces silence" {
  let buf = AudioBuffer::filled(4, init=0.8)
  apply_gain_buffer(buf, 4, 0.0)
  assert_true(buf.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "apply_gain_buffer: gain one is passthrough" {
  let buf = AudioBuffer::filled(4, init=0.6)
  apply_gain_buffer(buf, 4, 1.0)
  assert_true(buf.as_fixed_array().every(sample => sample == 0.6))
}

///|
test "apply_gain_buffer: gain half halves values" {
  let buf = AudioBuffer::filled(4, init=1.0)
  apply_gain_buffer(buf, 4, 0.5)
  assert_true(buf.as_fixed_array().every(sample => sample == 0.5))
}

///|
test "apply_gain_buffer: negative gain inverts signal" {
  let buf = AudioBuffer::filled(4, init=0.4)
  apply_gain_buffer(buf, 4, -1.0)
  assert_true(buf.as_fixed_array().every(sample => sample == -0.4))
}

///|
test "mix_buffers: basic addition" {
  let left = AudioBuffer::filled(4, init=0.3)
  let right = AudioBuffer::filled(4, init=0.2)
  let output = AudioBuffer::filled(4)
  mix_buffers(left, right, output, 4)
  inspect(output.get(0), content="0.5")
  inspect(output.get(3), content="0.5")
}

///|
test "multiply_buffers: basic multiplication" {
  let left = AudioBuffer::filled(4, init=0.5)
  let right = AudioBuffer::filled(4, init=0.6)
  let output = AudioBuffer::filled(4)
  multiply_buffers(left, right, output, 4)
  inspect(output.get(0), content="0.3")
}

///|
test "multiply_buffers: ring modulation with zero" {
  let left = AudioBuffer::filled(4, init=0.8)
  let right = AudioBuffer::filled(4, init=0.0)
  let output = AudioBuffer::filled(4)
  multiply_buffers(left, right, output, 4)
  assert_true(output.as_fixed_array().every(sample => sample == 0.0))
}

///|
test "clip_buffer: values within threshold unchanged" {
  let buf = AudioBuffer::filled(4, init=0.3)
  clip_buffer(buf, 4, 1.0)
  assert_true(buf.as_fixed_array().every(sample => sample == 0.3))
}

///|
test "clip_buffer: values exceeding threshold are clipped" {
  let buf = AudioBuffer::filled(4, init=1.5)
  clip_buffer(buf, 4, 1.0)
  assert_true(buf.as_fixed_array().every(sample => sample == 1.0))
}

///|
test "clip_buffer: negative values clipped to negative threshold" {
  let buf = AudioBuffer::filled(4, init=-2.0)
  clip_buffer(buf, 4, 0.5)
  assert_true(buf.as_fixed_array().every(sample => sample == -0.5))
}

///|
test "min_buffer_length: various orderings" {
  inspect(min_buffer_length(4, 3, 2, 1), content="1")
  inspect(min_buffer_length(1, 2, 3, 4), content="1")
  inspect(min_buffer_length(5, 5, 5, 5), content="5")
  inspect(min_buffer_length(10, 3, 7, 4), content="3")
}

///|
test "copy_stereo_buffers: copies both channels" {
  let sl = AudioBuffer::filled(4, init=0.4)
  let sr = AudioBuffer::filled(4, init=0.6)
  let tl = AudioBuffer::filled(4)
  let tr = AudioBuffer::filled(4)
  copy_stereo_buffers(sl, sr, tl, tr, 4)
  assert_true(tl.as_fixed_array().every(sample => sample == 0.4))
  assert_true(tr.as_fixed_array().every(sample => sample == 0.6))
}

///|
test "mixdown_stereo_buffers: averages left and right" {
  let left = AudioBuffer::filled(4, init=0.8)
  let right = AudioBuffer::filled(4, init=0.2)
  let output = AudioBuffer::filled(4)
  mixdown_stereo_buffers(left, right, output, 4)
  assert_true(output.as_fixed_array().every(sample => sample == 0.5))
}
