///|
/// What an entry plays and what it knows about where its events came from. It
/// is built once, where the kind of material is known, so the entry's own
/// operations have no per-kind branches.
priv struct EntryContent {
  /// The entry's body and content when the material entered `delay` after its
  /// origin (ADR-0025); `None` when entering changes nothing.
  entered : (@pattern.Rational) -> (
    @pattern.Pat[@score.ScoreEvent],
    EntryContent,
  )?
  /// The entry's events over `arc`, each with its tracked source if it has one.
  query_sourced : (EntrySpec, @pattern.Rational, @pattern.TimeSpan) -> Array[
    PlaybackSourcedEvent,
  ]
}

///|
fn untracked_pattern_content(
  snapshot : @pattern.UntrackedPatternSnapshot[@score.ScoreEvent],
  index : Int32,
) -> EntryContent {
  {
    entered: delay => {
      let snapshot = snapshot.entered(delay)
      Some(
        (
          snapshot.pat().entries()[index],
          untracked_pattern_content(snapshot, index),
        ),
      )
    },
    query_sourced: (_, origin, arc) => {
      let placement = @pattern.Placement(origin~)
      snapshot
      .query_sourced_events_for_entry(index, arc)
      .map(event => {
        event: event.event().placed(placement),
        origin: @model.VoiceOrigin::Pattern(event.pattern_node_path()),
        source: None,
        controls: event.controls().on_playback_clock(origin),
      })
    },
  }
}

///|
fn tracked_pattern_content(
  snapshot : @pattern.TrackedPatternSnapshot[@score.ScoreEvent],
  index : Int32,
) -> EntryContent {
  {
    entered: delay => {
      let snapshot = snapshot.entered(delay)
      Some(
        (
          snapshot.pat().entries()[index],
          tracked_pattern_content(snapshot, index),
        ),
      )
    },
    query_sourced: (_, origin, arc) => {
      let placement = @pattern.Placement(origin~)
      snapshot
      .query_for_entry(index, arc)
      .map(event => {
        event: event.event().placed(placement),
        origin: @model.VoiceOrigin::Pattern(event.pattern_node_path()),
        source: Some(event),
        controls: event.controls().on_playback_clock(origin),
      })
    },
  }
}

///|
/// A song occurrence keeps its one-shot signals on its section's clock, so
/// entering changes nothing.
fn untracked_song_content(song_origin : @song.SongEventOrigin) -> EntryContent {
  {
    entered: _ => None,
    query_sourced: (spec, origin, arc) => {
      query_entry(spec, origin, arc).map(event => {
        event,
        origin: @model.VoiceOrigin::Song(song_origin),
        source: None,
        controls: @pattern.Controls::fixed(event.value.controls),
      })
    },
  }
}

///|
fn tracked_song_content(
  entry : @song.SongEntry[@pattern.TrackedPatternSnapshot[@score.ScoreEvent]],
) -> EntryContent {
  {
    entered: _ => None,
    query_sourced: (spec, origin, arc) => {
      let source_arc = @pattern.TimeSpan(
        arc.begin + spec.start,
        arc.end_ + spec.start,
      )
      guard entry.slice(source_arc) is Some(slice) else { return [] }
      let placement = @pattern.Placement(origin=origin - spec.start)
      slice
      .content()
      .query_for_entry(slice.entry(), slice.arc())
      .map(event => {
        event: event.event().placed(slice.placement()).placed(placement),
        origin: @model.VoiceOrigin::Song(slice.origin()),
        source: Some(event),
        controls: event
        .controls()
        .placed(slice.placement())
        .on_playback_clock(origin - spec.start),
      })
    },
  }
}

///|
/// The source is bound when preparing the material, never paired during playback.
priv struct EntrySpec {
  id : String
  body : @pattern.Pat[@score.ScoreEvent]
  start : @pattern.Rational
  end_ : @pattern.Rational?
  source : EntryContent
  /// How long after its origin the material entered; its one-shot signals
  /// start there (ADR-0025).
  delay : @pattern.Rational
}

///|
fn EntrySpec::EntrySpec(
  id~ : String,
  body~ : @pattern.Pat[@score.ScoreEvent],
  start~ : @pattern.Rational,
  end_~ : @pattern.Rational?,
  source~ : EntryContent,
) -> EntrySpec {
  { id, body, start, end_, source, delay: @pattern.Rational::from_int(0), }
}

