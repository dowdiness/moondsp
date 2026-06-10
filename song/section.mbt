///|
const DEFAULT_LAYER_NAME = "main"

///|
pub(all) suberror SectionBuildError {
  NonPositiveLength
} derive(Eq, Debug)

///|
pub(all) suberror SectionPatchError {
  MissingLayer(String)
  DuplicateLayer(String)
} derive(Eq, Debug)

///|
pub(all) suberror SectionDocBuildError {
  NonPositiveSectionLength
  EmptyLayers
  DuplicateLayerId(String)
  DuplicateLayerName(String)
} derive(Eq, Debug)

///|
pub(all) suberror SectionDocEditError {
  MissingLayerId(String)
  DuplicateLayerName(String)
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
/// Identity-bearing authoring layer for incremental section edits.
///
/// The display `name` can change without changing `id` or `revision`. Replacing
/// the body advances only this layer's revision; containing section documents
/// decide whether that layer change also advances the section revision.
pub struct SectionLayerDoc[A] {
  priv id : @identity.SectionLayerId
  priv name : String
  priv revision : @identity.Revision
  priv body : @pattern.Pat[A]
}

///|
pub fn[A] SectionLayerDoc::SectionLayerDoc(
  id~ : @identity.SectionLayerId,
  name~ : String,
  body~ : @pattern.Pat[A],
) -> SectionLayerDoc[A] {
  { id, name, revision: @identity.Revision::zero(), body }
}

///|
pub fn[A] SectionLayerDoc::id(
  self : SectionLayerDoc[A],
) -> @identity.SectionLayerId {
  self.id
}

///|
pub fn[A] SectionLayerDoc::name(self : SectionLayerDoc[A]) -> String {
  self.name
}

///|
pub fn[A] SectionLayerDoc::revision(
  self : SectionLayerDoc[A],
) -> @identity.Revision {
  self.revision
}

///|
pub fn[A] SectionLayerDoc::body(self : SectionLayerDoc[A]) -> @pattern.Pat[A] {
  self.body
}

///|
pub fn[A] SectionLayerDoc::rename(
  self : SectionLayerDoc[A],
  name~ : String,
) -> SectionLayerDoc[A] {
  { id: self.id, name, revision: self.revision, body: self.body }
}

///|
pub fn[A] SectionLayerDoc::replace_body(
  self : SectionLayerDoc[A],
  body~ : @pattern.Pat[A],
) -> SectionLayerDoc[A] {
  { id: self.id, name: self.name, revision: self.revision.next(), body }
}

///|
pub fn[A] SectionLayerDoc::to_layer(
  self : SectionLayerDoc[A],
) -> SectionLayer[A] {
  SectionLayer(name=self.name, body=self.body)
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
/// Small typed patch language for section variations.
///
/// This intentionally covers only layer add/replace operations. Addressing,
/// ranges, and boundary operations need a song-layout model and should be
/// layered on later.
pub enum SectionPatch[A] {
  SetLayer(String, @pattern.Pat[A])
  AddLayer(String, @pattern.Pat[A])
}

///|
pub fn[A] SectionPatch::set_layer(
  name : String,
  body : @pattern.Pat[A],
) -> SectionPatch[A] {
  SetLayer(name, body)
}

///|
pub fn[A] SectionPatch::add_layer(
  name : String,
  body : @pattern.Pat[A],
) -> SectionPatch[A] {
  AddLayer(name, body)
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
/// Identity-bearing section body for authoring-time edits.
///
/// `Single` keeps an explicit layer identity for the default single-pattern
/// path. `Layers` preserves ordered playback while allowing layer IDs to remain
/// stable across display-name edits.
pub enum SectionDocBody[A] {
  Single(SectionLayerDoc[A])
  Layers(Array[SectionLayerDoc[A]])
}

///|
pub fn[A] SectionDocBody::single(
  layer : SectionLayerDoc[A],
) -> SectionDocBody[A] {
  Single(layer)
}

///|
pub fn[A] SectionDocBody::layers(
  layers : Array[SectionLayerDoc[A]],
) -> SectionDocBody[A] {
  Layers(layers.copy())
}

///|
fn[A] SectionDocBody::snapshot(self : SectionDocBody[A]) -> SectionDocBody[A] {
  match self {
    Single(layer) => Single(layer)
    Layers(layers) => Layers(layers.copy())
  }
}

///|
fn[A] SectionDocBody::to_section_body(
  self : SectionDocBody[A],
) -> SectionBody[A] {
  match self {
    Single(layer) => SectionBody::single(layer.body())
    Layers(layers) => {
      let result : Array[SectionLayer[A]] = []
      for layer in layers {
        result.push(layer.to_layer())
      }
      SectionBody::layers(result)
    }
  }
}

///|
pub fn[A] SectionDocBody::layer_count(self : SectionDocBody[A]) -> Int {
  match self {
    Single(_) => 1
    Layers(layers) => layers.length()
  }
}

///|
pub fn[A] SectionDocBody::get_layer(
  self : SectionDocBody[A],
  id : @identity.SectionLayerId,
) -> SectionLayerDoc[A]? {
  match self {
    Single(layer) => if layer.id() == id { Some(layer) } else { None }
    Layers(layers) => {
      for layer in layers {
        if layer.id() == id {
          return Some(layer)
        }
      }
      None
    }
  }
}

///|
fn[A] section_doc_body_has_layer_name_except(
  body : SectionDocBody[A],
  name : String,
  id : @identity.SectionLayerId,
) -> Bool {
  match body {
    Single(layer) => layer.id() != id && layer.name() == name
    Layers(layers) =>
      layers.iter().any(layer => layer.id() != id && layer.name() == name)
  }
}

///|
fn[A] validate_section_doc_body(
  body : SectionDocBody[A],
) -> Unit raise SectionDocBuildError {
  match body {
    Single(_) => ()
    Layers(layers) => {
      if layers.is_empty() {
        raise EmptyLayers
      }
      let ids : Map[String, Bool] = {}
      let names : Map[String, Bool] = {}
      for layer in layers {
        let id_value = layer.id().value()
        if ids.contains(id_value) {
          raise DuplicateLayerId(id_value)
        }
        if names.contains(layer.name()) {
          raise DuplicateLayerName(layer.name())
        }
        ids[id_value] = true
        names[layer.name()] = true
      }
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
      let replaced = for layer in layers; did_replace = false {
        if layer.name() == name {
          result.push(SectionLayer(name~, body~))
          continue true
        }
        result.push(layer)
        continue did_replace
      } nobreak {
        did_replace
      }
      if !replaced {
        result.push(SectionLayer(name~, body~))
      }
    }
  }
  Layers(result)
}

///|
fn[A] SectionBody::add_layer(
  self : SectionBody[A],
  name : String,
  body : @pattern.Pat[A],
) -> SectionBody[A] raise SectionPatchError {
  match self.get_layer(name) {
    Some(_) => raise DuplicateLayer(name)
    None => self.upsert_layer(name, body)
  }
}

///|
fn[A] SectionBody::set_layer(
  self : SectionBody[A],
  name : String,
  body : @pattern.Pat[A],
) -> SectionBody[A] raise SectionPatchError {
  let result : Array[SectionLayer[A]] = []
  match self {
    Single(_) =>
      if name == DEFAULT_LAYER_NAME {
        Single(body)
      } else {
        raise MissingLayer(name)
      }
    Layers(layers) => {
      let replaced = for layer in layers; did_replace = false {
        if layer.name() == name {
          result.push(SectionLayer(name~, body~))
          continue true
        }
        result.push(layer)
        continue did_replace
      } nobreak {
        did_replace
      }
      if !replaced {
        raise MissingLayer(name)
      }
      Layers(result)
    }
  }
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
/// Identity-bearing authoring section for incremental song edits.
///
/// This document lowers to the existing `Section[A]` playback value. Display
/// renames keep stable IDs and revisions; body, length, and scope edits advance
/// revision tokens so future song snapshots can invalidate the right boundary.
pub struct SectionDoc[A] {
  priv id : @identity.SectionId
  priv name : String
  priv length_cycles : @pattern.Rational
  priv scope : TimeScope
  priv revision : @identity.Revision
  priv body : SectionDocBody[A]
}

///|
pub fn[A] SectionDoc::SectionDoc(
  id~ : @identity.SectionId,
  name~ : String,
  length_cycles~ : @pattern.Rational,
  scope~ : TimeScope,
  body~ : SectionDocBody[A],
) -> SectionDoc[A] raise SectionDocBuildError {
  if length_cycles.num <= 0L {
    raise NonPositiveSectionLength
  }
  validate_section_doc_body(body)
  {
    id,
    name,
    length_cycles,
    scope,
    revision: @identity.Revision::zero(),
    body: body.snapshot(),
  }
}

///|
pub fn[A] SectionDoc::single(
  id~ : @identity.SectionId,
  name~ : String,
  length_cycles~ : @pattern.Rational,
  scope~ : TimeScope,
  layer_id~ : @identity.SectionLayerId,
  body~ : @pattern.Pat[A],
) -> SectionDoc[A] raise SectionDocBuildError {
  SectionDoc(
    id~,
    name~,
    length_cycles~,
    scope~,
    body=SectionDocBody::single(
      SectionLayerDoc(id=layer_id, name="main", body~),
    ),
  )
}

///|
pub fn[A] SectionDoc::id(self : SectionDoc[A]) -> @identity.SectionId {
  self.id
}

///|
pub fn[A] SectionDoc::name(self : SectionDoc[A]) -> String {
  self.name
}

///|
pub fn[A] SectionDoc::length_cycles(self : SectionDoc[A]) -> @pattern.Rational {
  self.length_cycles
}

///|
pub fn[A] SectionDoc::scope(self : SectionDoc[A]) -> TimeScope {
  self.scope
}

///|
pub fn[A] SectionDoc::revision(self : SectionDoc[A]) -> @identity.Revision {
  self.revision
}

///|
pub fn[A] SectionDoc::body(self : SectionDoc[A]) -> SectionDocBody[A] {
  self.body.snapshot()
}

///|
pub fn[A] SectionDoc::layer_count(self : SectionDoc[A]) -> Int {
  self.body.layer_count()
}

///|
pub fn[A] SectionDoc::get_layer(
  self : SectionDoc[A],
  id : @identity.SectionLayerId,
) -> SectionLayerDoc[A]? {
  self.body.get_layer(id)
}

///|
pub fn[A] SectionDoc::rename(
  self : SectionDoc[A],
  name~ : String,
) -> SectionDoc[A] {
  {
    id: self.id,
    name,
    length_cycles: self.length_cycles,
    scope: self.scope,
    revision: self.revision,
    body: self.body.snapshot(),
  }
}

///|
pub fn[A] SectionDoc::with_length(
  self : SectionDoc[A],
  length_cycles~ : @pattern.Rational,
) -> SectionDoc[A] raise SectionDocBuildError {
  if length_cycles.num <= 0L {
    raise NonPositiveSectionLength
  }
  {
    id: self.id,
    name: self.name,
    length_cycles,
    scope: self.scope,
    revision: self.revision.next(),
    body: self.body.snapshot(),
  }
}

///|
pub fn[A] SectionDoc::with_scope(
  self : SectionDoc[A],
  scope~ : TimeScope,
) -> SectionDoc[A] {
  {
    id: self.id,
    name: self.name,
    length_cycles: self.length_cycles,
    scope,
    revision: self.revision.next(),
    body: self.body.snapshot(),
  }
}

///|
pub fn[A] SectionDoc::rename_layer(
  self : SectionDoc[A],
  id : @identity.SectionLayerId,
  name~ : String,
) -> SectionDoc[A] raise SectionDocEditError {
  let (body, found) = match self.body {
    Single(layer) =>
      if layer.id() == id {
        (SectionDocBody::single(layer.rename(name~)), true)
      } else {
        (self.body.snapshot(), false)
      }
    Layers(layers) => {
      let result : Array[SectionLayerDoc[A]] = []
      let found = for layer in layers; did_find = false {
        if layer.id() == id {
          if section_doc_body_has_layer_name_except(self.body, name, id) {
            raise DuplicateLayerName(name)
          }
          result.push(layer.rename(name~))
          continue true
        }
        result.push(layer)
        continue did_find
      } nobreak {
        did_find
      }
      (SectionDocBody::layers(result), found)
    }
  }
  if !found {
    raise MissingLayerId(id.value())
  }
  {
    id: self.id,
    name: self.name,
    length_cycles: self.length_cycles,
    scope: self.scope,
    revision: self.revision,
    body,
  }
}

///|
pub fn[A] SectionDoc::replace_layer_body(
  self : SectionDoc[A],
  id : @identity.SectionLayerId,
  body~ : @pattern.Pat[A],
) -> SectionDoc[A] raise SectionDocEditError {
  let (doc_body, found) = match self.body {
    Single(layer) =>
      if layer.id() == id {
        (SectionDocBody::single(layer.replace_body(body~)), true)
      } else {
        (self.body.snapshot(), false)
      }
    Layers(layers) => {
      let result : Array[SectionLayerDoc[A]] = []
      let found = for layer in layers; did_find = false {
        if layer.id() == id {
          result.push(layer.replace_body(body~))
          continue true
        }
        result.push(layer)
        continue did_find
      } nobreak {
        did_find
      }
      (SectionDocBody::layers(result), found)
    }
  }
  if !found {
    raise MissingLayerId(id.value())
  }
  {
    id: self.id,
    name: self.name,
    length_cycles: self.length_cycles,
    scope: self.scope,
    revision: self.revision.next(),
    body: doc_body,
  }
}

///|
pub fn[A] SectionDoc::to_section(self : SectionDoc[A]) -> Section[A] {
  {
    name: self.name,
    length_cycles: self.length_cycles,
    scope: self.scope,
    body: self.body.to_section_body(),
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
/// Query the section body in section-local time with this section's
/// `TimeScope` applied.
///
/// `Section::body()` intentionally exposes the raw unscoped pattern for
/// structural callers. Playback and song layout should use this method so
/// non-identity scopes can map event spans without changing occurrence layout.
pub fn[A] Section::query(
  self : Section[A],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[A]] {
  let body = self.body.to_pattern()
  if self.scope.is_identity() {
    body.query(arc)
  } else {
    body.fast(self.scope.rate()).query(arc)
  }
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

///|
pub fn[A] Section::apply_patch(
  self : Section[A],
  patch : SectionPatch[A],
) -> Section[A] raise SectionPatchError {
  let body = match patch {
    SetLayer(name, body) => self.body.set_layer(name, body)
    AddLayer(name, body) => self.body.add_layer(name, body)
  }
  {
    name: self.name,
    length_cycles: self.length_cycles,
    scope: self.scope,
    body,
  }
}
