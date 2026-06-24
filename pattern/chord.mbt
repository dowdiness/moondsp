///|
/// Chord quality definitions and MIDI note mapping for chord names.
///
/// Supports standard chord notation:
///   C, Dm, G7, F#m7, Bb, Cmaj7, Am, Esus4, Cdim, Caug, Dm7b5, etc.
///
/// Each chord name is parsed into a root MIDI note + quality intervals,
/// producing an array of MIDI note numbers for use with `note()`.

///|
/// Chord quality intervals in semitones from root.
priv struct ChordQuality {
  intervals : Array[Int]
}

///|
let major : ChordQuality = { intervals: [0, 4, 7] }

///|
let minor : ChordQuality = { intervals: [0, 3, 7] }

///|
let dim : ChordQuality = { intervals: [0, 3, 6] }

///|
let aug : ChordQuality = { intervals: [0, 4, 8] }

///|
let dom7 : ChordQuality = { intervals: [0, 4, 7, 10] }

///|
let maj7 : ChordQuality = { intervals: [0, 4, 7, 11] }

///|
let min7 : ChordQuality = { intervals: [0, 3, 7, 10] }

///|
let dim7 : ChordQuality = { intervals: [0, 3, 6, 9] }

///|
let half_dim7 : ChordQuality = { intervals: [0, 3, 6, 10] }

///|
let min_maj7 : ChordQuality = { intervals: [0, 3, 7, 11] }

///|
let sus2 : ChordQuality = { intervals: [0, 2, 7] }

///|
let sus4 : ChordQuality = { intervals: [0, 5, 7] }

///|
let sixth : ChordQuality = { intervals: [0, 4, 7, 9] }

///|
let min6 : ChordQuality = { intervals: [0, 3, 7, 9] }

///|
let nine : ChordQuality = { intervals: [0, 4, 7, 10, 14] }

///|
let maj9 : ChordQuality = { intervals: [0, 4, 7, 11, 14] }

///|
let min9 : ChordQuality = { intervals: [0, 3, 7, 10, 14] }

///|
let add9 : ChordQuality = { intervals: [0, 4, 7, 14] }

///|
let seven_sus4 : ChordQuality = { intervals: [0, 5, 7, 10] }

///|
let aug7 : ChordQuality = { intervals: [0, 4, 8, 10] }

///|
/// Quality keys sorted by length descending for longest-prefix matching.
let quality_keys : Array[String] = [
  "m7b5", "mMaj7", "mM7", "7sus4", "maj7", "min7", "dim7", "aug7", "sus4", "sus2",
  "add9", "maj9", "min9", "M9", "M7", "m7", "m9", "m6", "dim", "aug", "min", "+7",
  "ø7", "m", "7", "9", "6", "+", "ø",
]

///|
/// Quality map from key string to chord interval array.
let quality_map : Map[String, ChordQuality] = {
  "maj7": maj7,
  "M7": maj7,
  "min7": min7,
  "dim7": dim7,
  "dim": dim,
  "aug7": aug7,
  "aug": aug,
  "+7": aug7,
  "+": aug,
  "m7b5": half_dim7,
  "ø7": half_dim7,
  "ø": half_dim7,
  "mMaj7": min_maj7,
  "mM7": min_maj7,
  "maj9": maj9,
  "M9": maj9,
  "min9": min9,
  "m7": min7,
  "m9": min9,
  "7sus4": seven_sus4,
  "sus4": sus4,
  "sus2": sus2,
  "add9": add9,
  "m6": min6,
  "6": sixth,
  "7": dom7,
  "9": nine,
  "m": minor,
  "min": minor,
}

///|
/// Parse root note letter (A-G, case insensitive) to semitone offset from C.
fn parse_root_note(letter : UInt16) -> Int? {
  match letter {
    'c' | 'C' => Some(0)
    'd' | 'D' => Some(2)
    'e' | 'E' => Some(4)
    'f' | 'F' => Some(5)
    'g' | 'G' => Some(7)
    'a' | 'A' => Some(9)
    'b' | 'B' => Some(11)
    _ => None
  }
}

///|
/// Try to parse a one-digit chord octave suffix.
fn parse_octave_digits(s : String) -> Int? {
  if s.length() != 1 {
    return None
  }
  let mut oct = 0
  for i in 0..<s.length() {
    let c = s[i]
    if c >= '0' && c <= '9' {
      oct = oct * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None // non-digit in octave string
    }
  }
  Some(oct)
}