///|
/// This material entered `delay` after its origin: its one-shot signals
/// start at its entry (ADR-0025). A song occurrence keeps them on its
/// section's clock.
fn EntrySpec::entered(self : EntrySpec, delay : @pattern.Rational) -> EntrySpec {
  guard delay.num != 0L else { return self }
  match (self.source.entered)(delay) {
    Some((body, source)) => { ..self, body, source, delay, }
    None => self
  }
}

///|
/// `replacement` placed for its boundary `due`, entering there.
fn entering(
  current : EntrySpec,
  origin : @pattern.Rational,
  replacement : EntrySpec,
  due : @pattern.Rational,
) -> (EntrySpec, @pattern.Rational) {
  let origin = replacement_origin(current, origin, replacement, due)
  (replacement.entered(due - origin), origin)
}

///|
/// A transition always carries the material that is currently audible (when
/// there is one) and a boundary that has already been proven safe.
priv enum EntryEdit {
  Replace(EntrySpec, @pattern.Rational)
}

///|
fn EntryEdit::due(self : EntryEdit) -> @pattern.Rational {
  match self {
    Replace(_, due) => due
  }
}

///|
priv enum DeferredEdit {
  Replace(EntrySpec)
  Remove
}

///|
fn deferred_edit(spec : EntrySpec?) -> DeferredEdit {
  match spec {
    Some(spec) => Replace(spec)
    None => Remove
  }
}

///|
/// Exclusive runtime states. Entering has no current material: it is a
/// reservation for a future boundary. Switching and stopping retain the
/// actual current material until their proven boundary.
priv enum EntryState {
  Entering(EntrySpec, @pattern.Rational, @pattern.Rational)
  Current(EntrySpec, @pattern.Rational)
  Switching(EntrySpec, @pattern.Rational, EntryEdit)
  Stopping(EntrySpec, @pattern.Rational, @pattern.Rational)
  Retained(EntrySpec, @pattern.Rational, DeferredEdit)
  Finishing(EntrySpec, @pattern.Rational, @pattern.Rational, EntrySpec)
  Skipped(EntrySpec)
}

///|
fn EntryState::material(self : EntryState) -> EntrySpec {
  match self {
    Entering(material, _, _)
    | Current(material, _)
    | Switching(material, _, _)
    | Stopping(material, _, _)
    | Retained(material, _, _)
    | Finishing(material, _, _, _)
    | Skipped(material) => material
  }
}

///|
fn PlaybackSnapshot::entries(self : PlaybackSnapshot) -> Array[EntrySpec] {
  match self {
    UntrackedPattern(snapshot) =>
      pattern_entry_specs(snapshot.pat(), index => {
        untracked_pattern_content(snapshot, index)
      })
    TrackedPattern(snapshot) =>
      pattern_entry_specs(snapshot.pat(), index => {
        tracked_pattern_content(snapshot, index)
      })
    Song(Untracked(snapshot)) | RepeatSong(Untracked(snapshot)) =>
      song_entry_specs(snapshot, entry => untracked_song_content(entry.origin()))
    Song(Tracked(snapshot)) | RepeatSong(Tracked(snapshot)) =>
      song_entry_specs(snapshot, entry => tracked_song_content(entry))
  }
}

///|
/// One spec per canonical entry of a pattern, in `Pat::entries` order.
fn pattern_entry_specs(
  pat : @pattern.Pat[@score.ScoreEvent],
  content : (Int32) -> EntryContent,
) -> Array[EntrySpec] {
  let result : Array[EntrySpec] = []
  for index, body in pat.entries() {
    result.push(
      EntrySpec(
        id=body.entry_key(),
        body~,
        start=@pattern.Rational::from_int(0),
        end_=None,
        source=content(index),
      ),
    )
  }
  result
}

///|
/// One spec per canonical song entry, in the snapshot's entry order.
fn[C] song_entry_specs(
  snapshot : @song.SongSnapshot[C],
  source : (@song.SongEntry[C]) -> EntryContent,
) -> Array[EntrySpec] {
  snapshot
  .entries()
  .map(entry => {
    // Layer identity, not stack position, keys an entry within its occurrence.
    let occurrence = entry.origin().occurrence().value()
    let layer = entry.origin().layer().value()
    EntrySpec(
      id="\{occurrence.length()}:\{occurrence}/\{layer.length()}:\{layer}/" +
        entry.body().entry_key(),
      body=entry.body(),
      start=entry.start(),
      end_=Some(entry.end_()),
      source=source(entry),
    )
  })
}

