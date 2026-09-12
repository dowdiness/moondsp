///|
priv enum EntrySource {
  Pattern(@pattern.PatternSnapshot[@pattern.ControlMap], Int)
  Song(@song.SongSnapshot[@pattern.ControlMap], Int)
}

///|
/// The source is bound when preparing the material, never paired during playback.
priv struct EntrySpec {
  id : String
  body : @pattern.Pat[@pattern.ControlMap]
  start : @pattern.Rational
  end_ : @pattern.Rational?
  source : EntrySource
}

///|
fn EntrySpec::EntrySpec(
  id~ : String,
  body~ : @pattern.Pat[@pattern.ControlMap],
  start~ : @pattern.Rational,
  end_~ : @pattern.Rational?,
  source~ : EntrySource,
) -> EntrySpec {
  { id, body, start, end_, source, }
}

///|
priv enum EntryEdit {
  Replace(EntrySpec, @pattern.Rational?)
  Remove(@pattern.Rational?)
}

///|
fn EntryEdit::due(self : EntryEdit) -> @pattern.Rational? {
  match self {
    Replace(_, due) | Remove(due) => due
  }
}

///|
priv enum EntryPhase {
  Playing
  Waiting(EntryEdit)
  Changing(EntryEdit)
}

///|
/// While waiting, material is only the original timing anchor, not audible input.
priv struct EntryState {
  material : EntrySpec
  origin : @pattern.Rational
  phase : EntryPhase
}

///|
fn EntryState::EntryState(
  material : EntrySpec,
  origin : @pattern.Rational,
  phase : EntryPhase,
) -> EntryState {
  { material, origin, phase, }
}

///|
fn PlaybackSnapshot::entries(self : PlaybackSnapshot) -> Array[EntrySpec] {
  match self {
    Pattern(snapshot) => {
      let result : Array[EntrySpec] = []
      for index, body in snapshot.pat().entries() {
        result.push(
          EntrySpec(
            id=body.entry_key(),
            body~,
            start=@pattern.Rational::from_int(0),
            end_=None,
            source=Pattern(snapshot, index),
          ),
        )
      }
      result
    }
    Song(snapshot) => {
      let result : Array[EntrySpec] = []
      let mut index = 0
      for occurrence in snapshot.song().occurrences() {
        let bodies = occurrence
          .section()
          .body()
          .fast(occurrence.section().scope().rate())
          .entries()
        for body in bodies {
          result.push(
            EntrySpec(
              id="\{occurrence.id().value().length()}:\{occurrence.id().value()}/" +
                body.entry_key(),
              body~,
              start=occurrence.start(),
              end_=Some(occurrence.end_()),
              source=Song(snapshot, index),
            ),
          )
          index += 1
        }
      }
      result
    }
  }
}

///|
fn next_entry(
  material : EntrySpec,
  origin : @pattern.Rational,
  now : @pattern.Rational,
) -> @pattern.Rational? {
  guard now > material.start else { return Some(material.start) }
  let period = material.body.entry_period()
  let relative = (now - origin) / period
  let floor = relative.floor()
  let cycle = if relative == @pattern.Rational::new(floor, 1L) {
    floor
  } else {
    floor + 1L
  }
  let due = origin + period * @pattern.Rational::new(cycle, 1L)
  match material.end_ {
    Some(end_) if due >= end_ => None
    _ => Some(due)
  }
}

///|
fn EntryState::retains_content(self : EntryState, spec : EntrySpec) -> Bool {
  guard self.material.start == spec.start && self.material.end_ == spec.end_ else {
    return false
  }
  match self.phase {
    Waiting(_) => {
      // Silence reverts the idle interval and cancels its reservation. This
      // canonical value is only compared, never installed as playback state.
      let idle : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence().slow(
        self.material.body.entry_period(),
      )
      idle.same_content(spec.body)
    }
    _ => self.material.body.same_content(spec.body)
  }
}

///|
fn PlaybackSnapshot::start_entries(
  self : PlaybackSnapshot,
) -> Array[EntryState] {
  self.entries().map(spec => EntryState(spec, spec.start, Playing))
}

