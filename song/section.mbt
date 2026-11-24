///|
const DEFAULT_LAYER_NAME = "main"

///|
#derive(Eq, Debug)
pub(all) suberror SectionBuildError {
  NonPositiveLength
}

///|
#derive(Eq, Debug)
pub(all) suberror SectionPatchError {
  MissingLayer(String)
  DuplicateLayer(String)
}

///|
#derive(Eq, Debug)
pub(all) suberror SectionDocBuildError {
  NonPositiveSectionLength
  EmptyLayers
  DuplicateLayerId(String)
  DuplicateLayerName(String)
}

///|
#derive(Eq, Debug)
pub(all) suberror SectionDocEditError {
  MissingLayerId(String)
  DuplicateLayerName(String)
}

///|
/// Named pattern layer inside a section body.
///
/// Layers are ordered by their array position so stacked playback is
/// deterministic. Names are for addressing and replacement.
pub struct SectionLayer[C] {
  priv name : String
  priv body : C
}

///|
pub fn[C] SectionLayer::SectionLayer(
  name~ : String,
  body~ : C,
) -> SectionLayer[C] {
  { name, body, }
}

///|
pub fn[C] SectionLayer::name(self : SectionLayer[C]) -> String {
  self.name
}

///|
pub fn[C] SectionLayer::body(self : SectionLayer[C]) -> C {
  self.body
}

///|
/// Identity-bearing authoring layer for incremental section edits.
///
/// The display `name` can change without changing `id` or `revision`. Replacing
/// the body advances only this layer's revision; containing section documents
/// decide whether that layer change also advances the section revision.
pub struct SectionLayerDoc[C] {
  priv id : @identity.SectionLayerId
  priv name : String
  priv revision : @identity.Revision
  priv body : C
}

///|
pub fn[C] SectionLayerDoc::SectionLayerDoc(
  id~ : @identity.SectionLayerId,
  name~ : String,
  body~ : C,
) -> SectionLayerDoc[C] {
  { id, name, revision: @identity.Revision::zero(), body, }
}

///|
pub fn[C] SectionLayerDoc::id(
  self : SectionLayerDoc[C],
) -> @identity.SectionLayerId {
  self.id
}

///|
pub fn[C] SectionLayerDoc::name(self : SectionLayerDoc[C]) -> String {
  self.name
}

///|
pub fn[C] SectionLayerDoc::revision(
  self : SectionLayerDoc[C],
) -> @identity.Revision {
  self.revision
}

///|
pub fn[C] SectionLayerDoc::body(self : SectionLayerDoc[C]) -> C {
  self.body
}

///|
pub fn[C] SectionLayerDoc::rename(
  self : SectionLayerDoc[C],
  name~ : String,
) -> SectionLayerDoc[C] {
  { id: self.id, name, revision: self.revision, body: self.body, }
}

///|
pub fn[C] SectionLayerDoc::replace_body(
  self : SectionLayerDoc[C],
  body~ : C,
) -> SectionLayerDoc[C] {
  { id: self.id, name: self.name, revision: self.revision.next(), body, }
}

///|
pub fn[C] SectionLayerDoc::to_layer(
  self : SectionLayerDoc[C],
) -> SectionLayer[C] {
  SectionLayer(name=self.name, body=self.body)
}

///|
/// Pattern body for a section.
///
/// `Single` keeps the initial identity-section API compact. `Layers` is the
/// first named structure needed for later variation and addressing APIs.
pub enum SectionBody[C] {
  Single(C)
  Layers(Array[SectionLayer[C]])
}

///|
/// Small typed patch language for section variations.
///
/// This intentionally covers only layer add/replace operations. Addressing,
/// ranges, and boundary operations need a song-layout model and should be
/// layered on later.
pub enum SectionPatch[C] {
  SetLayer(String, C)
  AddLayer(String, C)
}

