///|
using @song {
  type Section,
  type SectionBuildError,
  type Song,
  type SongBuildError,
  type SongPart,
}

///|
fn rat(n : Int64, d : Int64) -> @pattern.Rational {
  @pattern.Rational(n, d)
}

///|
fn cycles(n : Int64) -> @pattern.Rational {
  @pattern.Rational(n, 1L)
}

///|
fn span(
  begin : @pattern.Rational,
  end_ : @pattern.Rational,
) -> @pattern.TimeSpan {
  @pattern.TimeSpan(begin, end_)
}

///|
fn oid(value : String) -> @identity.OccurrenceId {
  @identity.OccurrenceId::from_string(value) catch {
    _ => abort("occurrence id creation failed")
  }
}

///|
fn sid(value : String) -> @identity.SectionId {
  @identity.SectionId::from_string(value) catch {
    _ => abort("section id creation failed")
  }
}

///|
fn lid(value : String) -> @identity.SectionLayerId {
  @identity.SectionLayerId::from_string(value) catch {
    _ => abort("layer id creation failed")
  }
}

///|
fn untracked(
  name : String,
  midi : Double,
) -> @pattern.UntrackedPatternSnapshot[@score.ScoreEvent] {
  @pattern.PatternDoc::from_pattern(
    id=@identity.PatternNodeId::from_string(name),
    pat=@score.note(midi),
  ).lower() catch {
    _ => abort("pattern snapshot creation failed")
  }
}

///|
fn tracked(
  name : String,
  midi : Double,
) -> @pattern.TrackedPatternSnapshot[@score.ScoreEvent] {
  @pattern.PatternDoc::atom(
    id=@identity.PatternNodeId::from_string(name),
    source_atom=@identity.SourceAtomId(@identity.SourceEpoch(7000L), 1L),
    value=@score.ScoreEvent(Note(@score.Instrument::default(), pitch=midi)),
    content="note:\{midi}",
  ).lower_tracked() catch {
    _ => abort("pattern lowering failed")
  }
}

///|
/// A one-layer section of `length` cycles.
fn[C] section(
  id : String,
  length : @pattern.Rational,
  content : C,
) -> Section[C] {
  Section(id=sid(id), length_cycles=length, layers=[
    SectionLayer(id=lid("\{id}:main"), content~),
  ]) catch {
    _ => abort("section creation failed")
  }
}

///|
fn[C] at(
  id : String,
  start : @pattern.Rational,
  section : Section[C],
) -> SongPart[C] {
  SongPart::at(id=oid(id), start~, section~) catch {
    _ => abort("part creation failed")
  }
}

///|
fn[C] song(parts : Array[SongPart[C]]) -> Song[C] {
  Song(parts~) catch {
    _ => abort("song creation failed")
  }
}

///|
/// Each occurrence as its id and span, in written order.
fn[C] layout(song : Song[C]) -> Array[(String, @pattern.TimeSpan)] {
  song.occurrences().iter().map(o => (o.id().value(), o.span())).collect()
}

///|
test "parts without a start follow the latest end, in written order" {
  let one = section("one", cycles(1), untracked("one", 60.0))
  let two = section("two", cycles(2), untracked("two", 62.0))
  let laid_out = song([
    SongPart(id=oid("intro"), section=one),
    SongPart(id=oid("verse"), section=two),
    // Overlaps the verse; the next implicit part follows its end, not its start.
    at("pad", rat(1L, 2L), two),
    SongPart(id=oid("outro"), section=one),
  ])
  @debug.assert_eq(layout(laid_out), [
    ("intro", span(cycles(0), cycles(1))),
    ("verse", span(cycles(1), cycles(3))),
    ("pad", span(rat(1L, 2L), rat(5L, 2L))),
    ("outro", span(cycles(3), cycles(4))),
  ])
  @debug.assert_eq(laid_out.duration(), cycles(4))
}

///|
test "an explicit start leaves a gap, and the song lasts to its latest end" {
  let one = section("one", cycles(1), untracked("one", 60.0))
  let laid_out = song([
    SongPart(id=oid("first"), section=one),
    at("late", cycles(5), one),
    at("middle", cycles(3), one),
  ])
  @debug.assert_eq(laid_out.duration(), cycles(6))
  // Earliest first, whatever order the parts were written in; covered time
  // is not a gap.
  @debug.assert_eq(laid_out.gap_spans(), [
    span(cycles(1), cycles(3)),
    span(cycles(4), cycles(5)),
  ])
  let contiguous = song([
    SongPart(id=oid("a"), section=one),
    SongPart(id=oid("b"), section=one),
  ])
  @debug.assert_eq(contiguous.gap_spans(), [])
}

