///|
/// A control's value at one time, or its absence there (ADR-0020 Decision 3).
/// A single-field type, so it costs no allocation on any backend; its methods
/// are the only code that knows how absence is represented.
struct ControlValue(Double)

///|
let absent : ControlValue = ControlValue(@double.not_a_number)

///|
/// No value.
pub fn ControlValue::absent() -> ControlValue {
  absent
}

///|
/// `value`, or no value where `value` is `NaN`: `NaN` is never a control value.
pub fn ControlValue::of(value : Double) -> ControlValue {
  ControlValue(value)
}

///|
pub fn ControlValue::is_absent(self : ControlValue) -> Bool {
  self.0.is_nan()
}

///|
/// The value, if there is one.
pub fn ControlValue::get(self : ControlValue) -> Double? {
  if self.is_absent() {
    None
  } else {
    Some(self.0)
  }
}

///|
/// The value, or `fallback` where there is none. Allocates nothing, unlike
/// `get`, so the audio thread reads values this way.
pub fn ControlValue::unwrap_or(
  self : ControlValue,
  fallback : Double,
) -> Double {
  if self.is_absent() {
    fallback
  } else {
    self.0
  }
}

///|
/// This value, or `fallback` where this one is absent.
pub fn ControlValue::or_else(
  self : ControlValue,
  fallback : ControlValue,
) -> ControlValue {
  if self.is_absent() {
    fallback
  } else {
    self
  }
}

///|
/// The product where both are present, else whichever is present.
pub fn ControlValue::times(
  self : ControlValue,
  other : ControlValue,
) -> ControlValue {
  if self.is_absent() {
    other
  } else if other.is_absent() {
    self
  } else {
    ControlValue(self.0 * other.0)
  }
}

///|
/// Two absent values are equal; a present value equals only the same value.
pub impl Eq for ControlValue with fn equal(self, other) {
  if self.is_absent() {
    other.is_absent()
  } else {
    self.0 == other.0
  }
}

///|
pub impl Show for ControlValue with fn output(self, logger) {
  match self.get() {
    Some(value) => logger.write_object(value)
    None => logger.write_string("absent")
  }
}

///|
/// A note's controls as a voice reads them (ADR-0020 Decision 4).
pub(open) trait ControlSource {
  /// `key`'s value at the note's onset.
  fn value(Self, Control) -> ControlValue
  /// Visit each key whose value changes while the note sounds, with its
  /// reader at exact time `num / den` (`den > 0`). Reading allocates nothing.
  fn each_varying(Self, (Control, (Int64, Int64) -> ControlValue) -> Unit) -> Unit
}

///|
/// Fixed controls: every key holds its value for the whole note.
pub impl ControlSource for Map[Control, Double] with fn value(self, key) {
  match self.get(key) {
    Some(value) => ControlValue(value)
    None => absent
  }
}

///|
pub impl ControlSource for Map[Control, Double] with fn each_varying(_, _) {
  ()
}