///|
/// Each target keeps at most one active and one pending version. Later edits
/// replace the payload but retain the original reservation, including no boundary.
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
    let replacement = remaining.get(entry.material.id)
    remaining.remove(entry.material.id)
    if replacement is Some(spec) && entry.retains_content(spec) {
      let retained = if entry.phase is Waiting(_) {
        spec
      } else {
        entry.material
      }
      result.push(EntryState(retained, entry.origin, Playing))
      continue
    }
    let due = match entry.phase {
      Playing => next_entry(entry.material, entry.origin, now)
      Waiting(edit) | Changing(edit) => edit.due()
    }
    let edit = match replacement {
      Some(spec) => EntryEdit::Replace(spec, due)
      None => EntryEdit::Remove(due)
    }
    let phase = match entry.phase {
      Waiting(_) => EntryPhase::Waiting(edit)
      _ => EntryPhase::Changing(edit)
    }
    result.push(EntryState(entry.material, entry.origin, phase))
  }
  for spec in next {
    guard remaining.contains(spec.id) else { continue }
    guard !(spec.end_ is Some(end_) && end_ <= now) else { continue }
    result.push(
      EntryState(
        spec,
        spec.start,
        Waiting(Replace(spec, next_entry(spec, spec.start, now))),
      ),
    )
  }
  result
}

///|
fn settle_entries(
  entries : Array[EntryState],
  now : @pattern.Rational,
) -> Array[EntryState] {
  entries.filter_map(entry => {
    guard !(entry.material.end_ is Some(end_) && end_ <= now) else {
      return None
    }
    match entry.phase {
      Waiting(edit) | Changing(edit) => {
        guard edit.due() is Some(due) && due <= now else { return Some(entry) }
        match edit {
          Replace(spec, _) =>
            Some(
              EntryState(spec, replacement_origin(entry, spec, due), Playing),
            )
          Remove(_) => None
        }
      }
      Playing => Some(entry)
    }
  })
}

///|
fn EntryState::has_pending(self : EntryState) -> Bool {
  !(self.phase is Playing)
}

///|
fn replacement_origin(
  entry : EntryState,
  spec : EntrySpec,
  due : @pattern.Rational,
) -> @pattern.Rational {
  if spec.start != entry.material.start {
    spec.start
  } else if spec.body.entry_period() != entry.material.body.entry_period() {
    due
  } else {
    entry.origin
  }
}

///|
/// Both query paths consume entry-local arcs and return events on the playback clock.
fn query_entry(
  spec : EntrySpec,
  origin : @pattern.Rational,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  spec.body.query(arc).map(event => event.shift(origin))
}

///|
fn EntrySpec::query_sourced(
  self : EntrySpec,
  origin : @pattern.Rational,
  arc : @pattern.TimeSpan,
) -> Array[PlaybackSourcedEvent] {
  match self.source {
    Pattern(snapshot, index) =>
      snapshot
      .query_sourced_events_for_entry(index, arc)
      .map(event => {
        event: event.event().shift(origin),
        origin: @model.VoiceOrigin::Pattern(event.pattern_node_path()),
      })
    Song(snapshot, index) => {
      let source_arc = @pattern.TimeSpan::new(
        arc.begin + self.start,
        arc.end_ + self.start,
      )
      let delta = origin - self.start
      snapshot
      .query_sourced_events_for_entry(index, source_arc)
      .map(event => {
        event: event.event().shift(delta),
        origin: @model.VoiceOrigin::Song(event.origin()),
      })
    }
  }
}

///|
fn query_entries(
  entries : Array[EntryState],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
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
  let local_arc = @pattern.TimeSpan::new(begin - origin, end_ - origin)
  result.append(query(spec, origin, local_arc))
}

///|
/// Split reservations once for both query paths, without allocating segment arrays.
fn[A] query_entry_segments(
  entries : Array[EntryState],
  arc : @pattern.TimeSpan,
  query : (EntrySpec, @pattern.Rational, @pattern.TimeSpan) -> Array[A],
) -> Array[A] {
  let result : Array[A] = []
  for entry in entries {
    match entry.phase {
      Playing =>
        append_entry_segment(result, entry.material, entry.origin, arc, query)
      Waiting(edit) | Changing(edit) =>
        if edit.due() is Some(due) && due < arc.end_ {
          if entry.phase is Changing(_) && due > arc.begin {
            append_entry_segment(
              result,
              entry.material,
              entry.origin,
              @pattern.TimeSpan::new(arc.begin, due),
              query,
            )
          }
          if edit is Replace(spec, _) {
            append_entry_segment(
              result,
              spec,
              replacement_origin(entry, spec, due),
              @pattern.TimeSpan::new(
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
        } else if entry.phase is Changing(_) {
          append_entry_segment(result, entry.material, entry.origin, arc, query)
        }
    }
  }
  result
}