///|
fn next_unbounded_entry(
  material : EntrySpec,
  origin : @pattern.Rational,
  now : @pattern.Rational,
) -> @pattern.Rational {
  guard now > material.start else { return material.start }
  let period = material.body.entry_period()
  let relative = (now - origin) / period
  let floor = relative.floor()
  let cycle = if relative == @pattern.Rational(floor, 1L) {
    floor
  } else {
    floor + 1L
  }
  origin + period * @pattern.Rational(cycle, 1L)
}

///|
fn next_entry(
  material : EntrySpec,
  origin : @pattern.Rational,
  now : @pattern.Rational,
) -> @pattern.Rational? {
  let due = next_unbounded_entry(material, origin, now)
  match material.end_ {
    Some(end_) if due >= end_ => None
    _ => Some(due)
  }
}

///|
fn same_entry(left : EntrySpec, right : EntrySpec) -> Bool {
  left.start == right.start &&
  left.end_ == right.end_ &&
  left.body.same_content(right.body)
}

///|
fn idle_entry(material : EntrySpec, spec : EntrySpec) -> Bool {
  guard material.start == spec.start && material.end_ == spec.end_ else {
    return false
  }
  let idle : @pattern.Pat[@score.ScoreEvent] = @pattern.Pat::silence().slow(
    material.body.entry_period(),
  )
  idle.same_content(spec.body)
}

///|
fn EntryState::retain_if_same(
  self : EntryState,
  spec : EntrySpec,
) -> EntryState? {
  match self {
    Current(material, origin)
    | Switching(material, origin, _)
    | Stopping(material, origin, _)
    | Retained(material, origin, _) =>
      if same_entry(material, spec) {
        Some(Current(spec.entered(material.delay), origin))
      } else {
        None
      }
    Entering(material, origin, due) =>
      if idle_entry(material, spec) {
        None
      } else if material.start == spec.start && material.end_ == spec.end_ {
        let (spec, origin) = entering(material, origin, spec, due)
        Some(Entering(spec, origin, due))
      } else {
        None
      }
    Finishing(current, origin, due, skipped) =>
      if same_entry(skipped, spec) {
        Some(Finishing(current, origin, due, spec))
      } else if same_entry(current, spec) {
        Some(Current(spec.entered(current.delay), origin))
      } else {
        None
      }
    Skipped(material) =>
      if same_entry(material, spec) {
        Some(Skipped(spec))
      } else {
        None
      }
  }
}

///|
/// Preserve a proven exit only when it cannot enter a moved finite occurrence
/// after that occurrence's authored start.
fn plan_change(
  current : EntrySpec,
  origin : @pattern.Rational,
  due : @pattern.Rational,
  replacement : EntrySpec?,
) -> EntryState {
  match replacement {
    None => Stopping(current, origin, due)
    Some(spec) =>
      if spec.end_ is Some(_) && spec.start != current.start && spec.start < due {
        Finishing(current, origin, due, spec)
      } else {
        Switching(
          current,
          origin,
          Replace(entering(current, origin, spec, due).0, due),
        )
      }
  }
}

///|
/// Parse a prepared entry and the current transport position into exactly one
/// eligible runtime state. A finite occurrence already in progress cannot be
/// represented as Entering and therefore cannot later join midway.
fn entry_for_update(spec : EntrySpec, now : @pattern.Rational) -> EntryState {
  match spec.end_ {
    Some(end_) if now >= end_ => Skipped(spec)
    Some(_) if now > spec.start => Skipped(spec)
    Some(_) => Entering(spec, spec.start, spec.start)
    None => {
      let due = next_unbounded_entry(spec, spec.start, now)
      Entering(spec.entered(due - spec.start), spec.start, due)
    }
  }
}

///|
fn PlaybackSnapshot::start_entries(
  self : PlaybackSnapshot,
) -> Array[EntryState] {
  self.entries().map(spec => Current(spec, spec.start))
}

