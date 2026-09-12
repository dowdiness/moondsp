///|
priv struct EntrySpec {
  id : String
  body : @pattern.Pat[@pattern.ControlMap]
  start : @pattern.Rational
  end_ : @pattern.Rational?
}

///|
priv struct EntryEdit {
  due : @pattern.Rational?
  replacement : EntrySpec?
}

///|
priv struct EntryState {
  active : EntrySpec
  origin : @pattern.Rational
  edit : EntryEdit?
}

///|
fn PlaybackSnapshot::entries(self : PlaybackSnapshot) -> Array[EntrySpec] {
  match self {
    Pattern(snapshot) =>
      snapshot
      .pat()
      .entries()
      .map(body => {
        id: body.entry_key(),
        body,
        start: @pattern.Rational::from_int(0),
        end_: None,
      })
    Song(snapshot) =>
      snapshot
      .song()
      .occurrences()
      .iter()
      .flat_map(o => {
        o
        .section()
        .body()
        .fast(o.section().scope().rate())
        .entries()
        .map(body => {
          id: "\{o.id().value().length()}:\{o.id().value()}/" + body.entry_key(),
          body,
          start: o.start(),
          end_: Some(o.end_()),
        })
        .iter()
      })
      .collect()
  }
}

///|
fn next_entry(
  entry : EntryState,
  now : @pattern.Rational,
) -> @pattern.Rational? {
  if now <= entry.active.start {
    return Some(entry.active.start)
  }
  let period = entry.active.body.entry_period()
  let relative = (now - entry.origin) / period
  let floor = relative.floor()
  let cycle = if relative == @pattern.Rational::new(floor, 1L) {
    floor
  } else {
    floor + 1L
  }
  let due = entry.origin + period * @pattern.Rational::new(cycle, 1L)
  match entry.active.end_ {
    Some(end_) if due >= end_ => None
    _ => Some(due)
  }
}

///|
fn same_material(a : EntrySpec, b : EntrySpec) -> Bool {
  a.body.same_content(b.body) && a.start == b.start && a.end_ == b.end_
}

///|
// Pure reconciliation: each target retains at most one active and one pending
// version. Later edits replace the payload, never recompute its reservation.
fn reconcile_entries(
  current : Array[EntryState],
  next : Array[EntrySpec],
  now : @pattern.Rational,
) -> Array[EntryState] {
  let remaining : Map[String, EntrySpec] = Map([])
  for spec in next {
    remaining[spec.id] = spec
  }
  let result = []
  for entry in current {
    let replacement = remaining.get(entry.active.id)
    remaining.remove(entry.active.id)
    if replacement is Some(spec) && same_material(entry.active, spec) {
      result.push({ ..entry, edit: None, })
    } else {
      let due = match entry.edit {
        Some(edit) => edit.due
        None => next_entry(entry, now)
      }
      result.push({ ..entry, edit: Some({ due, replacement, }), })
    }
  }
  for spec in next {
    if remaining.contains(spec.id) {
      if spec.end_ is Some(end_) && end_ <= now {
        continue
      }
      let silent = {
        ..spec,
        body: @pattern.Pat::silence().slow(spec.body.entry_period()),
      }
      let entry = EntryState::{ active: spec, origin: spec.start, edit: None, }
      result.push({
        active: silent,
        origin: spec.start,
        edit: Some({ due: next_entry(entry, now), replacement: Some(spec), }),
      })
    }
  }
  result
}

///|
fn settle_entries(
  entries : Array[EntryState],
  now : @pattern.Rational,
) -> Array[EntryState] {
  entries.filter_map(entry => {
    if entry.active.end_ is Some(end_) && end_ <= now {
      return None
    }
    match entry.edit {
      Some({ due: Some(due), replacement, }) if due <= now =>
        replacement.map(spec => {
          active: spec,
          origin: replacement_origin(entry, spec, due),
          edit: None,
        })
      _ => Some(entry)
    }
  })
}

///|
fn query_entry(
  spec : EntrySpec,
  origin : @pattern.Rational,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  let begin = if arc.begin < spec.start { spec.start } else { arc.begin }
  let end_ = match spec.end_ {
    Some(end_) if end_ < arc.end_ => end_
    _ => arc.end_
  }
  if begin >= end_ {
    return []
  }
  let source_arc = @pattern.TimeSpan::new(begin - origin, end_ - origin)
  spec.body.query(source_arc).map(event => event.shift(origin))
}

///|
fn query_entries(
  entries : Array[EntryState],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  entries
  .iter()
  .flat_map(entry => {
    match entry.edit {
      Some({ due: Some(due), replacement, }) if due < arc.end_ => {
        let old = if due > arc.begin {
          query_entry(
            entry.active,
            entry.origin,
            @pattern.TimeSpan::new(arc.begin, due),
          )
        } else {
          []
        }
        let next = match replacement {
          None => []
          Some(spec) => {
            let origin = replacement_origin(entry, spec, due)
            query_entry(
              spec,
              origin,
              @pattern.TimeSpan::new(
                if due > arc.begin {
                  due
                } else {
                  arc.begin
                },
                arc.end_,
              ),
            )
          }
        }
        (old + next).iter()
      }
      _ => query_entry(entry.active, entry.origin, arc).iter()
    }
  })
  .collect()
}

///|
fn replacement_origin(
  entry : EntryState,
  spec : EntrySpec,
  due : @pattern.Rational,
) -> @pattern.Rational {
  if spec.start != entry.active.start {
    spec.start
  } else if spec.body.entry_period() != entry.active.body.entry_period() {
    due
  } else {
    entry.origin
  }
}
