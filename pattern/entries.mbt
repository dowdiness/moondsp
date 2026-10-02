///|
/// Give an authored material a stable address. The name is not a clock group.
pub fn[A] Pat::named_entry(self : Pat[A], name : String) -> Pat[A] {
  let scope = match self.metadata.scope {
    Material | NamedMaterial(_) => NamedMaterial(name)
    Anonymous | Named(_) => Named(name)
  }
  make_pat(
    self.query,
    self.metadata.period,
    self.body,
    scope,
    self.metadata.content,
  )
}

///|
fn EntryScope::as_material(self : EntryScope) -> EntryScope {
  match self {
    Named(name) | NamedMaterial(name) => NamedMaterial(name)
    Anonymous | Material => Material
  }
}

///|
/// Group this expression as one authored material without changing its content.
pub fn[A] Pat::material(self : Pat[A]) -> Pat[A] {
  make_pat(
    self.query,
    self.metadata.period,
    self.body,
    self.metadata.scope.as_material(),
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
pub fn[A] Pat::entry_key(self : Pat[A]) -> String {
  match self.metadata.scope {
    Anonymous | Material => ""
    Named(name) | NamedMaterial(name) => name
  }
}

///|
fn scope_path_key(scope : EntryScope, index : Int) -> String {
  match scope {
    Named(name) | NamedMaterial(name) => "name:\{name}"
    Anonymous | Material => "slot:\{index}"
  }
}

///|
fn[A] Pat::entry_at_path(self : Pat[A], path : String) -> Pat[A] {
  make_pat(
    self.query,
    self.metadata.period,
    self.body,
    match self.metadata.scope {
      Material | NamedMaterial(_) => NamedMaterial(path)
      Anonymous | Named(_) => Named(path)
    },
    self.metadata.content,
  )
}

///|
/// Return independent authored members, with owned address metadata.
///
/// Only raw anonymous overlays are traversed structurally. A transformed
/// query may retain child projections for entry consumers, but it is never
/// treated as an overlay during normalization.
pub fn[A] Pat::entries(self : Pat[A]) -> Array[Pat[A]] {
  let result = []
  fn visit(pat : Pat[A], path : String) -> Unit {
    match pat.metadata.scope {
      Material | NamedMaterial(_) => result.push(pat.entry_at_path(path))
      Anonymous | Named(_) =>
        match pat.body {
          Opaque([]) => result.push(pat.entry_at_path(path))
          Overlay(children) | Opaque(children) => {
            let seen : Map[String, Int] = Map([])
            for i, child in children {
              let key = scope_path_key(child.metadata.scope, i)
              let count = seen.get(key).unwrap_or(0)
              seen[key] = count + 1
              visit(child, path + "/\{key.length()}:\{key}:\{count}")
            }
          }
          Silence =>
            match pat.metadata.scope {
              Named(_) => result.push(pat.entry_at_path(path))
              _ => ()
            }
        }
    }
  }
  let root_path = match self.metadata.scope {
    Named(name) | NamedMaterial(name) => "name:" + name
    Anonymous | Material => "root"
  }
  visit(self, root_path)
  result
}