///|
test "a song needs a part, and its parts distinct ids" {
  let one = section("one", cycles(1), untracked("one", 60.0))
  let none : Array[
    SongPart[@pattern.UntrackedPatternSnapshot[@score.ScoreEvent]],
  ] = []
  let empty = try Song(parts=none) catch {
    error => Some(error)
  } noraise {
    _ => None
  }
  @debug.assert_eq(empty, Some(SongBuildError::EmptySong))
  let repeated = try
    Song(parts=[
      SongPart(id=oid("same"), section=one),
      at("same", cycles(4), one),
    ])
  catch {
    error => Some(error)
  } noraise {
    _ => None
  }
  @debug.assert_eq(repeated, Some(SongBuildError::DuplicateOccurrence("same")))
}

///|
test "a part cannot start before the song begins" {
  let one = section("one", cycles(1), untracked("one", 60.0))
  let refused = try
    SongPart::at(id=oid("early"), start=rat(-1L, 2L), section=one)
  catch {
    NegativeStart => true
  } noraise {
    _ => false
  }
  assert_true(refused)
  // The song's beginning is a valid start.
  @debug.assert_eq(song([at("first", cycles(0), one)]).duration(), cycles(1))
}

///|
test "a section lasts, plays at a positive rate, and has distinct layers" {
  let build = (
    length : @pattern.Rational,
    rate : @pattern.Rational,
    layers : Array[String],
  ) => {
    try
      Section(
        id=sid("checked"),
        length_cycles=length,
        rate~,
        layers=layers.map(id => {
          SectionLayer(id=lid(id), content=untracked(id, 60.0))
        }),
      )
    catch {
      error => Some(error)
    } noraise {
      _ => None
    }
  }
  @debug.assert_eq(
    build(cycles(0), cycles(1), ["main"]),
    Some(SectionBuildError::NonPositiveLength),
  )
  @debug.assert_eq(
    build(cycles(1), rat(-1L, 2L), ["main"]),
    Some(SectionBuildError::NonPositiveRate),
  )
  @debug.assert_eq(
    build(cycles(1), cycles(1), []),
    Some(SectionBuildError::EmptyLayers),
  )
  @debug.assert_eq(
    build(cycles(1), cycles(1), ["lead", "lead"]),
    Some(SectionBuildError::DuplicateLayer("lead")),
  )
  @debug.assert_eq(build(rat(1L, 2L), rat(1L, 3L), ["lead", "pad"]), None)
}

///|
/// A song event as a consumer sees it: the content's own event placed back on
/// the song clock, tagged with its song origin.
priv struct SongTestEvent {
  origin : @song.SongEventOrigin
  source : @pattern.EventOrigin
  event : @pattern.Event[@score.ScoreEvent]
  controls : @pattern.Controls
}

///|
fn query(
  entries : ArrayView[
    @song.SongEntry[@pattern.TrackedPatternSnapshot[@score.ScoreEvent]],
  ],
  arc : @pattern.TimeSpan,
) -> Array[SongTestEvent] {
  let result : Array[SongTestEvent] = []
  for entry in entries {
    guard span(entry.start(), entry.end_()).intersect(arc) is Some(arc) else {
      continue
    }
    let placement = entry.placement()
    for
      event in entry
      .content()
      .query_for_entry(entry.content_entry(), placement.local_span(arc)) {
      result.push({
        origin: entry.origin(),
        source: event.origin(),
        event: event.event().placed(placement),
        controls: event.controls().placed(placement),
      })
    }
  }
  result
}

///|
test "entries tag each event with its occurrence, section and layer, in layer order" {
  let layered = Section(id=sid("section:layered"), length_cycles=cycles(1), layers=[
    SectionLayer(id=lid("layer:lead"), content=tracked("lead", 60.0)),
    SectionLayer(id=lid("layer:pad"), content=tracked("pad", 67.0)),
  ])
  let events = query(
    song([SongPart(id=oid("occurrence:layered"), section=layered)]).entries(),
    span(cycles(0), rat(1L, 100L)),
  )
  @debug.assert_eq(
    events.map(event => {
      let origin = event.origin
      (
        origin.occurrence().value(),
        origin.section().value(),
        origin.layer().value(),
        event.event.value.sound is Note(_, pitch=60.0),
      )
    }),
    [
      ("occurrence:layered", "section:layered", "layer:lead", true),
      ("occurrence:layered", "section:layered", "layer:pad", false),
    ],
  )
}

