///|
/// Stateful integer-sample delay line backed by a circular buffer.
pub struct DelayLine {
  buffer : FixedArray[Double]
  mut write_pos : Int
  mut delay_samples : Int
  mut feedback : Double

  fn new(
    max_delay_samples : Int,
    delay_samples? : Int,
    feedback? : Double,
  ) -> DelayLine
}

///|
/// Create a delay line with preallocated storage and a normalized delay length.
pub fn DelayLine::new(
  max_delay_samples : Int,
  delay_samples? : Int = default_delay_samples(max_delay_samples),
  feedback? : Double = 0.0,
) -> DelayLine {
  let capacity = max_delay_capacity(max_delay_samples)
  {
    buffer: FixedArray::make(capacity, 0.0),
    write_pos: 0,
    delay_samples: normalize_delay_samples(delay_samples, capacity),
    feedback: normalize_feedback(feedback),
  }
}

///|
/// Return the maximum representable delay length in samples.
pub fn DelayLine::max_delay_samples(self : DelayLine) -> Int {
  self.buffer.length()
}

///|
/// Return the active delay length in samples.
pub fn DelayLine::delay_samples(self : DelayLine) -> Int {
  self.delay_samples
}

///|
/// Return the active feedback amount.
pub fn DelayLine::feedback(self : DelayLine) -> Double {
  self.feedback
}

///|
/// Update the active delay length, clamping to the allocated storage range.
pub fn DelayLine::set_delay_samples(
  self : DelayLine,
  delay_samples : Int,
) -> Unit {
  self.delay_samples = normalize_delay_samples(
    delay_samples,
    self.buffer.length(),
  )
}

///|
/// Update the feedback amount, clamping to the stable supported range.
pub fn DelayLine::set_feedback(self : DelayLine, feedback : Double) -> Unit {
  self.feedback = normalize_feedback(feedback)
}

///|
/// Clear the circular buffer state without changing the configured delay.
pub fn DelayLine::reset(self : DelayLine) -> Unit {
  self.buffer.fill(0.0)
  self.write_pos = 0
}

///|
/// Process one input sample and return the delayed output sample.
pub fn DelayLine::tick(self : DelayLine, input : Double) -> Double {
  if self.delay_samples == 0 {
    self.buffer[self.write_pos] = input
    self.advance_write_pos()
    input
  } else {
    let read_pos = delayed_read_pos(
      self.write_pos,
      self.delay_samples,
      self.buffer.length(),
    )
    let output = self.buffer[read_pos]
    self.buffer[self.write_pos] = input + output * self.feedback
    self.advance_write_pos()
    output
  }
}

///|
/// Process one block of samples in place.
pub fn DelayLine::process(
  self : DelayLine,
  context : DspContext,
  buffer : AudioBuffer,
) -> Unit {
  let sample_rate = context.sample_rate()
  let sample_count = effective_sample_count(context, buffer)
  if !is_finite_positive(sample_rate) {
    buffer.fill(0.0)
    return
  }
  if sample_count <= 0 {
    buffer.fill(0.0)
    return
  }

  for index = 0; index < sample_count; index = index + 1 {
    let input = buffer.get(index)
    buffer.set(index, self.tick(input))
  }

  for index = sample_count; index < buffer.length(); index = index + 1 {
    buffer.set(index, 0.0)
  }
}

///|
fn DelayLine::advance_write_pos(self : DelayLine) -> Unit {
  self.write_pos = self.write_pos + 1
  if self.write_pos >= self.buffer.length() {
    self.write_pos = 0
  }
}

///|
fn delayed_read_pos(
  write_pos : Int,
  delay_samples : Int,
  capacity : Int,
) -> Int {
  let read_pos = write_pos - delay_samples
  if read_pos < 0 {
    read_pos + capacity
  } else {
    read_pos
  }
}

///|
fn max_delay_capacity(value : Int) -> Int {
  if value > 0 {
    value
  } else {
    1
  }
}

///|
fn default_delay_samples(value : Int) -> Int {
  if value > 0 {
    value
  } else {
    0
  }
}

///|
fn normalize_delay_samples(value : Int, capacity : Int) -> Int {
  if value < 0 {
    0
  } else if value > capacity {
    capacity
  } else {
    value
  }
}

///|
fn normalize_feedback(value : Double) -> Double {
  if !is_finite(value) {
    0.0
  } else if value < -max_feedback_amount() {
    -max_feedback_amount()
  } else if value > max_feedback_amount() {
    max_feedback_amount()
  } else {
    value
  }
}

///|
fn max_feedback_amount() -> Double {
  0.99
}
