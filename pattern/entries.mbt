///|
/// Give an authored material a stable address. The name is not a clock group.
pub fn[A] Pat::named_entry(self : Pat[A], name : String) -> Pat[A] {
  { ..self, entry_key: name, }
}

///|
/// Mark one compiled expression as an indivisible authored material.
/// The caller must change the signature whenever its content changes. An empty
/// signature makes replacement conservative: the content is always rechecked.
pub fn[A] Pat::material(self : Pat[A], signature : String) -> Pat[A] {
  { ..self, members: [], signature, }
}

///|
/// Record an outer transformation independently on each stack member.
pub fn[A] Pat::entry_transform(self : Pat[A], signature : String) -> Pat[A] {
  {
    ..self,
    signature: if self.signature == "" {
      ""
    } else {
      self.signature + signature
    },
    members: self.members.map(p => p.entry_transform(signature)),
  }
}

///|
pub fn[A] Pat::entry_period(self : Pat[A]) -> Rational {
  self.period
}

///|
pub fn[A] Pat::entry_signature(self : Pat[A]) -> String {
  let mut text = self.signature
  for p in self.members {
    let part = p.entry_signature()
    // Unknown content must stay unknown when a stack becomes one material.
    if part == "" {
      return ""
    }
    text = text +
      "/\{p.entry_key.length()}:\{p.entry_key}:\{part.length()}:\{part}"
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
      result.push({ ..pat, entry_key: path, })
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