///|
/// Try to match a quality from the beginning of string `s`.
/// Returns (quality, remaining_suffix) or None.
/// Only matches if the quality key is a prefix of `s`.
fn match_quality(s : String) -> (ChordQuality, String)? {
  for key in quality_keys {
    let klen = key.length()
    if klen <= s.length() && s[:klen].to_owned() == key {
      let remaining = s[klen:].to_owned()
      // Remaining must be empty or parseable as an octave number
      if remaining.is_empty() || parse_octave_digits(remaining) is Some(_) {
        match quality_map.get(key) {
          Some(q) => return Some((q, remaining))
          None => ()
        }
      }
    }
  }
  None
}

///|
/// Parsed chord components.
priv struct ChordParts {
  accidental : Int
  quality : ChordQuality
  octave : Int
}

///|
/// After parsing the root note at position 0, try to parse the rest of the
/// name as an accidental followed by a quality suffix and optional octave.
/// Supports both standard (#/b) and alternate (s/f) accidental notation.
fn parse_accidental_then_quality(
  name : String,
  start_pos : Int,
  len : Int,
  default_octave : Int,
) -> ChordParts? {
  if start_pos >= len {
    return None
  }
  let c = name[start_pos]
  // Only proceed if it looks like an accidental
  let is_std = c == '#' || c == 'b'
  let is_alt = c == 's' || c == 'f'
  if !is_std && !is_alt {
    return None
  }

  let mut accidental = if c == '#' || c == 's' { 1 } else { -1 }
  let mut new_pos = start_pos + 1

  // Double accidental?
  if new_pos < len {
    let d = name[new_pos]
    if d == '#' || d == 's' {
      accidental = accidental + 1
      new_pos += 1
    } else if d == 'b' || d == 'f' {
      accidental = accidental - 1
      new_pos += 1
    }
  }

  // Now parse quality and optional octave from the rest
  let rest = name[new_pos:].to_owned()
  if rest.is_empty() {
    // Just root + accidental, no quality → major triad
    return Some({ accidental, quality: major, octave: default_octave })
  }

  match match_quality(rest) {
    Some((quality, remaining)) => {
      let octave = match parse_octave_digits(remaining) {
        Some(oct) => oct
        None => default_octave
      }
      return Some({ accidental, quality, octave })
    }
    None =>
      // Not a recognized quality — try to parse rest as octave number
      match parse_octave_digits(rest) {
        Some(oct) => return Some({ accidental, quality: major, octave: oct })
        None => return None
      }
  }
}

///|
/// Parse a chord name and return the MIDI note numbers (as Int).
///
/// Format: `<root><accidental?><quality?><octave?>`
/// - root: A-G (case insensitive)
/// - accidental: `#` or `b` (or `s`/`f` for sharp/flat)
/// - quality: `m`, `min`, `dim`, `aug`, `+`, `maj7`, `M7`, `7`, etc.
/// - octave: integer 0-9 (default 4)
///
/// Quality is matched with longest-prefix semantics on the suffix
/// AFTER any accidental. Quality-only names like "Esus4" are matched
/// directly without accidental parsing (the 's' starts "sus4", not a sharp).
///
/// Returns `None` if the chord name cannot be parsed.
pub fn parse_chord(name : String) -> Array[Int]? {
  parse_chord_with_default_octave(name, 4)
}

///|
fn parse_chord_with_default_octave(
  name : String,
  default_octave : Int,
) -> Array[Int]? {
  let len = name.length()
  if len < 1 {
    return None
  }

  // Parse root note letter
  let root_semitone = match parse_root_note(name[0]) {
    Some(s) => s
    None => return None
  }

  if len == 1 {
    // Just a root letter → major triad at default octave
    let root_midi = (default_octave + 1) * 12 + root_semitone
    return Some(major.intervals.map(fn(i) { root_midi + i }))
  }

  // Strategy: try quality matching on the entire suffix first.
  // This handles "Esus4", "Am", "C7", "Gdim", "C6", etc.
  // where there's no explicit accidental.
  let suffix = name[1:].to_owned()
  match match_quality(suffix) {
    Some((quality, remaining)) => {
      let octave = match parse_octave_digits(remaining) {
        Some(oct) => oct
        None => default_octave
      }
      let root_midi = (octave + 1) * 12 + root_semitone
      return Some(quality.intervals.map(fn(i) { root_midi + i }))
    }
    None => ()
  }

  // No quality matched on the raw suffix.
  // Try parsing accidental then quality (for "F#m7", "Bb", "C#", etc.)
  match parse_accidental_then_quality(name, 1, len, default_octave) {
    Some(parts) => {
      let root_midi = (parts.octave + 1) * 12 + root_semitone + parts.accidental
      return Some(parts.quality.intervals.map(fn(i) { root_midi + i }))
    }
    None => ()
  }

  // Last resort: try to parse the whole suffix as an octave number
  // (for names like "C5" = C major in octave 5)
  match parse_octave_digits(suffix) {
    Some(octave) => {
      let root_midi = (octave + 1) * 12 + root_semitone
      Some(major.intervals.map(fn(i) { root_midi + i }))
    }
    None => None
  }
}

