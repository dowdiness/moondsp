///|
/// Per-edit Draft cost: what the live editor pays on every committed keystroke.
fn bench_edit_toggle(
  b : @bench.T,
  name : String,
  text : String,
  player_window~ : @pattern.QueryWindow? = None,
) -> Unit {
  let draft = try! Draft(text)
  if player_window is Some(window) {
    ignore(draft.check_playback_within(window))
  }
  let at = text.find("60").unwrap()
  let spellings = ["61", "60"]
  let index = Ref(0)
  b.bench(name~, fn() {
    let edit = TextEdit(from=at, to=at + 2, inserted=spellings[index.val])
    index.val = 1 - index.val
    let result = draft.edit(
      EditTransaction(base=draft.state().version(), edits=[edit]),
    )
    b.keep(result)
  })
}

///|
/// The editor's own sources, from short to heavily shared references.
fn bench_edit_cases() -> Array[(String, String)] {
  [
    ("direct", "note(\"60 62 64 67\")"),
    (
      "default_example", "bpm(96);\n\n$: s(\"bd ~ sd ~ bd bd sd ~\").slow(4)\n$: s(\"hh hh hh hh hh hh hh hh\").slow(4)\n$: note(\"60 ~ 63 67 70 ~ 67 63\").slow(4).gain(0.25).lpf(1800)",
    ),
    (
      "nested_reused", "let motif = note(\"60 62 64 67\"); let phrase = stack(motif, motif.slow(2)); stack(phrase, phrase.slow(3))",
    ),
    (
      "shared_32_paths", "let a = note(\"60\"); let b = stack(a, a); let c = stack(b, b); let d = stack(c, c); let e = stack(d, d); stack(e, e)",
    ),
    (
      "song_4_sections", "song(section(\"a\",4,note(\"60 62 64 67\")),section(\"b\",4,s(\"bd sd hh cp\")),section(\"c\",4,note(\"64 67\").slow(2)),section(\"d\",4,s(\"hh*8\")),part(\"pa\",\"a\"),part(\"pb\",\"b\"),part(\"pc\",\"c\"),part(\"pd\",\"d\"))",
    ),
  ]
}

///|
test "bench/draft/edit" (b : @bench.T) {
  // One 128-frame block at 48 kHz and 1000 BPM (four beats per cycle) spans 1/90 cycle.
  let player_window = @pattern.QueryWindow::from_span(
    @pattern.Rational(1L, 90L),
  )
  for case in bench_edit_cases() {
    bench_edit_toggle(b, "syntax/" + case.0, case.1)
    bench_edit_toggle(b, "player_48k/" + case.0, case.1, player_window~)
  }
}
