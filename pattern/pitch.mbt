///|
/// Add semitones to the `note` control without changing event timing or other
/// controls. Events without a note are unchanged.
pub fn Pat::transpose(
  self : Pat[ControlMap],
  semitones : Int,
) -> Pat[ControlMap] {
  if semitones == 0 {
    return self
  }
  self.map_payload(value => {
    match value.get("note") {
      Some(note) => value.set("note", note + semitones.to_double())
      None => value
    }
  })
}

///|
/// Move notes by scale degrees in an explicitly supplied, ascending one-octave
/// MIDI scale. The scale must contain pitches in `[0, 12)`; an empty or invalid
/// scale leaves the pattern unchanged.
pub fn Pat::steps(
  self : Pat[ControlMap],
  scale : Array[Int],
  steps : Int,
) -> Pat[ControlMap] {
  self.steps_by(scale, steps, value => value.get("note"), (value, note) => {
    value.set("note", note)
  })
}

///|
fn[A] Pat::steps_by(
  self : Pat[A],
  scale : Array[Int],
  steps : Int,
  pitch : (A) -> Double?,
  set_pitch : (A, Double) -> A,
) -> Pat[A] {
  guard !scale.is_empty() && steps != 0 else { return self }
  let mut previous = -1
  for pitch in scale {
    guard pitch > previous && pitch < 12 else { return self }
    previous = pitch
  }
  self.map_payload(value => {
    match pitch(value) {
      Some(note) => {
        let midi = note.to_int()
        let octave = midi / 12
        let pitch = midi % 12
        let mut degree = -1
        for i, scale_pitch in scale {
          if scale_pitch <= pitch {
            degree = i
          }
        }
        let mut target_octave = octave
        if degree < 0 {
          degree = scale.length() - 1
          target_octave -= 1
        }
        let mut target_degree = degree + steps
        while target_degree < 0 {
          target_degree += scale.length()
          target_octave -= 1
        }
        while target_degree >= scale.length() {
          target_degree -= scale.length()
          target_octave += 1
        }
        set_pitch(
          value,
          (target_octave * 12 + scale[target_degree]).to_double(),
        )
      }
      None => value
    }
  })
}

///|
/// Keep only the lowest note in each simultaneous chord event group.
/// Timing, entry period, and non-note controls are retained.
pub fn Pat::lowest(self : Pat[ControlMap]) -> Pat[ControlMap] {
  self.lowest_by(value => value.get("note"))
}

///|
fn[A] Pat::lowest_by(self : Pat[A], pitch : (A) -> Double?) -> Pat[A] {
  let inner = self
  // One material keeps the whole-pattern note selection on the playback path.
  let scope = self.metadata.scope.as_material()
  make_pat(
    fn(arc) {
      let events = inner.query(arc)
      events.filter(event => {
        match pitch(event.value) {
          None => true
          Some(note) => {
            let onset = match event.whole {
              Some(whole) => whole.begin
              None => event.part.begin
            }
            !events.any(other => {
              let other_onset = match other.whole {
                Some(whole) => whole.begin
                None => other.part.begin
              }
              other_onset == onset &&
              (match pitch(other.value) {
                Some(other_note) => other_note < note
                None => false
              })
            })
          }
        }
      })
    },
    self.entry_period(),
    Opaque([]),
    scope,
    transformed_signature(self.entry_signature(), "lowest"),
  )
}

///|
fn voicing_pitch(note : Double, low : Int, high : Int) -> Double? {
  let midi = note.to_int()
  let shift = if midi < low {
    (low - midi + 11) / 12
  } else if midi > high {
    -((midi - high + 11) / 12)
  } else {
    0
  }
  let candidate = midi + shift * 12
  if candidate < low || candidate > high {
    None
  } else {
    Some(candidate.to_double() + note - midi.to_double())
  }
}

///|
/// Octave-fold chord tones into the inclusive MIDI range. An omitted `count`
/// retains all tones that fit; an explicit count keeps the lowest tones.
/// A non-positive count or empty range yields silence.
pub fn Pat::voicing(
  self : Pat[ControlMap],
  low : Int,
  high : Int,
  count? : Int = 2147483647,
) -> Pat[ControlMap] {
  self.voicing_by(low, high, count, value => value.get("note"), (value, note) => {
    value.set("note", note)
  })
}

///|
fn[A] Pat::voicing_by(
  self : Pat[A],
  low : Int,
  high : Int,
  count : Int,
  get_pitch : (A) -> Double?,
  set_pitch : (A, Double) -> A,
) -> Pat[A] {
  let inner = self
  let scope = self.metadata.scope.as_material()
  make_pat(
    fn(arc) {
      if count <= 0 || low > high {
        []
      } else {
        let events = inner.query(arc)
        let result : Array[Event[A]] = []
        for event_index in 0..<events.length() {
          let event = events[event_index]
          match get_pitch(event.value) {
            None => result.push(event)
            Some(note) =>
              match voicing_pitch(note, low, high) {
                None => ()
                Some(pitch) => {
                  let onset = match event.whole {
                    Some(whole) => whole.begin
                    None => event.part.begin
                  }
                  let mut rank = 0
                  for other_index in 0..<events.length() {
                    let other = events[other_index]
                    let other_onset = match other.whole {
                      Some(whole) => whole.begin
                      None => other.part.begin
                    }
                    if other_onset == onset {
                      match get_pitch(other.value) {
                        Some(other_note) =>
                          match voicing_pitch(other_note, low, high) {
                            Some(other_pitch) =>
                              if other_pitch < pitch ||
                                (
                                  other_pitch == pitch &&
                                  other_index < event_index
                                ) {
                                rank += 1
                              }
                            None => ()
                          }
                        None => ()
                      }
                    }
                  }
                  if rank < count {
                    result.push({
                      whole: event.whole,
                      part: event.part,
                      value: set_pitch(event.value, pitch),
                    })
                  }
                }
              }
          }
        }
        result
      }
    },
    self.entry_period(),
    Opaque([]),
    scope,
    transformed_signature(
      self.entry_signature(),
      "voicing:\{low}:\{high}:\{count}",
    ),
  )
}

