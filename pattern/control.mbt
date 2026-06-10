///|
/// Numeric control map — the contract between Pattern and DSP engines.
pub struct ControlMap(Map[String, Double]) derive(Debug)

///|
pub impl Show for ControlMap with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn ControlMap::empty() -> ControlMap {
  ControlMap({})
}

///|
pub fn ControlMap::single(key : String, value : Double) -> ControlMap {
  let m : Map[String, Double] = {}
  m[key] = value
  ControlMap(m)
}

///|
pub fn ControlMap::get(self : ControlMap, key : String) -> Double? {
  self.0.get(key)
}

///|
pub fn ControlMap::each(
  self : ControlMap,
  f : (String, Double) -> Unit,
) -> Unit {
  self.0.each(f)
}

///|
/// Return a fresh map snapshot of this control map.
pub fn ControlMap::entries(self : ControlMap) -> Map[String, Double] {
  let result : Map[String, Double] = {}
  self.0.each(fn(k, v) { result[k] = v })
  result
}

///|
pub fn ControlMap::set(
  self : ControlMap,
  key : String,
  value : Double,
) -> ControlMap {
  let result = self.entries()
  result[key] = value
  ControlMap(result)
}

///|
pub fn ControlMap::merge(self : ControlMap, other : ControlMap) -> ControlMap {
  let result = self.entries()
  other.0.each(fn(k, v) { result[k] = v })
  ControlMap(result)
}

///|
pub fn note(n : Double) -> Pat[ControlMap] {
  Pat::pure(ControlMap::single("note", n))
}

///|
/// Create a sound control pattern from a MIDI drum number.
pub fn sound(midi : Double) -> Pat[ControlMap] {
  Pat::pure(ControlMap::single("sound", midi))
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
  Pat::pure(ControlMap::single("cutoff", f))
}

///|
pub fn s_gain(g : Double) -> Pat[ControlMap] {
  Pat::pure(ControlMap::single("gain", g))
}

///|
pub fn s_pan(p : Double) -> Pat[ControlMap] {
  Pat::pure(ControlMap::single("pan", p))
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
pub fn Pat::jux(
  self : Pat[ControlMap],
  f : (Pat[ControlMap]) -> Pat[ControlMap],
) -> Pat[ControlMap] {
  let left = merge_control(self, s_pan(-1.0))
  let right = merge_control(f(self), s_pan(1.0))
  stack([left, right])
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
        { whole: ae.whole, part: ae.part, value: merged }
      })
    },
  }
}