///|
/// Create a pattern from a chord name. The chord is expanded into a stack
/// of note events, one per chord tone, all at the same time position.
///
/// Octave defaults to 4 (middle C octave).
///
/// Examples:
///   chord("C")    → C major: [C4, E4, G4]  = [60, 64, 67]
///   chord("Dm")   → D minor: [D4, F4, A4]  = [62, 65, 69]
///   chord("G7")   → G dominant 7th: [G4, B4, D5, F5] = [67, 71, 74, 77]
///   chord("F#m7") → F# minor 7th: [F#4, A4, C#5, E5] = [66, 69, 73, 76]
///
/// Returns silence pattern for unrecognized chord names.
pub fn chord(name : String, octave? : Int = 4) -> Pat[ControlMap] {
  match parse_chord_with_default_octave(name, octave) {
    Some(notes) => chord_pat_from_notes(notes)
    None => Pat::silence()
  }
}

///|
/// Internal: create a stacked pattern from MIDI note numbers.
fn chord_pat_from_notes(notes : Array[Int]) -> Pat[ControlMap] {
  stack(notes.map(fn(midi) { note(midi.to_double()) }))
}

///|
/// Parse a note name (e.g., "C4", "F#3", "Bb5", "Eb") into a MIDI note number.
/// The octave defaults to 4 (middle C) if not specified.
/// Returns `None` if the name cannot be parsed.
///
/// Examples:
///   note_name_to_midi("C4")  → Some(60.0)
///   note_name_to_midi("F#3") → Some(54.0)
///   note_name_to_midi("Bb5") → Some(82.0)
///   note_name_to_midi("C")   → Some(60.0)  (default octave 4)
///   note_name_to_midi("X")   → None
pub fn note_name_to_midi(name : String) -> Double? {
  if name.is_empty() {
    return None
  }
  let len = name.length()
  // Parse root letter
  let base_semitone = match parse_root_note(name[0]) {
    Some(s) => s
    None => return None
  }
  if len == 1 {
    // Just a root letter → default octave 4
    return Some(((4 + 1) * 12 + base_semitone).to_double())
  }
  let mut pos = 1
  let mut modifier = 0
  // Parse accidental (#, s, b, f)
  if pos < len {
    match name[pos] {
      '#' | 's' => {
        modifier = 1
        pos += 1
      }
      'b' | 'f' => {
        modifier = -1
        pos += 1
      }
      _ => ()
    }
  }
  // Double accidental?
  if pos < len {
    match name[pos] {
      '#' | 's' => {
        modifier = modifier + 1
        pos += 1
      }
      'b' | 'f' => {
        modifier = modifier - 1
        pos += 1
      }
      _ => ()
    }
  }
  // Parse octave
  let mut octave = 4 // default octave
  let mut negative = false
  if pos < len && name[pos] == '-' {
    negative = true
    pos += 1
  }
  let mut has_digits = false
  let mut oct = 0
  while pos < len {
    let c = name[pos]
    if c >= '0' && c <= '9' {
      oct = oct * 10 + (c.to_int() - '0'.to_int())
      has_digits = true
    } else {
      return None
    }
    pos += 1
  }
  if negative && !has_digits {
    return None
  }
  if has_digits {
    octave = if negative { -oct } else { oct }
  }
  let midi = ((octave + 1) * 12 + base_semitone + modifier).to_double()
  Some(midi)
}

///|
/// Parse a chord name with an explicit octave override, returning
/// the MIDI note numbers as `Double` for use in `ControlMap`.
///
/// Returns `None` if the chord name is unrecognized.
pub fn chord_notes(name : String, octave? : Int = 4) -> Array[Double]? {
  match parse_chord_with_default_octave(name, octave) {
    Some(notes) => Some(notes.map(fn(n) { n.to_double() }))
    None => None
  }
}
