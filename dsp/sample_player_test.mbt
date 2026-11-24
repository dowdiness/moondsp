///|
fn sample_test_store() -> @dsp.SampleStore {
  @dsp.SampleStore(entries=4, max_length=16, capacity=64)
}

///|
fn sample_test_waveform(
  length : Int32,
  at : (Int32) -> Double,
) -> FixedArray[Float] {
  FixedArray::makei(length, index => Float::from_double(at(index)))
}

///|
/// The first `count` samples of `waveform`, as the player renders them.
fn sample_test_doubles(
  waveform : FixedArray[Float],
  count : Int32,
) -> Array[Double] {
  Array::makei(count, index => waveform[index].to_double())
}

///|
/// Plays `count` samples of `player`, one block of 4 at a time.
fn sample_test_play(
  player : @dsp.SamplePlayer,
  count : Int32,
  number~ : Double = 0.0,
  pitch~ : Double = 60.0,
  speed~ : Double = 1.0,
  begin~ : Double = 0.0,
  end~ : Double = 1.0,
) -> Array[Double] {
  let context = @dsp.DspContext(sample_rate=48000.0, block_size=4)
  let block = @dsp.AudioBuffer::filled(4)
  let played = []
  while played.length() < count {
    player.process(context, block, number~, pitch~, speed~, begin~, end~)
    for index in 0..<4 {
      played.push(block.get(index))
    }
  }
  played[:count].to_owned()
}

///|
test "a waveform plays unchanged at its root pitch and speed 1, then silence" {
  let store = sample_test_store()
  // Distinct, exactly representable values, so any misread shows.
  let waveform = sample_test_waveform(10, index => {
    (index + 1).to_double() / 16.0
  })
  assert_eq(store.register(2, waveform, root_pitch=60.0), None)
  let played = sample_test_play(@dsp.SamplePlayer(store), 12, number=2.0)
  for index in 0..<10 {
    assert_eq(played[index], waveform[index].to_double())
  }
  assert_eq(played[10:].to_owned(), [0.0, 0.0])
}

///|
test "speed 2 and a pitch an octave above the root both read every second sample" {
  let store = sample_test_store()
  let waveform = sample_test_waveform(12, index => index.to_double() / 8.0 - 0.5)
  assert_eq(store.register(0, waveform, root_pitch=48.0), None)
  let expected = [
    waveform[0].to_double(),
    waveform[2].to_double(),
    waveform[4].to_double(),
    waveform[6].to_double(),
    waveform[8].to_double(),
    waveform[10].to_double(),
    0.0,
    0.0,
  ]
  let by_speed = sample_test_play(
    @dsp.SamplePlayer(store),
    8,
    pitch=48.0,
    speed=2.0,
  )
  let by_pitch = sample_test_play(@dsp.SamplePlayer(store), 8, pitch=60.0)
  assert_eq(by_speed, expected)
  assert_eq(by_pitch, expected)
}

///|
test "half speed interpolates between samples, and a negative speed plays backwards" {
  let store = sample_test_store()
  let waveform = sample_test_waveform(4, index => [1.0, 0.5, -0.5, 0.25][index])
  assert_eq(store.register(1, waveform, root_pitch=60.0), None)
  let slow = sample_test_play(
    @dsp.SamplePlayer(store),
    8,
    number=1.0,
    speed=0.5,
  )
  assert_eq(slow, [1.0, 0.75, 0.5, 0.0, -0.5, -0.125, 0.25, 0.0])
  let backwards = sample_test_play(
    @dsp.SamplePlayer(store),
    5,
    number=1.0,
    speed=-1.0,
  )
  assert_eq(backwards, [0.25, -0.5, 0.5, 1.0, 0.0])
}