///|
pub fn[C] SectionPatch::set_layer(name : String, body : C) -> SectionPatch[C] {
  SetLayer(name, body)
}

///|
pub fn[C] SectionPatch::add_layer(name : String, body : C) -> SectionPatch[C] {
  AddLayer(name, body)
}

///|
fn[C] SectionBody::snapshot(self : SectionBody[C]) -> SectionBody[C] {
  match self {
    Single(body) => Single(body)
    Layers(layers) => Layers(layers.copy())
  }
}

///|
pub fn[C] SectionBody::single(body : C) -> SectionBody[C] {
  Single(body)
}

///|
pub fn[C] SectionBody::layers(
  layers : Array[SectionLayer[C]],
) -> SectionBody[C] {
  Layers(layers.copy())
}

///|
/// The section's layers stacked into one pattern.
pub fn[C : SongContent] SectionBody::to_pattern(
  self : SectionBody[C],
) -> @pattern.Pat[@score.ScoreEvent] {
  match self {
    Single(body) => body.pat()
    Layers(layers) => @pattern.stack(layers.map(layer => layer.body().pat()))
  }
}

///|
pub fn[C] SectionBody::layer_count(self : SectionBody[C]) -> Int32 {
  match self {
    Single(_) => 1
    Layers(layers) => layers.length()
  }
}

