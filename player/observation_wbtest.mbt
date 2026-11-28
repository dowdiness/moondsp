///|
fn observed_event() -> @pattern.EventWithOrigin[@score.ScoreEvent] raise {
  let atom = @identity.SourceAtomId::SourceAtomId(
    @identity.SourceEpoch::SourceEpoch(11L),
    19L,
  )
  @pattern.PatternDoc::atom(
    id=@identity.PatternNodeId::from_string("onset:atom"),
    source_atom=atom,
    value=@score.ScoreEvent(Note(@score.Instrument::default(), pitch=60.0)),
  )
  .lower_tracked()
  .query(
    @pattern.TimeSpan(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )[0]
}

///|
test "observations keep the newest 256, count what they overwrite, and clear" {
  let onsets = Onsets()
  let signals = SignalValues()
  let observer : &@scheduler.PlaybackObserver = Observations::{
    onsets,
    signals,
  }
  let event = observed_event()
  let signal = event.origin().atom()
  for sample in 0..<=OBSERVATION_CAPACITY {
    observer.onset(sample.to_int64(), event)
    observer.signal(sample.to_int64(), signal, 0.5, sample.to_double())
  }
  observer.signal_lost()
  assert_eq(onsets.count(), 256)
  assert_eq(onsets.dropped(), 1)
  // Oldest first: sample 0 was overwritten.
  assert_eq(onsets.sample(0), 1L)
  assert_eq(onsets.sample(255), 256L)
  assert_true(onsets.source(255).origin().atom() == signal)
  assert_eq(signals.count(), 256)
  assert_eq(signals.dropped(), 2)
  assert_eq(signals.sample(0), 1L)
  assert_eq(signals.value(255), 256.0)
  assert_eq(signals.material(255), 0.5)
  assert_true(signals.signal(255) == signal)
  onsets.clear()
  signals.clear()
  assert_eq((onsets.count(), onsets.dropped()), (0, 0))
  assert_eq((signals.count(), signals.dropped()), (0, 0))
  observer.onset(7L, event)
  assert_eq(onsets.sample(0), 7L)
}