///|
test "exact entry origins survive a placed, rated section" {
  let epoch = @identity.SourceEpoch(7001L)
  let c = @identity.SourceAtomId(epoch, 1L)
  let g = @identity.SourceAtomId(epoch, 2L)
  let exact = @pattern.PatternDoc::stack(
    id=@identity.PatternNodeId::from_string("source:stack"),
    docs=[
      @pattern.PatternDoc::atom(
        id=@identity.PatternNodeId::from_string("source:c"),
        source_atom=c,
        value=@score.ScoreEvent(Note(@score.Instrument::default(), pitch=60.0)),
      ),
      @pattern.PatternDoc::atom(
        id=@identity.PatternNodeId::from_string("source:g"),
        source_atom=g,
        value=@score.ScoreEvent(Note(@score.Instrument::default(), pitch=67.0)),
      ),
    ],
  ).lower_tracked()
  let fast = Section(
    id=sid("section:exact"),
    length_cycles=cycles(1),
    rate=cycles(2),
    layers=[SectionLayer(id=lid("layer:exact"), content=exact)],
  )
  let entries = song([at("occurrence:exact", cycles(3), fast)]).entries()
  let arc = span(rat(13L, 4L), rat(15L, 4L))
  for index, atom in [c, g] {
    let events = query(entries[index:index + 1], arc)
    @debug.assert_eq(events.length(), 2)
    for event in events {
      assert_true(event.source.atom() == atom)
      assert_true(
        event.event.value.sound is Note(_, pitch~) &&
        pitch == (if index == 0 { 60.0 } else { 67.0 }),
      )
    }
    @debug.assert_eq(events[0].event.whole, Some(span(cycles(3), rat(7L, 2L))))
    @debug.assert_eq(events[1].event.whole, Some(span(rat(7L, 2L), cycles(4))))
    @debug.assert_eq(events[0].event.part.begin, arc.begin)
    @debug.assert_eq(events[1].event.part.end_, arc.end_)
  }
}

///|
test "song events read their buses on the song clock" {
  let id = (name : String) => {
    @identity.PatternNodeId::from_string("song-bus:" + name) catch {
      _ => abort("bad id")
    }
  }
  let pattern = @pattern.PatternDoc::merge_control(
    id=id("merge"),
    left=@pattern.PatternDoc::atom(
      id=id("note"),
      source_atom=@identity.SourceAtomId(@identity.SourceEpoch(7002L), 1L),
      value=@score.ScoreEvent(Note(@score.Instrument::default(), pitch=60.0)),
    ),
    right=@pattern.PatternDoc::continuous(
      id=id("ramp"),
      key=Lpf,
      f=(t, _) => 100.0 * t,
      signature="100t",
    ),
  ).lower_tracked()
  // Placed at cycle 3 and played twice as fast: local = (t - 3) × 2.
  let fast = Section(
    id=sid("section:bus"),
    length_cycles=cycles(1),
    rate=cycles(2),
    layers=[SectionLayer(id=lid("layer:bus"), content=pattern)],
  )
  let events = query(
    song([at("occurrence:bus", cycles(3), fast)]).entries(),
    span(rat(13L, 4L), rat(7L, 2L)),
  )
  @debug.assert_eq(events.length(), 1)
  let reader = events[0].controls.reader(Lpf).unwrap()
  // (3.25 - 3) × 2 = 0.5 and (3.4 - 3) × 2 = 0.8.
  @debug.assert_eq("\{reader(13L, 4L)} \{reader(17L, 5L)}", "50 80")
  // An entry that starts the song at playback time 1 adds 1, after the rate.
  let entry = @pattern.Placement(origin=cycles(1))
  let placed = events[0].controls.placed(entry).reader(Lpf).unwrap()
  @debug.assert_eq("\{placed(17L, 4L)} \{placed(22L, 5L)}", "50 80")
  @debug.assert_eq(
    events[0].event.placed(entry).part,
    span(rat(17L, 4L), rat(9L, 2L)),
  )
}