///|
test "begin and end play a slice forwards and backwards; an empty slice is silent" {
  let store = sample_test_store()
  // Values 1 to 8, so each played value names its waveform sample.
  let waveform = sample_test_waveform(8, index => (index + 1).to_double())
  assert_eq(store.register(0, waveform, root_pitch=60.0), None)
  let play = (begin, end, speed) => {
    sample_test_play(@dsp.SamplePlayer(store), 6, speed~, begin~, end~)
  }
  // 0.25 × 8 = 2 and 0.75 × 8 = 6: samples 2 to 5.
  assert_eq(play(0.25, 0.75, 1.0), [3.0, 4.0, 5.0, 6.0, 0.0, 0.0])
  assert_eq(play(0.25, 0.75, -1.0), [6.0, 5.0, 4.0, 3.0, 0.0, 0.0])
  // 0.3 × 8 = 2.4 starts at sample 3; 0.6 × 8 = 4.8 ends before sample 5.
  assert_eq(play(0.3, 0.6, 1.0), [4.0, 5.0, 0.0, 0.0, 0.0, 0.0])
  // Out-of-range fractions clamp to the waveform.
  assert_eq(play(-1.0, 0.25, 1.0), [1.0, 2.0, 0.0, 0.0, 0.0, 0.0])
  assert_eq(play(0.875, 2.0, -1.0), [8.0, 0.0, 0.0, 0.0, 0.0, 0.0])
  for slice in [(0.5, 0.5), (0.75, 0.25)] {
    assert_eq(play(slice.0, slice.1, 1.0), [0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
    assert_eq(play(slice.0, slice.1, -1.0), [0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
  }
}

///|
test "a slice bound within rounding error of a whole sample lands on it" {
  let store = @dsp.SampleStore(entries=1, max_length=100, capacity=100)
  let waveform = sample_test_waveform(100, index => (index + 1).to_double())
  assert_eq(store.register(0, waveform, root_pitch=60.0), None)
  // 0.07 × 100 is 7.000000000000001 in doubles; the slice is samples 7 to 9.
  let played = sample_test_play(
    @dsp.SamplePlayer(store),
    4,
    begin=0.07,
    end=0.1,
  )
  assert_eq(played, [8.0, 9.0, 10.0, 0.0])
  // A fraction genuinely between samples still starts at the next one.
  let between = sample_test_play(
    @dsp.SamplePlayer(store),
    2,
    begin=0.0705,
    end=0.09,
  )
  assert_eq(between, [9.0, 0.0])
}

///|
test "begin and end are fixed at onset; reset reads them again" {
  let store = sample_test_store()
  let waveform = sample_test_waveform(8, index => (index + 1).to_double())
  assert_eq(store.register(0, waveform, root_pitch=60.0), None)
  let player = @dsp.SamplePlayer(store)
  let head = sample_test_play(player, 4, begin=0.5)
  // A later begin and end do not move the sounding voice.
  let tail = sample_test_play(player, 4, begin=0.0, end=0.25)
  assert_eq([..head, ..tail], [5.0, 6.0, 7.0, 8.0, 0.0, 0.0, 0.0, 0.0])
  player.reset()
  assert_eq(sample_test_play(player, 4, begin=0.0, end=0.25), [
    1.0, 2.0, 0.0, 0.0,
  ])
}

///|
test "a sample number with no waveform plays silence" {
  let store = sample_test_store()
  assert_eq(
    store.register(0, sample_test_waveform(4, _ => 1.0), root_pitch=60.0),
    None,
  )
  // Unregistered, fractional, negative, past the entries, and a context's
  // default store.
  for number in [3.0, 0.5, -1.0, 4.0] {
    let played = sample_test_play(@dsp.SamplePlayer(store), 4, number~)
    assert_eq(played, [0.0, 0.0, 0.0, 0.0])
  }
  let default_store = @dsp.DspContext(sample_rate=48000.0, block_size=4).samples()
  assert_eq(default_store.entries(), 0)
  let played = sample_test_play(@dsp.SamplePlayer(default_store), 4)
  assert_eq(played, [0.0, 0.0, 0.0, 0.0])
}

///|
test "a sounding player keeps its waveform when the store replaces it" {
  let store = sample_test_store()
  let first = sample_test_waveform(8, index => (index + 1).to_double() / 8.0)
  let second = sample_test_waveform(8, index => -(index + 1).to_double() / 8.0)
  assert_eq(store.register(0, first, root_pitch=60.0), None)
  let sounding = @dsp.SamplePlayer(store)
  let head = sample_test_play(sounding, 4)
  assert_eq(store.register(0, second, root_pitch=60.0), None)
  let tail = sample_test_play(sounding, 4)
  assert_eq([..head, ..tail], sample_test_doubles(first, 8))
  let fresh = sample_test_play(@dsp.SamplePlayer(store), 4)
  assert_eq(fresh, sample_test_doubles(second, 4))
}

///|
test "reset forgets the waveform and the read position" {
  let store = sample_test_store()
  let first = sample_test_waveform(8, index => (index + 1).to_double() / 8.0)
  let second = sample_test_waveform(8, index => -(index + 1).to_double() / 8.0)
  assert_eq(store.register(0, first, root_pitch=60.0), None)
  let player = @dsp.SamplePlayer(store)
  ignore(sample_test_play(player, 4))
  assert_eq(store.register(0, second, root_pitch=60.0), None)
  player.reset()
  let played = sample_test_play(player, 4)
  assert_eq(played, sample_test_doubles(second, 4))
}

///|
test "a registration over a limit fails and leaves the store unchanged" {
  let store = @dsp.SampleStore(entries=2, max_length=4, capacity=6)
  let four = sample_test_waveform(4, _ => 0.5)
  assert_eq(
    store.register(2, four, root_pitch=60.0),
    Some(@dsp.SampleLimit::Entries),
  )
  assert_eq(
    store.register(-1, four, root_pitch=60.0),
    Some(@dsp.SampleLimit::Entries),
  )
  assert_eq(
    store.register(0, sample_test_waveform(5, _ => 0.5), root_pitch=60.0),
    Some(@dsp.SampleLimit::Length),
  )
  assert_eq(store.register(0, four, root_pitch=60.0), None)
  // Four of six samples are used, so a second waveform of four does not fit.
  assert_eq(
    store.register(1, four, root_pitch=60.0),
    Some(@dsp.SampleLimit::Memory),
  )
  assert_true(store.has(0))
  assert_true(!store.has(1))
  assert_eq(sample_test_play(@dsp.SamplePlayer(store), 4), [0.5, 0.5, 0.5, 0.5])
  assert_eq(
    store.register(1, sample_test_waveform(2, _ => 0.25), root_pitch=60.0),
    None,
  )
  assert_eq(sample_test_play(@dsp.SamplePlayer(store), 2, number=1.0), [
    0.25, 0.25,
  ])
}

///|
test "a chunked registration is invisible until commit, and a new begin reuses its memory" {
  let store = @dsp.SampleStore(entries=2, max_length=4, capacity=4)
  assert_eq(store.begin(0, 4, root_pitch=60.0), None)
  store.write(0, 1.0)
  store.write(1, Float::from_double(0.0 / 0.0))
  assert_true(!store.has(0))
  assert_eq(sample_test_play(@dsp.SamplePlayer(store), 2), [0.0, 0.0])
  // Abandoning the pending waveform frees its four samples.
  assert_eq(store.begin(1, 4, root_pitch=60.0), None)
  for offset in 0..<4 {
    store.write(offset, 0.5)
  }
  store.write(4, 9.0)
  assert_true(store.commit())
  assert_true(!store.commit())
  assert_true(!store.has(0))
  assert_eq(sample_test_play(@dsp.SamplePlayer(store), 5, number=1.0), [
    0.5, 0.5, 0.5, 0.5, 0.0,
  ])
}
