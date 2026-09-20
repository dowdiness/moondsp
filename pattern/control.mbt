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
pub fn s_lpf(frequency_hz : Double, resonance? : Double) -> Pat[ControlMap] {
  let cutoff = control("lpf", frequency_hz)
  match resonance {
    None => cutoff
    Some(q) => merge_control(cutoff, control("lpf_resonance", q))
  }
}

///|
pub fn s_hpf(frequency_hz : Double, resonance? : Double) -> Pat[ControlMap] {
  let cutoff = control("hpf", frequency_hz)
  match resonance {
    None => cutoff
    Some(q) => merge_control(cutoff, control("hpf_resonance", q))
  }
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
  jux_kernel(self, f, (value, pan) => merge_maps(value, pan), signature)
}

///|
fn[A] jux_kernel(
  pat : Pat[A],
  f : (Pat[A]) -> Pat[A],
  merge : (A, ControlMap) -> A,
  signature : String,
) -> Pat[A] {
  if signature != "" && pat.body is Silence {
    return pat
  }
  let left = merge_control_kernel(pat, s_pan(-1.0), merge)
  let right = merge_control_kernel(f(pat), s_pan(1.0), merge)
  let combined = stack([left, right])
  make_pat(
    combined.query,
    pat.metadata.period,
    Opaque([]),
    pat.metadata.scope,
    transformed_signature(
      pat.entry_signature(),
      if signature == "" {
        ""
      } else {
        "jux:" + signature
      },
    ),
  )
}

///|
fn merge_maps(a : ControlMap, b : ControlMap) -> ControlMap {
  a.merge(b)
}

///|
/// Merge overlapping right-hand payloads into each left-hand event.
fn[A, B] merge_control_kernel(
  a : Pat[A],
  b : Pat[B],
  merge : (A, B) -> A,
) -> Pat[A] {
  if a.body is Silence {
    return a
  }
  let left = a
  let children = a.transform_children(p => merge_control_kernel(p, b, merge))
  let change = if b.entry_signature() == "" {
    ""
  } else {
    "merge:" + b.entry_signature()
  }
  make_pat(
    fn(arc) {
      let b_events = b.query(arc)
      left
      .query(arc)
      .map(ae => {
        let merged = b_events.fold(init=ae.value, (merged, be) => {
          if ae.part.intersect(be.part) is Some(_) {
            merge(merged, be.value)
          } else {
            merged
          }
        })
        { whole: ae.whole, part: ae.part, value: merged, }
      })
    },
    a.metadata.period,
    Opaque(children),
    a.metadata.scope,
    transformed_signature(a.entry_signature(), change),
  )
}

///|
/// Merge controls: for each event in pattern a, merge all overlapping b events.
pub fn merge_control(
  a : Pat[ControlMap],
  b : Pat[ControlMap],
) -> Pat[ControlMap] {
  merge_control_kernel(a, b, merge_maps)
}

///|
/// A scalar control source whose content is tracked automatically.
pub fn control(key : String, value : Double) -> Pat[ControlMap] {
  let pat = Pat::pure(ControlMap::single(key, value))
  make_pat(
    pat.query,
    pat.metadata.period,
    pat.body,
    pat.metadata.scope,
    "control:\{key.length()}:\{key}:\{value}",
  )
}

///|
/// Select events carrying a control; optionally require an exact value.
pub fn Pat::select_control(
  self : Pat[ControlMap],
  key : String,
  value? : Double,
) -> Pat[ControlMap] {
  select_control_kernel(self, cm => cm, key, value)
}

///|
fn[A] select_control_kernel(
  pat : Pat[A],
  controls : (A) -> ControlMap,
  key : String,
  value : Double?,
) -> Pat[A] {
  let condition = match value {
    Some(v) => "equals:\{v}"
    None => "present"
  }
  pat.filter_map_payload(
    payload => {
      match controls(payload).get(key) {
        None => None
        Some(v) =>
          if value is Some(expected) && v != expected {
            None
          } else {
            Some(payload)
          }
      }
    },
    "select:\{key.length()}:\{key}:" + condition,
  )
}

///|
pub extend ControlMap with Debug::{to_repr}

///|
pub extend ControlMap with Show::{to_string, output}
