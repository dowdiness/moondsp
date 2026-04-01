///|
/// Numeric control map — the contract between Pattern and DSP engines.
pub struct ControlMap(Map[String, Double]) derive(Show)

///|
fn single_control(key : String, value : Double) -> ControlMap {
  let m : Map[String, Double] = {}
  m[key] = value
  ControlMap(m)
}

///|
pub fn note(n : Double) -> Pat[ControlMap] {
  Pat::pure(single_control("note", n))
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
  Pat::pure(single_control("cutoff", f))
}

///|
pub fn s_gain(g : Double) -> Pat[ControlMap] {
  Pat::pure(single_control("gain", g))
}

///|
pub fn s_pan(p : Double) -> Pat[ControlMap] {
  Pat::pure(single_control("pan", p))
}

///|
fn merge_maps(a : ControlMap, b : ControlMap) -> ControlMap {
  let result : Map[String, Double] = {}
  a.0.each(fn(k, v) { result[k] = v })
  b.0.each(fn(k, v) { result[k] = v })
  ControlMap(result)
}

///|
/// Merge controls: for each event in pattern a, merge all overlapping b events.
pub fn merge_control(
  a : Pat[ControlMap],
  b : Pat[ControlMap],
) -> Pat[ControlMap] {
  {
    query: fn(arc) {
      let a_events = a.query(arc)
      let b_events = b.query(arc)
      let events : Array[Event[ControlMap]] = []
      for i = 0; i < a_events.length(); i = i + 1 {
        let ae = a_events[i]
        let mut merged = ae.value
        for j = 0; j < b_events.length(); j = j + 1 {
          let be = b_events[j]
          match ae.part.intersect(be.part) {
            Some(_) => merged = merge_maps(merged, be.value)
            None => ()
          }
        }
        events.push({ whole: ae.whole, part: ae.part, value: merged })
      }
      events
    },
  }
}