///|
/// Each target keeps at most one current and one boundary-proven replacement.
/// Later edits replace the payload while retaining the proven boundary.
fn PlaybackSnapshot::reconcile_entries(
  self : PlaybackSnapshot,
  current : Array[EntryState],
  now : @pattern.Rational,
) -> Array[EntryState] {
  let next = self.entries()
  let remaining : Map[String, EntrySpec] = Map([])
  for spec in next {
    remaining[spec.id] = spec
  }
  let result : Array[EntryState] = []
  for entry in current {
    let material = entry.material()
    let replacement = remaining.get(material.id)
    remaining.remove(material.id)
    if replacement is Some(spec) && entry.retain_if_same(spec) is Some(retained) {
      result.push(retained)
      continue
    }
    match entry {
      Skipped(_) =>
        if replacement is Some(spec) {
          result.push(entry_for_update(spec, now))
        }
      Current(material, origin) | Retained(material, origin, _) =>
        match next_entry(material, origin, now) {
          Some(due) =>
            result.push(plan_change(material, origin, due, replacement))
          None =>
            result.push(Retained(material, origin, deferred_edit(replacement)))
        }
      Entering(material, origin, due) =>
        match replacement {
          Some(spec) if idle_entry(material, spec) => ()
          Some(spec) if spec.start != material.start ||
            spec.end_ != material.end_ =>
            result.push(entry_for_update(spec, now))
          Some(spec) => {
            let (spec, origin) = entering(material, origin, spec, due)
            result.push(Entering(spec, origin, due))
          }
          None => ()
        }
      Switching(material, origin, edit) =>
        result.push(plan_change(material, origin, edit.due(), replacement))
      Stopping(material, origin, due) =>
        result.push(plan_change(material, origin, due, replacement))
      Finishing(material, origin, due, _) =>
        result.push(plan_change(material, origin, due, replacement))
    }
  }
  for spec in next {
    guard remaining.contains(spec.id) else { continue }
    result.push(entry_for_update(spec, now))
  }
  result
}

///|
fn replacement_origin(
  current : EntrySpec,
  origin : @pattern.Rational,
  replacement : EntrySpec,
  due : @pattern.Rational,
) -> @pattern.Rational {
  if replacement.start != current.start {
    replacement.start
  } else if replacement.body.entry_period() != current.body.entry_period() {
    due
  } else {
    origin
  }
}

///|
fn settle_edit(
  current : EntrySpec,
  origin : @pattern.Rational,
  edit : EntryEdit,
  now : @pattern.Rational,
  otherwise : EntryState,
) -> EntryState? {
  guard edit.due() <= now else { return Some(otherwise) }
  match edit {
    Replace(spec, due) =>
      if spec.end_ is Some(end_) && end_ <= now {
        None
      } else {
        Some(Current(spec, replacement_origin(current, origin, spec, due)))
      }
  }
}

///|
fn settle_entries(
  entries : Array[EntryState],
  now : @pattern.Rational,
) -> Array[EntryState] {
  entries.filter_map(entry => {
    match entry {
      Skipped(_) => Some(entry)
      Current(material, _) if material.end_ is Some(end_) && end_ <= now => None
      Current(_, _) => Some(entry)
      Retained(material, _, edit) =>
        if material.end_ is Some(end_) && end_ <= now {
          match edit {
            Replace(spec) => Some(Skipped(spec))
            Remove => None
          }
        } else {
          Some(entry)
        }
      Entering(material, origin, due) =>
        if material.end_ is Some(end_) && end_ <= now {
          Some(Skipped(material))
        } else if due <= now {
          Some(Current(material, origin))
        } else {
          Some(entry)
        }
      Switching(material, origin, edit) =>
        settle_edit(material, origin, edit, now, entry)
      Stopping(material, _, due) =>
        if due <= now || (material.end_ is Some(end_) && end_ <= now) {
          None
        } else {
          Some(entry)
        }
      Finishing(_, _, due, skipped) =>
        if due <= now {
          Some(Skipped(skipped))
        } else {
          Some(entry)
        }
    }
  })
}

///|
fn EntryState::has_pending(self : EntryState) -> Bool {
  match self {
    Entering(_, _, _)
    | Switching(_, _, _)
    | Stopping(_, _, _)
    | Finishing(_, _, _, _) => true
    Current(_, _) | Retained(_, _, _) | Skipped(_) => false
  }
}