///|
/// Apply an onset mask over this pattern's entry period. The mask repeats
/// evenly across that period; false slots silence all events beginning there.
pub fn[A] Pat::mask(self : Pat[A], mask : Array[Bool]) -> Pat[A] {
  guard !mask.is_empty() else { return Pat::silence() }
  guard mask.any(value => value) else { return Pat::silence() }
  let inner = self
  let period = self.entry_period()
  let children = self.transform_children(child => child.mask(mask))
  let signature = mask.map(value => if value { "1" } else { "0" }).join("")
  make_pat(
    fn(arc) {
      let events = inner.query(arc)
      events.filter(event => {
        let onset = match event.whole {
          Some(whole) => whole.begin
          None => event.part.begin
        }
        let cycle = onset / period
        let phase = onset - period * Rational::new(cycle.floor(), 1L)
        let slot = (phase / period * Rational::from_int(mask.length()))
          .floor()
          .to_int()
        mask[slot % mask.length()]
      })
    },
    period,
    Opaque(children),
    self.metadata.scope,
    transformed_signature(self.entry_signature(), "mask:\{signature}"),
  )
}

///|
/// Replace the final `cycles` portion of each entry period with `replacement`.
/// The replacement is stretched to exactly that duration; the original
/// pattern's entry period remains unchanged. Invalid durations raise.
pub(all) suberror TailError {
  InvalidDuration
} derive(Eq, Debug)

///|
pub extend TailError with Eq::{not_equal, equal}

///|
pub extend TailError with Debug::{to_repr}

///|
pub fn[A] Pat::tail(
  self : Pat[A],
  replacement : Pat[A],
  cycles? : Rational = Rational::from_int(1),
) -> Pat[A] raise TailError {
  let period = self.entry_period()
  guard cycles > Rational::from_int(0) && cycles <= period else {
    raise InvalidDuration
  }
  let inner = self
  let replacement = replacement.slow(cycles / replacement.entry_period())
  make_pat(
    fn(arc) {
      let events : Array[Event[A]] = []
      let mut cycle_start = period *
        Rational::new((arc.begin / period).floor(), 1L)
      while cycle_start < arc.end_ {
        let prefix_end = cycle_start + period - cycles
        let prefix = TimeSpan::new(cycle_start, prefix_end)
        match prefix.intersect(arc) {
          Some(prefix_arc) =>
            events.append(
              inner
              .query(prefix_arc)
              .map(event => {
                let whole = event.whole.map(span => {
                  TimeSpan::new(
                    span.begin,
                    if span.end_ < prefix_end {
                      span.end_
                    } else {
                      prefix_end
                    },
                  )
                })
                { whole, part: event.part, value: event.value, }
              }),
            )
          None => ()
        }
        let tail_start = prefix_end
        let tail_span = TimeSpan::new(tail_start, cycle_start + period)
        match tail_span.intersect(arc) {
          Some(tail_arc) => {
            let local_arc = tail_arc.shift(Rational::from_int(0) - tail_start)
            events.append(
              replacement.query(local_arc).map(event => event.shift(tail_start)),
            )
          }
          None => ()
        }
        cycle_start = cycle_start + period
      }
      events
    },
    period,
    Opaque([]),
    self.metadata.scope,
    transformed_signature(
      self.entry_signature(),
      "tail:\{cycles.num}:\{cycles.den}:\{replacement.entry_signature()}",
    ),
  )
}

///|
/// Transpose notes whose onsets fall within normalized entry phase
/// `[begin, end)` on each repetition. Both boundaries are in `[0, 1]`;
/// events outside the phase range and the entry clock remain unchanged.
pub fn Pat::phase_transpose(
  self : Pat[ControlMap],
  semitones : Int,
  from : Rational,
  to? : Rational = Rational::from_int(1),
) -> Pat[ControlMap] {
  self.phase_transpose_by(semitones, from, to, value => value.get("note"), (
    value,
    note,
  ) => value.set("note", note))
}

///|
fn[A] Pat::phase_transpose_by(
  self : Pat[A],
  semitones : Int,
  from : Rational,
  to : Rational,
  pitch : (A) -> Double?,
  set_pitch : (A, Double) -> A,
) -> Pat[A] {
  let period = self.entry_period()
  let zero = Rational::from_int(0)
  let one = Rational::from_int(1)
  guard from >= zero && from < to && to <= one else { return self }
  guard semitones != 0 else { return self }
  let inner = self
  let children = self.transform_children(child => {
    child.phase_transpose_by(semitones, from, to, pitch, set_pitch)
  })
  make_pat(
    fn(arc) {
      inner
      .query(arc)
      .map(event => {
        let onset = match event.whole {
          Some(whole) => whole.begin
          None => event.part.begin
        }
        let cycle = (onset / period).floor()
        let phase = onset - period * Rational::new(cycle, 1L)
        let phase_fraction = phase / period
        let value = if phase_fraction >= from && phase_fraction < to {
          match pitch(event.value) {
            Some(note) => set_pitch(event.value, note + semitones.to_double())
            None => event.value
          }
        } else {
          event.value
        }
        { whole: event.whole, part: event.part, value, }
      })
    },
    period,
    Opaque(children),
    self.metadata.scope,
    transformed_signature(
      self.entry_signature(),
      "phase_transpose:\{from.num}:\{from.den}:\{to.num}:\{to.den}:\{semitones}",
    ),
  )
}
