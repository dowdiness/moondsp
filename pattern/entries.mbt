///|
/// Give an authored material a stable address. The name is not a clock group.
pub fn[A] Pat::named_entry(self : Pat[A], name : String) -> Pat[A] {
  { ..self, entry_key: name }
}

///|
/// Group this expression as one authored material without changing its content.
pub fn[A] Pat::material(self : Pat[A]) -> Pat[A] {
  { ..self, members: [], signature: self.entry_signature() }
}

///|
/// True only when both sources are identifiable and have the same content.
/// Names and placement are separate. Arbitrary queries/callbacks return false.
pub fn[A] Pat::same_content(self : Pat[A], other : Pat[A]) -> Bool {
  let signature = self.entry_signature()
  signature != "" &&
  signature == other.entry_signature() &&
  self.period == other.period
}

///|
// A missing source or callback identity stays unknown. Length framing prevents
// unrelated transformation chains from sharing an identity.
fn transformed_signature(source : String, change : String) -> String {
  if source == "" || change == "" {
    return ""
  }
  "\{source.length()}:\{source}/\{change.length()}:\{change}"
}

///|
pub fn[A] Pat::entry_period(self : Pat[A]) -> Rational {
  self.period
}

///|
fn[A] Pat::entry_signature(self : Pat[A]) -> String {
  let mut text = self.signature
  for p in self.members {
    let part = p.entry_signature()
    // Unknown content must stay unknown when a stack becomes one material.
    if part == "" {
      return ""
    }
    text = text + "/\{part.length()}:\{part}"
  }
  text
}

///|
pub fn[A] Pat::entry_key(self : Pat[A]) -> String {
  self.entry_key
}

///|
/// Return independent authored members, with owned address metadata.
pub fn[A] Pat::entries(self : Pat[A]) -> Array[Pat[A]] {
  let result = []
  fn visit(pat : Pat[A], path : String) -> Unit {
    if pat.members.is_empty() {
      result.push({ ..pat, entry_key: path })
    } else {
      let seen : Map[String, Int] = Map([])
      for i, child in pat.members {
        let key = if child.entry_key == "" {
          "slot:\{i}"
        } else {
          "name:\{child.entry_key}"
        }
        let count = seen.get(key).unwrap_or(0)
        seen[key] = count + 1
        visit(child, path + "/\{key.length()}:\{key}:\{count}")
      }
    }
  }
  visit(
    self,
    if self.entry_key == "" {
      "root"
    } else {
      "name:" + self.entry_key
    },
  )
  result
}
