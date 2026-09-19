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
    Pattern(snapshot) => {
      let result : Array[EntrySpec] = []
      for index, body in snapshot.pat().entries() {
        result.push(
          EntrySpec(
            id=snapshot.entry_key(index).unwrap(),
            body~,
            start=@pattern.Rational::from_int(0),
            end_=None,
            source=Pattern(snapshot, index),
          ),
        )
      }
      result
    }
    Song(snapshot) | RepeatSong(snapshot) => {
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
fn next_unbounded_entry(
  material : EntrySpec,
  origin : @pattern.Rational,
  now : @pattern.Rational,
) -> @pattern.Rational {
  guard now > material.start else { return material.start }
  let period = material.body.entry_period()
  let relative = (now - origin) / period
  let floor = relative.floor()
  let cycle = if relative == @pattern.Rational::new(floor, 1L) {
    floor
  } else {
    floor + 1L
  }
  origin + period * @pattern.Rational::new(cycle, 1L)
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
  let idle : @pattern.Pat[@pattern.ControlMap] = @pattern.Pat::silence().slow(
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
        Some(Current(spec, origin))
      } else {
        None
      }
    Entering(material, origin, due) =>
      if idle_entry(material, spec) {
        None
      } else if material.start == spec.start && material.end_ == spec.end_ {
        Some(
          Entering(spec, replacement_origin(material, origin, spec, due), due),
        )
      } else {
        None
      }
    Finishing(current, origin, due, skipped) =>
      if same_entry(skipped, spec) {
        Some(Finishing(current, origin, due, spec))
      } else if same_entry(current, spec) {
        Some(Current(spec, origin))
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
        Switching(current, origin, Replace(spec, due))
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
    None =>
      Entering(spec, spec.start, next_unbounded_entry(spec, spec.start, now))
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
          Some(spec) =>
            result.push(
              Entering(
                spec,
                replacement_origin(material, origin, spec, due),
                due,
              ),
            )
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
      Switching(material, origin, edit) => {
        let due = edit.due()
        if due < arc.end_ {
          if due > arc.begin {
            append_entry_segment(
              result,
              material,
              origin,
              @pattern.TimeSpan::new(arc.begin, due),
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
            @pattern.TimeSpan::new(
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
            @pattern.TimeSpan::new(
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
