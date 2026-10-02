///|
fn allocation_bench_snapshot(dense : Bool) -> PlaybackSnapshot raise {
  let note = @pattern.PatternDoc::from_pattern(
    id=@identity.PatternNodeId::from_string("bench-notes"),
    pat=@pattern.sequence([
      @pattern.note(60.0),
      @pattern.note(64.0),
      @pattern.note(67.0),
    ]),
  )
  if !dense {
    return PlaybackSnapshot::pattern(note.lower())
  }
  let motif = note.fast(
    id=@identity.PatternNodeId::from_string("bench-fast"),
    factor=@pattern.Rational::from_int(16),
  )
  let slower = @pattern.PatternDoc::reference(
    id=@identity.PatternNodeId::from_string("bench-slow-reference"),
    definition=motif,
  ).slow(
    id=@identity.PatternNodeId::from_string("bench-slow"),
    factor=@pattern.Rational::from_int(2),
  )
  let phrase = @pattern.PatternDoc::stack(
    id=@identity.PatternNodeId::from_string("bench-phrase"),
    docs=[
      @pattern.PatternDoc::reference(
        id=@identity.PatternNodeId::from_string("bench-fast-reference"),
        definition=motif,
      ),
      slower,
    ],
  )
  let third = @pattern.PatternDoc::reference(
    id=@identity.PatternNodeId::from_string("bench-third-reference"),
    definition=phrase,
  ).slow(
    id=@identity.PatternNodeId::from_string("bench-third"),
    factor=@pattern.Rational::from_int(3),
  )
  let chord = @pattern.PatternDoc::from_pattern(
    id=@identity.PatternNodeId::from_string("bench-chord"),
    pat=@pattern.stack([
      @pattern.note(60.0),
      @pattern.note(64.0),
      @pattern.note(67.0),
    ]),
  ).fast(
    id=@identity.PatternNodeId::from_string("bench-chord-fast"),
    factor=@pattern.Rational::from_int(16),
  )
  PlaybackSnapshot::pattern(
    @pattern.PatternDoc::stack(
      id=@identity.PatternNodeId::from_string("bench-root"),
      docs=[
        @pattern.PatternDoc::reference(
          id=@identity.PatternNodeId::from_string("bench-phrase-reference"),
          definition=phrase,
        ),
        third,
        chord,
      ],
    ).lower(),
  )
}

///|
test "bench/playback/sourced-query" (b : @bench.T) {
  let arcs = Array::makei(600, index => {
    @pattern.TimeSpan::new(
      @pattern.Rational::new(Int64::from_int(index * 128), 96000L),
      @pattern.Rational::new(Int64::from_int((index + 1) * 128), 96000L),
    )
  })
  for dense in [false, true] {
    let state = PlaybackState()
    state.queue(allocation_bench_snapshot(dense))
    state.commit_pending(@pattern.Rational::from_int(0))
    b.bench(name=if dense { "dense_600_arcs" } else { "sparse_600_arcs" }, fn() {
      // Querying does not mutate the owner; no admission or arc creation here.
      for arc in arcs {
        b.keep(state.query_active_sourced_events(arc))
      }
    })
  }
}