///|
pub fn[C] SectionBody::get_layer(self : SectionBody[C], name : String) -> C? {
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
pub enum SectionDocBody[C] {
  Single(SectionLayerDoc[C])
  Layers(Array[SectionLayerDoc[C]])
}

///|
pub fn[C] SectionDocBody::single(
  layer : SectionLayerDoc[C],
) -> SectionDocBody[C] {
  Single(layer)
}

///|
pub fn[C] SectionDocBody::layers(
  layers : Array[SectionLayerDoc[C]],
) -> SectionDocBody[C] {
  Layers(layers.copy())
}

///|
fn[C] SectionDocBody::snapshot(self : SectionDocBody[C]) -> SectionDocBody[C] {
  match self {
    Single(layer) => Single(layer)
    Layers(layers) => Layers(layers.copy())
  }
}

///|
fn[C] SectionDocBody::to_section_body(
  self : SectionDocBody[C],
) -> SectionBody[C] {
  match self {
    Single(layer) => SectionBody::single(layer.body())
    Layers(layers) => SectionBody::layers(layers.map(layer => layer.to_layer()))
  }
}

///|
pub fn[C] SectionDocBody::layer_count(self : SectionDocBody[C]) -> Int32 {
  match self {
    Single(_) => 1
    Layers(layers) => layers.length()
  }
}

///|
pub fn[C] SectionDocBody::get_layer(
  self : SectionDocBody[C],
  id : @identity.SectionLayerId,
) -> SectionLayerDoc[C]? {
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
fn[C] section_doc_body_has_layer_name_except(
  body : SectionDocBody[C],
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
fn[C] validate_section_doc_body(
  body : SectionDocBody[C],
) -> Unit raise SectionDocBuildError {
  match body {
    Single(_) => ()
    Layers(layers) => {
      if layers.is_empty() {
        raise EmptyLayers
      }
      let ids : Map[String, Bool] = Map([])
      let names : Map[String, Bool] = Map([])
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
fn[C] SectionBody::upsert_layer(
  self : SectionBody[C],
  name : String,
  body : C,
) -> SectionBody[C] {
  let result : Array[SectionLayer[C]] = []
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
fn[C] SectionBody::add_layer(
  self : SectionBody[C],
  name : String,
  body : C,
) -> SectionBody[C] raise SectionPatchError {
  match self.get_layer(name) {
    Some(_) => raise DuplicateLayer(name)
    None => self.upsert_layer(name, body)
  }
}

///|
fn[C] SectionBody::set_layer(
  self : SectionBody[C],
  name : String,
  body : C,
) -> SectionBody[C] raise SectionPatchError {
  let result : Array[SectionLayer[C]] = []
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
/// Named long-form region over layers of content `C`.
///
/// `Section` is structure only: names, length, local time scope, and layers.
/// Structural operations never look inside the content; only the queries that
/// need a pattern require `C : SongContent`, so one structure holds runtime
/// patterns and lowered pattern snapshots alike (ADR-0021).
pub struct Section[C] {
  priv name : String
  priv length_cycles : @pattern.Rational
  priv scope : TimeScope
  priv body : SectionBody[C]
}

///|
pub fn[C] Section::Section(
  name~ : String,
  length_cycles~ : @pattern.Rational,
  scope~ : TimeScope,
  body~ : SectionBody[C],
) -> Section[C] raise SectionBuildError {
  if length_cycles.num <= 0L {
    raise NonPositiveLength
  } else {
    { name, length_cycles, scope, body: body.snapshot(), }
  }
}

///|
/// Identity-bearing authoring section for incremental song edits.
///
/// This document lowers to the `Section[C]` playback value. Display
/// renames keep stable IDs and revisions; body, length, and scope edits advance
/// revision tokens so future song snapshots can invalidate the right boundary.
pub struct SectionDoc[C] {
  priv id : @identity.SectionId
  priv name : String
  priv length_cycles : @pattern.Rational
  priv scope : TimeScope
  priv revision : @identity.Revision
  priv body : SectionDocBody[C]
}

///|
pub fn[C] SectionDoc::SectionDoc(
  id~ : @identity.SectionId,
  name~ : String,
  length_cycles~ : @pattern.Rational,
  scope~ : TimeScope,
  body~ : SectionDocBody[C],
) -> SectionDoc[C] raise SectionDocBuildError {
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
pub fn[C] SectionDoc::single(
  id~ : @identity.SectionId,
  name~ : String,
  length_cycles~ : @pattern.Rational,
  scope~ : TimeScope,
  layer_id~ : @identity.SectionLayerId,
  body~ : C,
) -> SectionDoc[C] raise SectionDocBuildError {
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
pub fn[C] SectionDoc::id(self : SectionDoc[C]) -> @identity.SectionId {
  self.id
}

///|
pub fn[C] SectionDoc::name(self : SectionDoc[C]) -> String {
  self.name
}

///|
pub fn[C] SectionDoc::length_cycles(self : SectionDoc[C]) -> @pattern.Rational {
  self.length_cycles
}

///|
pub fn[C] SectionDoc::scope(self : SectionDoc[C]) -> TimeScope {
  self.scope
}

///|
pub fn[C] SectionDoc::revision(self : SectionDoc[C]) -> @identity.Revision {
  self.revision
}

///|
pub fn[C] SectionDoc::body(self : SectionDoc[C]) -> SectionDocBody[C] {
  self.body.snapshot()
}

///|
pub fn[C] SectionDoc::layer_count(self : SectionDoc[C]) -> Int32 {
  self.body.layer_count()
}

///|
pub fn[C] SectionDoc::get_layer(
  self : SectionDoc[C],
  id : @identity.SectionLayerId,
) -> SectionLayerDoc[C]? {
  self.body.get_layer(id)
}

///|
pub fn[C] SectionDoc::rename(
  self : SectionDoc[C],
  name~ : String,
) -> SectionDoc[C] {
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
pub fn[C] SectionDoc::with_length(
  self : SectionDoc[C],
  length_cycles~ : @pattern.Rational,
) -> SectionDoc[C] raise SectionDocBuildError {
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
pub fn[C] SectionDoc::with_scope(
  self : SectionDoc[C],
  scope~ : TimeScope,
) -> SectionDoc[C] {
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
pub fn[C] SectionDoc::rename_layer(
  self : SectionDoc[C],
  id : @identity.SectionLayerId,
  name~ : String,
) -> SectionDoc[C] raise SectionDocEditError {
  let (body, found) = match self.body {
    Single(layer) =>
      if layer.id() == id {
        (SectionDocBody::single(layer.rename(name~)), true)
      } else {
        (self.body.snapshot(), false)
      }
    Layers(layers) => {
      let result : Array[SectionLayerDoc[C]] = []
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
pub fn[C] SectionDoc::replace_layer_body(
  self : SectionDoc[C],
  id : @identity.SectionLayerId,
  body~ : C,
) -> SectionDoc[C] raise SectionDocEditError {
  let (doc_body, found) = match self.body {
    Single(layer) =>
      if layer.id() == id {
        (SectionDocBody::single(layer.replace_body(body~)), true)
      } else {
        (self.body.snapshot(), false)
      }
    Layers(layers) => {
      let result : Array[SectionLayerDoc[C]] = []
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
pub fn[C] SectionDoc::to_section(self : SectionDoc[C]) -> Section[C] {
  {
    name: self.name,
    length_cycles: self.length_cycles,
    scope: self.scope,
    body: self.body.to_section_body(),
  }
}

///|
/// A one-cycle section with a single layer and the identity scope.
pub fn[C] Section::single(name~ : String, body~ : C) -> Section[C] {
  {
    name,
    length_cycles: @pattern.Rational::from_int(1),
    scope: TimeScope::identity(),
    body: SectionBody::single(body),
  }
}

///|
pub fn[C] Section::name(self : Section[C]) -> String {
  self.name
}

///|
pub fn[C] Section::length_cycles(self : Section[C]) -> @pattern.Rational {
  self.length_cycles
}

///|
pub fn[C] Section::scope(self : Section[C]) -> TimeScope {
  self.scope
}

///|
/// The section's layers stacked into one pattern, without its scope.
pub fn[C : SongContent] Section::body(
  self : Section[C],
) -> @pattern.Pat[@score.ScoreEvent] {
  self.body.to_pattern()
}

///|
/// Query the section body in section-local time with this section's
/// `TimeScope` applied.
///
/// `Section::body()` intentionally exposes the raw unscoped pattern for
/// structural callers. Playback and song layout should use this method so
/// non-identity scopes can map event spans without changing occurrence layout.
pub fn[C : SongContent] Section::query(
  self : Section[C],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@score.ScoreEvent]] {
  let body = self.body.to_pattern()
  if self.scope.is_identity() {
    body.query(arc)
  } else {
    body.fast(self.scope.rate()).query(arc)
  }
}

///|
pub fn[C] Section::section_body(self : Section[C]) -> SectionBody[C] {
  self.body.snapshot()
}

///|
pub fn[C] Section::get_layer(self : Section[C], name : String) -> C? {
  self.body.get_layer(name)
}

///|
pub fn[C] Section::layer_count(self : Section[C]) -> Int32 {
  self.body.layer_count()
}

///|
pub fn[C] Section::layer(
  self : Section[C],
  name~ : String,
  body~ : C,
) -> Section[C] {
  {
    name: self.name,
    length_cycles: self.length_cycles,
    scope: self.scope,
    body: self.body.upsert_layer(name, body),
  }
}

///|
pub fn[C] Section::apply_patch(
  self : Section[C],
  patch : SectionPatch[C],
) -> Section[C] raise SectionPatchError {
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

///|
pub extend SectionBuildError with Debug::{to_repr}

///|
pub extend SectionBuildError with Eq::{not_equal, equal}

///|
pub extend SectionPatchError with Debug::{to_repr}

///|
pub extend SectionPatchError with Eq::{not_equal, equal}

///|
pub extend SectionDocBuildError with Debug::{to_repr}

///|
pub extend SectionDocBuildError with Eq::{not_equal, equal}

///|
pub extend SectionDocEditError with Debug::{to_repr}

///|
pub extend SectionDocEditError with Eq::{not_equal, equal}
