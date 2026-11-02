///|
/// Group this expression as one authored material without changing its content.
pub fn[A] Pat::material(self : Pat[A]) -> Pat[A] {
  match self.metadata.scope {
    Addressed(_) => self
    Anonymous | Material => self.with_scope(Material)
  }
}

///|
fn[A] Pat::with_scope(self : Pat[A], scope : EntryScope) -> Pat[A] {
  make_pat(
    self.query,
    self.metadata.period,
    self.body,
    scope,
    self.metadata.content,
  )
}

///|
/// True only when both sources are identifiable and have the same content.
/// Names and placement are separate. Arbitrary queries/callbacks return false.
pub fn[A] Pat::same_content(self : Pat[A], other : Pat[A]) -> Bool {
  let content = self.entry_signature()
  content != "" &&
  content == other.entry_signature() &&
  self.metadata.period == other.metadata.period
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
fn[A] combine_signature(prefix : String, pats : Array[Pat[A]]) -> String {
  let mut content = prefix + ":\{pats.length()}"
  for pat in pats {
    let signature = pat.entry_signature()
    if signature == "" {
      return ""
    }
    content = content + ":\{signature.length()}:\{signature}"
  }
  content
}

///|
fn[A] overlay_signature(pats : Array[Pat[A]]) -> String {
  let signatures : Array[String] = []
  // Content traverses raw overlays regardless of playback scopes. Opaque
  // queries remain atomic: their entry projections are not their query.
  fn collect_content(pat : Pat[A]) -> Bool {
    match pat.body {
      Silence => true
      Overlay(children) => {
        for child in children {
          guard collect_content(child) else { return false }
        }
        true
      }
      Opaque(_) => {
        let signature = pat.entry_signature()
        guard signature != "" else { return false }
        signatures.push(signature)
        true
      }
    }
  }
  for pat in pats {
    guard collect_content(pat) else { return "" }
  }
  match signatures {
    [] => "silence"
    [signature] => signature
    _ => {
      let mut content = "overlay:\{signatures.length()}:"
      for signature in signatures {
        content += ":\{signature.length()}:\{signature}"
      }
      content
    }
  }
}

///|
pub fn[A] Pat::entry_period(self : Pat[A]) -> Rational {
  self.metadata.period
}

///|
fn[A] Pat::entry_signature(self : Pat[A]) -> String {
  self.metadata.content
}

///|
/// The entry's address: its document node path when lowered from a document,
/// otherwise its position inside this anonymous pattern.
pub fn[A] Pat::entry_key(self : Pat[A]) -> String {
  match self.metadata.scope {
    Anonymous | Material => ""
    Addressed(key) => key
  }
}

///|
/// Return independent authored members, with their addresses.
///
/// Only raw anonymous overlays are traversed structurally. A transformed
/// query may retain child projections for entry consumers, but it is never
/// treated as an overlay during normalization.
pub fn[A] Pat::entries(self : Pat[A]) -> Array[Pat[A]] {
  let result = []
  fn visit(pat : Pat[A], path : String) -> Unit {
    match pat.metadata.scope {
      Addressed(_) => result.push(pat)
      Material => result.push(pat.with_scope(Addressed(path)))
      Anonymous =>
        match pat.body {
          Opaque([]) => result.push(pat.with_scope(Addressed(path)))
          Overlay(children) | Opaque(children) =>
            for i, child in children {
              visit(child, "\{path}/\{i}")
            }
          Silence => ()
        }
    }
  }
  visit(self, "root")
  result
}

///|
/// Give each entry, in `entries()` order, its address from `keys`.
fn[A] Pat::address_entries(self : Pat[A], keys : Array[String]) -> Pat[A] {
  let mut next = 0
  fn address(pat : Pat[A]) -> Pat[A] {
    fn take() -> Pat[A] {
      let key = keys[next]
      next += 1
      pat.with_scope(Addressed(key))
    }

    match pat.metadata.scope {
      Addressed(_) | Material => take()
      Anonymous =>
        match pat.body {
          Opaque([]) => take()
          Overlay(children) =>
            make_pat(
              pat.query,
              pat.metadata.period,
              Overlay(children.map(address)),
              Anonymous,
              pat.metadata.content,
            )
          Opaque(children) =>
            make_pat(
              pat.query,
              pat.metadata.period,
              Opaque(children.map(address)),
              Anonymous,
              pat.metadata.content,
            )
          Silence => pat
        }
    }
  }
  address(self)
}
