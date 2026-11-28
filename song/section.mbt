///|
#derive(Eq, Debug)
pub(all) suberror SectionBuildError {
  NonPositiveLength
  NonPositiveRate
  EmptyLayers
  DuplicateLayer(String)
}

///|
/// One layer of a section: content with the identity playback keys it by.
pub struct SectionLayer[C] {
  priv id : @identity.SectionLayerId
  priv content : C
}

///|
pub fn[C] SectionLayer::SectionLayer(
  id~ : @identity.SectionLayerId,
  content~ : C,
) -> SectionLayer[C] {
  { id, content, }
}

///|
pub fn[C] SectionLayer::id(self : SectionLayer[C]) -> @identity.SectionLayerId {
  self.id
}

///|
pub fn[C] SectionLayer::content(self : SectionLayer[C]) -> C {
  self.content
}

///|
/// A length-bounded block of layers that a song places.
///
/// `rate` is content cycles per section cycle: at `2` the layers play twice
/// as fast inside the same section length, at `1/2` half as fast. Layers play
/// together, in order.
pub struct Section[C] {
  priv id : @identity.SectionId
  priv length_cycles : @pattern.Rational
  priv rate : @pattern.Rational
  priv layers : Array[SectionLayer[C]]
}

///|
/// A section of `layers` lasting `length_cycles`, or `SectionBuildError` when
/// it does not last, its rate is not positive, it has no layer, or two layers
/// share an id.
pub fn[C] Section::Section(
  id~ : @identity.SectionId,
  length_cycles~ : @pattern.Rational,
  rate~ : @pattern.Rational = @pattern.Rational::from_int(1),
  layers~ : Array[SectionLayer[C]],
) -> Section[C] raise SectionBuildError {
  guard length_cycles.num > 0L else { raise NonPositiveLength }
  guard rate.num > 0L else { raise NonPositiveRate }
  guard !layers.is_empty() else { raise EmptyLayers }
  let ids : Map[String, Bool] = Map([])
  for layer in layers {
    let id = layer.id.value()
    if ids.contains(id) {
      raise DuplicateLayer(id)
    }
    ids[id] = true
  }
  { id, length_cycles, rate, layers: layers.copy(), }
}

///|
pub fn[C] Section::id(self : Section[C]) -> @identity.SectionId {
  self.id
}

///|
pub fn[C] Section::length_cycles(self : Section[C]) -> @pattern.Rational {
  self.length_cycles
}

///|
pub fn[C] Section::rate(self : Section[C]) -> @pattern.Rational {
  self.rate
}

///|
pub fn[C] Section::layers(self : Section[C]) -> ArrayView[SectionLayer[C]] {
  self.layers[:]
}

///|
pub extend SectionBuildError with Debug::{to_repr}

///|
pub extend SectionBuildError with Eq::{not_equal, equal}