///|
fn EntryState::is_skipped(self : EntryState) -> Bool {
  self is Skipped(_) ||
  self is Finishing(_, _, _, _) ||
  self is Retained(_, _, Replace(_))
}

///|
/// Both query paths consume entry-local arcs and return events on the playback clock.
fn query_entry(
  spec : EntrySpec,
  origin : @pattern.Rational,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@score.ScoreEvent]] {
  spec.body.query(arc).map(event => event.shift(origin))
}

///|
fn EntrySpec::query_sourced(
  self : EntrySpec,
  origin : @pattern.Rational,
  arc : @pattern.TimeSpan,
) -> Array[PlaybackSourcedEvent] {
  (self.source.query_sourced)(self, origin, arc)
}

///|
fn query_entries(
  entries : Array[EntryState],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@score.ScoreEvent]] {
  query_entry_segments(entries, arc, query_entry)
}

///|
fn query_sourced_entries(
  entries : Array[EntryState],
  arc : @pattern.TimeSpan,
) -> Array[PlaybackSourcedEvent] {
  query_entry_segments(entries, arc, EntrySpec::query_sourced)
}

///|
fn[A] append_entry_segment(
  result : Array[A],
  spec : EntrySpec,
  origin : @pattern.Rational,
  arc : @pattern.TimeSpan,
  query : (EntrySpec, @pattern.Rational, @pattern.TimeSpan) -> Array[A],
) -> Unit {
  let begin = if arc.begin < spec.start { spec.start } else { arc.begin }
  let end_ = match spec.end_ {
    Some(end_) if end_ < arc.end_ => end_
    _ => arc.end_
  }
  guard begin < end_ else { return }
  let local_arc = @pattern.TimeSpan(begin - origin, end_ - origin)
  result.append(query(spec, origin, local_arc))
}

///|
fn[A] append_replacement_segment(
  result : Array[A],
  current : EntrySpec,
  origin : @pattern.Rational,
  edit : EntryEdit,
  arc : @pattern.TimeSpan,
  query : (EntrySpec, @pattern.Rational, @pattern.TimeSpan) -> Array[A],
) -> Unit {
  let due = edit.due()
  guard due < arc.end_ else { return }
  if edit is Replace(spec, _) {
    append_entry_segment(
      result,
      spec,
      replacement_origin(current, origin, spec, due),
      @pattern.TimeSpan(if due > arc.begin { due } else { arc.begin }, arc.end_),
      query,
    )
  }
}

///|
/// Split proven transition boundaries once for both query paths, without
/// allocating segment arrays. Skipped occurrences have no query behavior.
fn[A] query_entry_segments(
  entries : Array[EntryState],
  arc : @pattern.TimeSpan,
  query : (EntrySpec, @pattern.Rational, @pattern.TimeSpan) -> Array[A],
) -> Array[A] {
  let result : Array[A] = []
  for entry in entries {
    match entry {
      Current(material, origin) | Retained(material, origin, _) =>
        append_entry_segment(result, material, origin, arc, query)
      Entering(material, origin, due) =>
        if due < arc.end_ {
          append_entry_segment(
            result,
            material,
            origin,
            @pattern.TimeSpan(
              if due > arc.begin {
                due
              } else {
                arc.begin
              },
              arc.end_,
            ),
            query,
          )
        }
      Switching(material, origin, edit) => {
        let due = edit.due()
        if due < arc.end_ {
          if due > arc.begin {
            append_entry_segment(
              result,
              material,
              origin,
              @pattern.TimeSpan(arc.begin, due),
              query,
            )
          }
          append_replacement_segment(result, material, origin, edit, arc, query)
        } else {
          append_entry_segment(result, material, origin, arc, query)
        }
      }
      Stopping(material, origin, due) =>
        if due > arc.begin {
          append_entry_segment(
            result,
            material,
            origin,
            @pattern.TimeSpan(
              arc.begin,
              if due < arc.end_ {
                due
              } else {
                arc.end_
              },
            ),
            query,
          )
        }
      Finishing(material, origin, due, _) =>
        if due > arc.begin {
          append_entry_segment(
            result,
            material,
            origin,
            @pattern.TimeSpan(
              arc.begin,
              if due < arc.end_ {
                due
              } else {
                arc.end_
              },
            ),
            query,
          )
        }
      Skipped(_) => ()
    }
  }
  result
}
