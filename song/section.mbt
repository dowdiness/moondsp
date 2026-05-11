///|
/// Named long-form region over a pattern body.
///
/// `Section` is polymorphic for the same reason `Pat[A]` is polymorphic:
/// structure, addressing, UI rendering, and future analysis should not be tied
/// to DSP control maps. Scheduler integration specializes this to
/// `Section[ControlMap]`.
pub struct Section[A] {
  priv name : String
  priv length_cycles : @pattern.Rational
  priv scope : TimeScope
  priv body : @pattern.Pat[A]
}

///|
pub fn[A] Section::new(
  name~ : String,
  length_cycles~ : @pattern.Rational,
  scope~ : TimeScope,
  body~ : @pattern.Pat[A],
) -> Section[A]? {
  if length_cycles.num <= 0L {
    None
  } else {
    Some({ name, length_cycles, scope, body })
  }
}

///|
pub fn[A] Section::from_pattern(
  name~ : String,
  body~ : @pattern.Pat[A],
) -> Section[A] {
  match
    Section::new(
      name~,
      length_cycles=@pattern.Rational::from_int(1),
      scope=TimeScope::identity(),
      body~,
    ) {
    Some(section) => section
    None => abort("Section::from_pattern: identity length rejected")
  }
}

///|
pub fn[A] Section::name(self : Section[A]) -> String {
  self.name
}

///|
pub fn[A] Section::length_cycles(self : Section[A]) -> @pattern.Rational {
  self.length_cycles
}

///|
pub fn[A] Section::scope(self : Section[A]) -> TimeScope {
  self.scope
}

///|
pub fn[A] Section::body(self : Section[A]) -> @pattern.Pat[A] {
  self.body
}
