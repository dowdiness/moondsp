///|
pub(all) suberror StableIdError {
  EmptyId
  InvalidId(String)
} derive(Eq, Debug)

///|
pub struct Revision {
  priv value : Int64
  priv fingerprint : Int64
} derive(Eq, Debug)

///|
pub fn Revision::zero() -> Revision {
  { value: 0L, fingerprint: 0L }
}

///|
pub fn Revision::next(self : Revision) -> Revision {
  let modulus = 2147483629L
  let multiplier = 131071L
  {
    value: self.value + 1L,
    fingerprint: (self.fingerprint % modulus * multiplier + 1L) % modulus,
  }
}

///|
pub fn Revision::max(self : Revision, other : Revision) -> Revision {
  if self.value > other.value {
    self
  } else if self.value < other.value {
    other
  } else if self.fingerprint >= other.fingerprint {
    self
  } else {
    other
  }
}

///|
pub fn Revision::combine(self : Revision, other : Revision) -> Revision {
  let modulus = 2147483647L
  let multiplier = 65537L
  let fingerprint_modulus = 2147483629L
  let fingerprint_multiplier = 131071L
  {
    value: (self.value % modulus * multiplier + other.value % modulus) % modulus,
    fingerprint: (
      self.fingerprint % fingerprint_modulus * fingerprint_multiplier +
      other.fingerprint % fingerprint_modulus +
      1L
    ) %
    fingerprint_modulus,
  }
}

///|
pub fn Revision::value(self : Revision) -> Int64 {
  self.value
}

///|
fn valid_id_code(code : Int) -> Bool {
  (code >= 'a'.to_int() && code <= 'z'.to_int()) ||
  (code >= 'A'.to_int() && code <= 'Z'.to_int()) ||
  (code >= '0'.to_int() && code <= '9'.to_int()) ||
  code == '_'.to_int() ||
  code == '-'.to_int() ||
  code == '.'.to_int() ||
  code == ':'.to_int()
}

///|
fn validate_id_value(value : String) -> String raise StableIdError {
  guard value.length() > 0 else { raise EmptyId }
  for index in 0..<value.length() {
    guard valid_id_code(value[index].to_int()) else { raise InvalidId(value) }
  }
  value
}

///|
pub struct PatternNodeId(String) derive(Eq, Debug)

///|
pub fn PatternNodeId::from_string(
  value : String,
) -> PatternNodeId raise StableIdError {
  PatternNodeId(validate_id_value(value))
}

///|
pub fn PatternNodeId::value(self : PatternNodeId) -> String {
  self.0
}

///|
pub struct SectionId(String) derive(Eq, Debug)

///|
pub fn SectionId::from_string(value : String) -> SectionId raise StableIdError {
  SectionId(validate_id_value(value))
}

///|
pub fn SectionId::value(self : SectionId) -> String {
  self.0
}

///|
pub struct SectionLayerId(String) derive(Eq, Debug)

///|
pub fn SectionLayerId::from_string(
  value : String,
) -> SectionLayerId raise StableIdError {
  SectionLayerId(validate_id_value(value))
}

///|
pub fn SectionLayerId::value(self : SectionLayerId) -> String {
  self.0
}

///|
pub struct OccurrenceId(String) derive(Eq, Debug)

///|
pub fn OccurrenceId::from_string(
  value : String,
) -> OccurrenceId raise StableIdError {
  OccurrenceId(validate_id_value(value))
}

///|
pub fn OccurrenceId::value(self : OccurrenceId) -> String {
  self.0
}

///|
pub struct GraphNodeId(String) derive(Eq, Debug)

///|
pub fn GraphNodeId::from_string(
  value : String,
) -> GraphNodeId raise StableIdError {
  GraphNodeId(validate_id_value(value))
}

///|
pub fn GraphNodeId::value(self : GraphNodeId) -> String {
  self.0
}
