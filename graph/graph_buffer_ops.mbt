///|
fn copy_buffer(
  source : AudioBuffer,
  target : AudioBuffer,
  sample_count : Int,
) -> Unit {
  let bounded = if sample_count < source.length() {
    if sample_count < target.length() {
      sample_count
    } else {
      target.length()
    }
  } else if source.length() < target.length() {
    source.length()
  } else {
    target.length()
  }

  for index = 0; index < bounded; index = index + 1 {
    target.set(index, source.get(index))
  }

  for index = bounded; index < target.length(); index = index + 1 {
    target.set(index, 0.0)
  }
}

///|
fn copy_stereo_buffers(
  source_left : AudioBuffer,
  source_right : AudioBuffer,
  target_left : AudioBuffer,
  target_right : AudioBuffer,
  sample_count : Int,
) -> Unit {
  copy_buffer(source_left, target_left, sample_count)
  copy_buffer(source_right, target_right, sample_count)
}

///|
fn mixdown_stereo_buffers(
  left : AudioBuffer,
  right : AudioBuffer,
  output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  let bounded = min_buffer_length(
    sample_count,
    left.length(),
    right.length(),
    output.length(),
  )
  for index = 0; index < bounded; index = index + 1 {
    output.set(index, (left.get(index) + right.get(index)) * 0.5)
  }
  for index = bounded; index < output.length(); index = index + 1 {
    output.set(index, 0.0)
  }
}

///|
fn fill_constant_buffer(
  buffer : AudioBuffer,
  sample_count : Int,
  value : Double,
) -> Unit {
  let bounded = if sample_count < buffer.length() {
    sample_count
  } else {
    buffer.length()
  }
  for index = 0; index < bounded; index = index + 1 {
    buffer.set(index, value)
  }
  for index = bounded; index < buffer.length(); index = index + 1 {
    buffer.set(index, 0.0)
  }
}

///|
fn apply_gain_buffer(
  buffer : AudioBuffer,
  sample_count : Int,
  amount : Double,
) -> Unit {
  let bounded = if sample_count < buffer.length() {
    sample_count
  } else {
    buffer.length()
  }
  for index = 0; index < bounded; index = index + 1 {
    buffer.set(index, buffer.get(index) * amount)
  }
  for index = bounded; index < buffer.length(); index = index + 1 {
    buffer.set(index, 0.0)
  }
}

///|
fn mix_buffers(
  left : AudioBuffer,
  right : AudioBuffer,
  output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  let bounded = min_buffer_length(
    sample_count,
    left.length(),
    right.length(),
    output.length(),
  )
  for index = 0; index < bounded; index = index + 1 {
    output.set(index, left.get(index) + right.get(index))
  }
  for index = bounded; index < output.length(); index = index + 1 {
    output.set(index, 0.0)
  }
}

///|
fn multiply_buffers(
  left : AudioBuffer,
  right : AudioBuffer,
  output : AudioBuffer,
  sample_count : Int,
) -> Unit {
  let bounded = min_buffer_length(
    sample_count,
    left.length(),
    right.length(),
    output.length(),
  )
  for index = 0; index < bounded; index = index + 1 {
    output.set(index, left.get(index) * right.get(index))
  }
  for index = bounded; index < output.length(); index = index + 1 {
    output.set(index, 0.0)
  }
}

///|
fn clip_buffer(
  buffer : AudioBuffer,
  sample_count : Int,
  threshold : Double,
) -> Unit {
  let bounded = if sample_count < buffer.length() {
    sample_count
  } else {
    buffer.length()
  }
  for index = 0; index < bounded; index = index + 1 {
    let sample = buffer.get(index)
    let clipped = if sample > threshold {
      threshold
    } else if sample < -threshold {
      -threshold
    } else {
      sample
    }
    buffer.set(index, clipped)
  }
  for index = bounded; index < buffer.length(); index = index + 1 {
    buffer.set(index, 0.0)
  }
}

///|
fn min_buffer_length(a : Int, b : Int, c : Int, d : Int) -> Int {
  let ab = if a < b { a } else { b }
  let cd = if c < d { c } else { d }
  if ab < cd {
    ab
  } else {
    cd
  }
}

///|
