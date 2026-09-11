///|
test "public transformations of identified material reach playback" {
  let source = @pattern.sequence([@pattern.note(60.0), @pattern.note(72.0)]).material()
  let cases = [
    (source.filter_map(_ => None), []),
    (@pattern.merge_control(source, @pattern.note(80.0)), [80, 80]),
    (
      @pattern.merge_control(
        source,
        @pattern.Pat::from_query(@pattern.note(80.0).query),
      ),
      [80, 80],
    ),
    (source.rev(), [72, 60]),
    (source.degrade_by(1.0), []),
    (@pattern.every(1, p => p.rev(), source), [72, 60]),
    (source.jux(p => p.rev()), [60, 72, 72, 60]),
  ]
  for case in cases {
    let (changed, expected) = case
    let state = PlaybackState()
    accept(state, [source], 0)
    accept(state, [changed], 1)
    assert_eq(notes(state, 1, 2), expected)
  }
}
