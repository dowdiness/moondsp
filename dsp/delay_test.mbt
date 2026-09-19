///|
test "delay line delays impulse by delay_samples" {
  let delay = DelayLine::new(8, delay_samples=3)
  assert_true(delay.tick(1.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 1.0)
  assert_true(delay.tick(0.0) == 0.0)
}

///|
test "delay with zero delay_samples is passthrough" {
  let delay = DelayLine::new(8, delay_samples=0)
  assert_true(delay.tick(0.5) == 0.5)
  assert_true(delay.tick(0.7) == 0.7)
}

///|
test "delay with max delay_samples uses full buffer" {
  let delay = DelayLine::new(4, delay_samples=4)
  assert_true(delay.tick(1.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 1.0)
}

///|
test "delay feedback accumulates energy" {
  let delay = DelayLine::new(2, delay_samples=1, feedback=0.5)
  let first = delay.tick(1.0)
  assert_true(first == 0.0)
  let second = delay.tick(0.0)
  assert_true(second == 1.0)
  let third = delay.tick(0.0)
  assert_true((third - 0.5).abs() < 0.000001)
}

///|
test "delay set_delay_samples changes delay mid-stream" {
  let delay = DelayLine::new(8, delay_samples=2)
  ignore(delay.tick(1.0))
  ignore(delay.tick(0.0))
  assert_true(delay.tick(0.0) == 1.0)
  delay.set_delay_samples(1)
  ignore(delay.tick(0.5))
  assert_true(delay.tick(0.0) == 0.5)
}

///|
test "delay reset returns silence for unwritten samples" {
  let delay = DelayLine::new(4, delay_samples=1, feedback=0.5)
  ignore(delay.tick(1.0))
  ignore(delay.tick(0.0))
  delay.reset()
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
}

///|
test "delay reset keeps configured delay and feedback" {
  let delay = DelayLine::new(8, delay_samples=3, feedback=0.25)
  ignore(delay.tick(1.0))
  delay.reset()
  assert_eq(delay.delay_samples(), 3)
  assert_eq(delay.feedback(), 0.25)
  assert_true(delay.tick(1.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 1.0)
}

///|
test "delay reset silences stale wrap-around content" {
  let delay = DelayLine::new(4, delay_samples=2, feedback=0.0)
  // Fill and wrap so every physical slot holds a non-zero value.
  ignore(delay.tick(1.0))
  ignore(delay.tick(2.0))
  ignore(delay.tick(3.0))
  ignore(delay.tick(4.0))
  ignore(delay.tick(5.0))
  delay.reset()
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
}

///|
test "delay reset then length change still reads silence until written" {
  let delay = DelayLine::new(8, delay_samples=1, feedback=0.9)
  ignore(delay.tick(1.0))
  ignore(delay.tick(1.0))
  delay.reset()
  delay.set_delay_samples(4)
  assert_true(delay.tick(0.5) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.0)
  assert_true(delay.tick(0.0) == 0.5)
}

///|
test "delay reset blocks feedback from stale samples" {
  let delay = DelayLine::new(4, delay_samples=1, feedback=0.9)
  ignore(delay.tick(1.0))
  ignore(delay.tick(0.0))
  delay.reset()
  assert_true(delay.tick(0.0) == 0.0)
  // Without valid-range guarding, feedback would recirculate the old impulse.
  assert_true(delay.tick(0.0) == 0.0)
}

///|
enum DelayOperation {
  Tick(Double)
  Reset
  SetDelay(Int)
}

///|
struct PhysicalDelayReference {
  mut history : Array[Double]
  mut delay_samples : Int
  feedback : Double
}

///|
fn new_physical_delay_reference(
  delay_samples : Int,
  feedback : Double,
) -> PhysicalDelayReference {
  { history: [], delay_samples, feedback, }
}

///|
fn physical_reference_tick(
  reference : PhysicalDelayReference,
  input : Double,
) -> Double {
  if reference.delay_samples == 0 {
    reference.history.push(input)
    input
  } else {
    let history_length = reference.history.length()
    let output = if history_length >= reference.delay_samples {
      reference.history[history_length - reference.delay_samples]
    } else {
      0.0
    }
    reference.history.push(input + output * reference.feedback)
    output
  }
}

///|
fn physical_reference_reset(reference : PhysicalDelayReference) -> Unit {
  reference.history = []
}

///|
fn assert_delay_operations(
  actual : DelayLine,
  reference : PhysicalDelayReference,
  operations : Array[DelayOperation],
) -> Unit raise {
  for operation in operations {
    match operation {
      Tick(input) => {
        let actual_output = actual.tick(input)
        let reference_output = physical_reference_tick(reference, input)
        assert_true((actual_output - reference_output).abs() < 0.000000000001)
      }
      Reset => {
        actual.reset()
        physical_reference_reset(reference)
      }
      SetDelay(delay_samples) => {
        actual.set_delay_samples(delay_samples)
        reference.delay_samples = delay_samples
      }
    }
  }
}

///|
test "delay reset matches physical reference across state transitions" {
  let actual = DelayLine::new(5, delay_samples=2, feedback=0.5)
  let reference = new_physical_delay_reference(2, 0.5)
  let operations : Array[DelayOperation] = [
    Tick(1.0),
    Tick(0.0),
    Tick(2.0),
    Tick(0.0),
    Tick(0.0),
    Tick(0.0),
    Reset,
    SetDelay(4),
    Tick(0.5),
    Tick(0.0),
    Tick(0.0),
    Tick(0.0),
    Tick(0.0),
    SetDelay(0),
    Tick(0.75),
    Tick(-0.25),
    Reset,
    SetDelay(1),
    Tick(0.25),
    Tick(0.0),
  ]
  assert_delay_operations(actual, reference, operations)
}

///|
test "delay reset matches physical reference at capacity one" {
  let actual = DelayLine::new(1, delay_samples=1, feedback=0.25)
  let reference = new_physical_delay_reference(1, 0.25)
  let operations : Array[DelayOperation] = [
    Tick(1.0),
    Tick(0.0),
    Reset,
    Tick(0.0),
    Reset,
    Tick(0.5),
    SetDelay(0),
    Tick(-0.25),
    SetDelay(1),
    Tick(0.0),
    Reset,
    Tick(0.0),
  ]
  assert_delay_operations(actual, reference, operations)
}
