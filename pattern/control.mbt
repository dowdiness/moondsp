///|
/// Numeric control map — the contract between Pattern and DSP engines.
/// Values are immutable to callers; entries() returns an owned copy.
pub struct ControlMap {
  priv values : Map[String, Double]
} derive(Debug)

///|
pub impl Show for ControlMap with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn ControlMap::empty() -> ControlMap {
  { values: Map([]), }
}

///|
pub fn ControlMap::single(key : String, value : Double) -> ControlMap {
  let m : Map[String, Double] = Map([])
  m[key] = value
  { values: m, }
}

///|
pub fn ControlMap::get(self : ControlMap, key : String) -> Double? {
  self.values.get(key)
}

///|
pub fn ControlMap::each(
  self : ControlMap,
  f : (String, Double) -> Unit,
) -> Unit {
  self.values.each(f)
}

///|
/// Return a fresh map snapshot of this control map.
pub fn ControlMap::entries(self : ControlMap) -> Map[String, Double] {
  let result : Map[String, Double] = Map([])
  self.values.each(fn(k, v) { result[k] = v })
  result
}

///|
/// Return a new control map with this value replaced; leave self unchanged.
pub fn ControlMap::set(
  self : ControlMap,
  key : String,
  value : Double,
) -> ControlMap {
  let result = self.entries()
  result[key] = value
  { values: result, }
}

///|
/// Return a new control map with the other values overriding self.
pub fn ControlMap::merge(self : ControlMap, other : ControlMap) -> ControlMap {
  let result = self.entries()
  other.values.each(fn(k, v) { result[k] = v })
  { values: result, }
}

///|
pub fn note(n : Double) -> Pat[ControlMap] {
  control("note", n)
}

///|
/// Create a sound control pattern from a MIDI drum number.
pub fn sound(midi : Double) -> Pat[ControlMap] {
  control("sound", midi)
}

///|
pub fn note_name(name : String) -> Pat[ControlMap] {
  note(parse_note_name(name))
}

///|
fn parse_note_name(name : String) -> Double {
  let len = name.length()
  if len < 2 {
    return 0.0
  }
  let letter = name[0]
  let base_semitone = match letter {
    'c' | 'C' => 0
    'd' | 'D' => 2
    'e' | 'E' => 4
    'f' | 'F' => 5
    'g' | 'G' => 7
    'a' | 'A' => 9
    'b' | 'B' => 11
    _ => 0
  }
  let mut offset = 1
  let mut modifier = 0
  if offset < len {
    match name[offset] {
      's' | '#' => {
        modifier = 1
        offset = offset + 1
      }
      'f' =>
        if offset + 1 < len {
          modifier = -1
          offset = offset + 1
        }
      _ => ()
    }
  }
  let mut octave = 0
  let mut negative = false
  if offset < len && name[offset] == '-' {
    negative = true
    offset = offset + 1
  }
  while offset < len {
    let c = name[offset]
    if c >= '0' && c <= '9' {
      octave = octave * 10 + (c.to_int() - '0'.to_int())
    }
    offset = offset + 1
  }
  if negative {
    octave = -octave
  }
  let midi = (octave + 1) * 12 + base_semitone + modifier
  midi.to_double()
}

///|
pub fn s_cutoff(f : Double) -> Pat[ControlMap] {
  control("cutoff", f)
}

///|
pub fn s_gain(g : Double) -> Pat[ControlMap] {
  control("gain", g)
}

///|
pub fn s_pan(p : Double) -> Pat[ControlMap] {
  control("pan", p)
}

///|
/// Strudel-style stereo split. Plays `self` panned hard left and
/// `f(self)` panned hard right, both stacked. Pre-existing `pan`
/// values on the input are overridden by the ±1 outer pan (Strudel-
/// correct: `jux` sets pan unconditionally).
///
/// Doubles per-pool concurrency only when `f` causes same-sound
/// coincidence (e.g. `fast(2)` packs the right channel denser, or
/// `rev` over a single-sound layer like `hh*16` puts left's hh at
/// slot t and right's hh at slot 1-t). For sparse multi-sound
/// patterns like `s("bd sd hh sd").jux(rev)` the per-pool pressure
/// stays at 1.
/// Arbitrary callback content is unknown. Use TimeTransform for known operations.
pub fn Pat::jux(
  self : Pat[ControlMap],
  f : (Pat[ControlMap]) -> Pat[ControlMap],
) -> Pat[ControlMap] {
  self.jux_known(f, "")
}

///|
fn Pat::jux_known(
  self : Pat[ControlMap],
  f : (Pat[ControlMap]) -> Pat[ControlMap],
  signature : String,
) -> Pat[ControlMap] {
  let left = merge_control(self, s_pan(-1.0))
  let right = merge_control(f(self), s_pan(1.0))
  let combined = stack([left, right])
  {
    ..combined,
    period: self.period,
    members: [],
    entry_key: self.entry_key,
    signature: transformed_signature(
      self.entry_signature(),
      if signature == "" {
        ""
      } else {
        "jux:" + signature
      },
    ),
  }
}

///|
fn merge_maps(a : ControlMap, b : ControlMap) -> ControlMap {
  a.merge(b)
}

///|
/// Merge controls: for each event in pattern a, merge all overlapping b events.
pub fn merge_control(
  a : Pat[ControlMap],
  b : Pat[ControlMap],
) -> Pat[ControlMap] {
  {
    period: a.period,
    members: a.members.map(p => merge_control(p, b)),
    entry_key: a.entry_key,
    signature: transformed_signature(
      a.signature,
      if b.entry_signature() == "" {
        ""
      } else {
        "merge:" + b.entry_signature()
      },
    ),
    query: fn(arc) {
      let b_events = b.query(arc)
      a
      .query(arc)
      .map(ae => {
        let merged = b_events.fold(init=ae.value, (merged, be) => {
          if ae.part.intersect(be.part) is Some(_) {
            merge_maps(merged, be.value)
          } else {
            merged
          }
        })
        { whole: ae.whole, part: ae.part, value: merged, }
      })
    },
  }
}

///|
/// A scalar control source whose content is tracked automatically.
pub fn control(key : String, value : Double) -> Pat[ControlMap] {
  let pat = Pat::pure(ControlMap::single(key, value))
  { ..pat, signature: "control:\{key.length()}:\{key}:\{value}", }
}

///|
/// Select events carrying a control; optionally require an exact value.
pub fn Pat::select_control(
  self : Pat[ControlMap],
  key : String,
  value? : Double,
) -> Pat[ControlMap] {
  let condition = match value {
    Some(v) => "equals:\{v}"
    None => "present"
  }
  self.filter_map_known(
    cm => {
      match cm.get(key) {
        None => None
        Some(v) =>
          if value is Some(expected) && v != expected {
            None
          } else {
            Some(cm)
          }
      }
    },
    "select:\{key.length()}:\{key}:" + condition,
  )
}
