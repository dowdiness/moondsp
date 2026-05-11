///|
const DEFAULT_LAYER_NAME = "main"

///|
pub(all) suberror SectionBuildError {
  NonPositiveLength
} derive(Eq, Debug)

///|
/// Named pattern layer inside a section body.
///
/// Layers are ordered by their array position so stacked playback is
/// deterministic. Names are for addressing and replacement.
pub struct SectionLayer[A] {
  priv name : String
  priv body : @pattern.Pat[A]
}

///|
pub fn[A] SectionLayer::SectionLayer(
  name~ : String,
  body~ : @pattern.Pat[A],
) -> SectionLayer[A] {
  { name, body }
}

///|
pub fn[A] SectionLayer::name(self : SectionLayer[A]) -> String {
  self.name
}

///|
pub fn[A] SectionLayer::body(self : SectionLayer[A]) -> @pattern.Pat[A] {
  self.body
}

///|
/// Pattern body for a section.
///
/// `Single` keeps the initial identity-section API compact. `Layers` is the
/// first named structure needed for later variation and addressing APIs.
pub enum SectionBody[A] {
  Single(@pattern.Pat[A])
  Layers(Array[SectionLayer[A]])
}

///|
fn[A] SectionBody::snapshot(self : SectionBody[A]) -> SectionBody[A] {
  match self {
    Single(body) => Single(body)
    Layers(layers) => Layers(layers.copy())
  }
}

///|
pub fn[A] SectionBody::single(body : @pattern.Pat[A]) -> SectionBody[A] {
  Single(body)
}

///|
pub fn[A] SectionBody::layers(
  layers : Array[SectionLayer[A]],
) -> SectionBody[A] {
  Layers(layers.copy())
}

///|
pub fn[A] SectionBody::to_pattern(self : SectionBody[A]) -> @pattern.Pat[A] {
  match self {
    Single(body) => body
    Layers(layers) => {
      let pats : Array[@pattern.Pat[A]] = []
      for layer in layers {
        pats.push(layer.body())
      }
      @pattern.stack(pats)
    }
  }
}

///|
pub fn[A] SectionBody::layer_count(self : SectionBody[A]) -> Int {
  match self {
    Single(_) => 1
    Layers(layers) => layers.length()
  }
}

///|
pub fn[A] SectionBody::get_layer(
  self : SectionBody[A],
  name : String,
) -> @pattern.Pat[A]? {
  match self {
    Single(body) => if name == DEFAULT_LAYER_NAME { Some(body) } else { None }
    Layers(layers) => {
      for layer in layers {
        if layer.name() == name {
          return Some(layer.body())
        }
      }
      None
    }
  }
}

///|
fn[A] SectionBody::upsert_layer(
  self : SectionBody[A],
  name : String,
  body : @pattern.Pat[A],
) -> SectionBody[A] {
  let result : Array[SectionLayer[A]] = []
  match self {
    Single(existing) =>
      if name == DEFAULT_LAYER_NAME {
        result.push(SectionLayer(name~, body~))
      } else {
        result.push(SectionLayer(name=DEFAULT_LAYER_NAME, body=existing))
        result.push(SectionLayer(name~, body~))
      }
    Layers(layers) => {
      let mut replaced = false
      for layer in layers {
        if layer.name() == name {
          result.push(SectionLayer(name~, body~))
          replaced = true
        } else {
          result.push(layer)
        }
      }
      if !replaced {
        result.push(SectionLayer(name~, body~))
      }
    }
  }
  Layers(result)
}

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
  priv body : SectionBody[A]
}

///|
pub fn[A] Section::Section(
  name~ : String,
  length_cycles~ : @pattern.Rational,
  scope~ : TimeScope,
  body~ : SectionBody[A],
) -> Section[A] raise SectionBuildError {
  if length_cycles.num <= 0L {
    raise NonPositiveLength
  } else {
    { name, length_cycles, scope, body: body.snapshot() }
  }
}

///|
pub fn[A] Section::from_pattern(
  name~ : String,
  body~ : @pattern.Pat[A],
) -> Section[A] {
  {
    name,
    length_cycles: @pattern.Rational::from_int(1),
    scope: TimeScope::identity(),
    body: SectionBody::single(body),
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
  self.body.to_pattern()
}

///|
pub fn[A] Section::section_body(self : Section[A]) -> SectionBody[A] {
  self.body.snapshot()
}

///|
pub fn[A] Section::get_layer(
  self : Section[A],
  name : String,
) -> @pattern.Pat[A]? {
  self.body.get_layer(name)
}

///|
pub fn[A] Section::layer_count(self : Section[A]) -> Int {
  self.body.layer_count()
}

///|
pub fn[A] Section::layer(
  self : Section[A],
  name~ : String,
  body~ : @pattern.Pat[A],
) -> Section[A] {
  {
    name: self.name,
    length_cycles: self.length_cycles,
    scope: self.scope,
    body: self.body.upsert_layer(name, body),
  }
}
