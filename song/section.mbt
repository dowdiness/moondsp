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
pub struct SectionLayer {
  priv name : String
  priv body : @pattern.Pat[@pattern.ControlMap]
}

///|
pub fn SectionLayer::SectionLayer(
  name~ : String,
  body~ : @pattern.Pat[@pattern.ControlMap],
) -> SectionLayer {
  { name, body, }
}

///|
pub fn SectionLayer::name(self : SectionLayer) -> String {
  self.name
}

///|
pub fn SectionLayer::body(
  self : SectionLayer,
) -> @pattern.Pat[@pattern.ControlMap] {
  self.body
}

///|
/// Identity-bearing authoring layer for incremental section edits.
///
/// The display `name` can change without changing `id` or `revision`. Replacing
/// the body advances only this layer's revision; containing section documents
/// decide whether that layer change also advances the section revision.
pub struct SectionLayerDoc {
  priv id : @identity.SectionLayerId
  priv name : String
  priv revision : @identity.Revision
  priv body : @pattern.Pat[@pattern.ControlMap]
  priv source_snapshot : @pattern.PatternSnapshotWithOrigins?
}

///|
pub fn SectionLayerDoc::SectionLayerDoc(
  id~ : @identity.SectionLayerId,
  name~ : String,
  body~ : @pattern.Pat[@pattern.ControlMap],
) -> SectionLayerDoc {
  {
    id,
    name,
    revision: @identity.Revision::zero(),
    body,
    source_snapshot: None,
  }
}

///|
pub fn SectionLayerDoc::id(self : SectionLayerDoc) -> @identity.SectionLayerId {
  self.id
}

///|
pub fn SectionLayerDoc::name(self : SectionLayerDoc) -> String {
  self.name
}

///|
pub fn SectionLayerDoc::revision(self : SectionLayerDoc) -> @identity.Revision {
  self.revision
}

///|
pub fn SectionLayerDoc::body(
  self : SectionLayerDoc,
) -> @pattern.Pat[@pattern.ControlMap] {
  self.body
}

///|
pub fn SectionLayerDoc::rename(
  self : SectionLayerDoc,
  name~ : String,
) -> SectionLayerDoc {
  {
    id: self.id,
    name,
    revision: self.revision,
    body: self.body,
    source_snapshot: self.source_snapshot,
  }
}

///|
pub fn SectionLayerDoc::replace_body(
  self : SectionLayerDoc,
  body~ : @pattern.Pat[@pattern.ControlMap],
) -> SectionLayerDoc {
  {
    id: self.id,
    name: self.name,
    revision: self.revision.next(),
    body,
    source_snapshot: None,
  }
}

///|
pub fn SectionLayerDoc::to_layer(self : SectionLayerDoc) -> SectionLayer {
  SectionLayer(name=self.name, body=self.body)
}

///|
/// Pattern body for a section.
///
/// `Single` keeps the initial identity-section API compact. `Layers` is the
/// first named structure needed for later variation and addressing APIs.
pub enum SectionBody {
  Single(@pattern.Pat[@pattern.ControlMap])
  Layers(Array[SectionLayer])
}

///|
/// Small typed patch language for section variations.
///
/// This intentionally covers only layer add/replace operations. Addressing,
/// ranges, and boundary operations need a song-layout model and should be
/// layered on later.
pub enum SectionPatch {
  SetLayer(String, @pattern.Pat[@pattern.ControlMap])
  AddLayer(String, @pattern.Pat[@pattern.ControlMap])
}

///|
pub fn SectionPatch::set_layer(
  name : String,
  body : @pattern.Pat[@pattern.ControlMap],
) -> SectionPatch {
  SetLayer(name, body)
}

///|
pub fn SectionPatch::add_layer(
  name : String,
  body : @pattern.Pat[@pattern.ControlMap],
) -> SectionPatch {
  AddLayer(name, body)
}

///|
fn SectionBody::snapshot(self : SectionBody) -> SectionBody {
  match self {
    Single(body) => Single(body)
    Layers(layers) => Layers(layers.copy())
  }
}

///|
pub fn SectionBody::single(
  body : @pattern.Pat[@pattern.ControlMap],
) -> SectionBody {
  Single(body)
}

///|
pub fn SectionBody::layers(layers : Array[SectionLayer]) -> SectionBody {
  Layers(layers.copy())
}

///|
pub fn SectionBody::to_pattern(
  self : SectionBody,
) -> @pattern.Pat[@pattern.ControlMap] {
  match self {
    Single(body) => body
    Layers(layers) => @pattern.stack(layers.map(layer => layer.body()))
  }
}

///|
pub fn SectionBody::layer_count(self : SectionBody) -> Int32 {
  match self {
    Single(_) => 1
    Layers(layers) => layers.length()
  }
}

///|
pub fn SectionBody::get_layer(
  self : SectionBody,
  name : String,
) -> @pattern.Pat[@pattern.ControlMap]? {
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
pub enum SectionDocBody {
  Single(SectionLayerDoc)
  Layers(Array[SectionLayerDoc])
}

///|
pub fn SectionDocBody::single(layer : SectionLayerDoc) -> SectionDocBody {
  Single(layer)
}

///|
pub fn SectionDocBody::layers(
  layers : Array[SectionLayerDoc],
) -> SectionDocBody {
  Layers(layers.copy())
}

///|
fn SectionDocBody::snapshot(self : SectionDocBody) -> SectionDocBody {
  match self {
    Single(layer) => Single(layer)
    Layers(layers) => Layers(layers.copy())
  }
}

///|
fn SectionDocBody::to_section_body(self : SectionDocBody) -> SectionBody {
  match self {
    Single(layer) => SectionBody::single(layer.body())
    Layers(layers) => SectionBody::layers(layers.map(layer => layer.to_layer()))
  }
}

///|
pub fn SectionDocBody::layer_count(self : SectionDocBody) -> Int32 {
  match self {
    Single(_) => 1
    Layers(layers) => layers.length()
  }
}

///|
pub fn SectionDocBody::get_layer(
  self : SectionDocBody,
  id : @identity.SectionLayerId,
) -> SectionLayerDoc? {
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
fn section_doc_body_has_layer_name_except(
  body : SectionDocBody,
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
fn validate_section_doc_body(
  body : SectionDocBody,
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
fn SectionBody::upsert_layer(
  self : SectionBody,
  name : String,
  body : @pattern.Pat[@pattern.ControlMap],
) -> SectionBody {
  let result : Array[SectionLayer] = []
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
fn SectionBody::add_layer(
  self : SectionBody,
  name : String,
  body : @pattern.Pat[@pattern.ControlMap],
) -> SectionBody raise SectionPatchError {
  match self.get_layer(name) {
    Some(_) => raise DuplicateLayer(name)
    None => self.upsert_layer(name, body)
  }
}

///|
fn SectionBody::set_layer(
  self : SectionBody,
  name : String,
  body : @pattern.Pat[@pattern.ControlMap],
) -> SectionBody raise SectionPatchError {
  let result : Array[SectionLayer] = []
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
/// Named long-form region over a `ControlMap` pattern body.
pub struct Section {
  priv name : String
  priv length_cycles : @pattern.Rational
  priv scope : TimeScope
  priv body : SectionBody
  priv source_snapshot : @pattern.PatternSnapshotWithOrigins?
}

///|
pub fn Section::Section(
  name~ : String,
  length_cycles~ : @pattern.Rational,
  scope~ : TimeScope,
  body~ : SectionBody,
) -> Section raise SectionBuildError {
  if length_cycles.num <= 0L {
    raise NonPositiveLength
  } else {
    {
      name,
      length_cycles,
      scope,
      body: body.snapshot(),
      source_snapshot: None,
    }
  }
}

///|
/// Compile-time provenance for a single pattern section. The runtime body is
/// derived from the snapshot, so its events cannot disagree with its origins.
pub fn Section::with_origins(
  name~ : String,
  length_cycles~ : @pattern.Rational,
  scope~ : TimeScope,
  snapshot~ : @pattern.PatternSnapshotWithOrigins,
) -> Section raise SectionBuildError {
  if length_cycles.num <= 0L {
    raise NonPositiveLength
  }
  {
    name,
    length_cycles,
    scope,
    body: SectionBody::single(snapshot.pat()),
    source_snapshot: Some(snapshot),
  }
}

///|
pub fn Section::source_snapshot(
  self : Section,
) -> @pattern.PatternSnapshotWithOrigins? {
  self.source_snapshot
}

///|
/// Identity-bearing authoring section for incremental song edits.
///
/// This document lowers to the `Section` playback value. Display
/// renames keep stable IDs and revisions; body, length, and scope edits advance
/// revision tokens so future song snapshots can invalidate the right boundary.
pub struct SectionDoc {
  priv id : @identity.SectionId
  priv name : String
  priv length_cycles : @pattern.Rational
  priv scope : TimeScope
  priv revision : @identity.Revision
  priv body : SectionDocBody
}

///|
pub fn SectionDoc::SectionDoc(
  id~ : @identity.SectionId,
  name~ : String,
  length_cycles~ : @pattern.Rational,
  scope~ : TimeScope,
  body~ : SectionDocBody,
) -> SectionDoc raise SectionDocBuildError {
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
pub fn SectionDoc::single(
  id~ : @identity.SectionId,
  name~ : String,
  length_cycles~ : @pattern.Rational,
  scope~ : TimeScope,
  layer_id~ : @identity.SectionLayerId,
  body~ : @pattern.Pat[@pattern.ControlMap],
) -> SectionDoc raise SectionDocBuildError {
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
pub fn SectionDoc::single_with_origins(
  id~ : @identity.SectionId,
  name~ : String,
  length_cycles~ : @pattern.Rational,
  scope~ : TimeScope,
  layer_id~ : @identity.SectionLayerId,
  snapshot~ : @pattern.PatternSnapshotWithOrigins,
) -> SectionDoc raise SectionDocBuildError {
  SectionDoc(
    id~,
    name~,
    length_cycles~,
    scope~,
    body=SectionDocBody::single({
      id: layer_id,
      name: DEFAULT_LAYER_NAME,
      revision: @identity.Revision::zero(),
      body: snapshot.pat(),
      source_snapshot: Some(snapshot),
    }),
  )
}

///|
pub fn SectionDoc::id(self : SectionDoc) -> @identity.SectionId {
  self.id
}

///|
pub fn SectionDoc::name(self : SectionDoc) -> String {
  self.name
}

///|
pub fn SectionDoc::length_cycles(self : SectionDoc) -> @pattern.Rational {
  self.length_cycles
}

///|
pub fn SectionDoc::scope(self : SectionDoc) -> TimeScope {
  self.scope
}

///|
pub fn SectionDoc::revision(self : SectionDoc) -> @identity.Revision {
  self.revision
}

///|
pub fn SectionDoc::body(self : SectionDoc) -> SectionDocBody {
  self.body.snapshot()
}

///|
pub fn SectionDoc::layer_count(self : SectionDoc) -> Int32 {
  self.body.layer_count()
}

///|
pub fn SectionDoc::get_layer(
  self : SectionDoc,
  id : @identity.SectionLayerId,
) -> SectionLayerDoc? {
  self.body.get_layer(id)
}

///|
pub fn SectionDoc::rename(self : SectionDoc, name~ : String) -> SectionDoc {
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
pub fn SectionDoc::with_length(
  self : SectionDoc,
  length_cycles~ : @pattern.Rational,
) -> SectionDoc raise SectionDocBuildError {
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
pub fn SectionDoc::with_scope(
  self : SectionDoc,
  scope~ : TimeScope,
) -> SectionDoc {
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
pub fn SectionDoc::rename_layer(
  self : SectionDoc,
  id : @identity.SectionLayerId,
  name~ : String,
) -> SectionDoc raise SectionDocEditError {
  let (body, found) = match self.body {
    Single(layer) =>
      if layer.id() == id {
        (SectionDocBody::single(layer.rename(name~)), true)
      } else {
        (self.body.snapshot(), false)
      }
    Layers(layers) => {
      let result : Array[SectionLayerDoc] = []
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
pub fn SectionDoc::replace_layer_body(
  self : SectionDoc,
  id : @identity.SectionLayerId,
  body~ : @pattern.Pat[@pattern.ControlMap],
) -> SectionDoc raise SectionDocEditError {
  let (doc_body, found) = match self.body {
    Single(layer) =>
      if layer.id() == id {
        (SectionDocBody::single(layer.replace_body(body~)), true)
      } else {
        (self.body.snapshot(), false)
      }
    Layers(layers) => {
      let result : Array[SectionLayerDoc] = []
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
pub fn SectionDoc::to_section(self : SectionDoc) -> Section {
  {
    name: self.name,
    length_cycles: self.length_cycles,
    scope: self.scope,
    body: self.body.to_section_body(),
    source_snapshot: match self.body {
      Single(layer) => layer.source_snapshot
      Layers(_) => None
    },
  }
}

///|
pub fn Section::from_pattern(
  name~ : String,
  body~ : @pattern.Pat[@pattern.ControlMap],
) -> Section {
  {
    name,
    length_cycles: @pattern.Rational::from_int(1),
    scope: TimeScope::identity(),
    body: SectionBody::single(body),
    source_snapshot: None,
  }
}

///|
pub fn Section::name(self : Section) -> String {
  self.name
}

///|
pub fn Section::length_cycles(self : Section) -> @pattern.Rational {
  self.length_cycles
}

///|
pub fn Section::scope(self : Section) -> TimeScope {
  self.scope
}

///|
pub fn Section::body(self : Section) -> @pattern.Pat[@pattern.ControlMap] {
  self.body.to_pattern()
}

///|
/// Query the section body in section-local time with this section's
/// `TimeScope` applied.
///
/// `Section::body()` intentionally exposes the raw unscoped pattern for
/// structural callers. Playback and song layout should use this method so
/// non-identity scopes can map event spans without changing occurrence layout.
pub fn Section::query(
  self : Section,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  let body = self.body.to_pattern()
  if self.scope.is_identity() {
    body.query(arc)
  } else {
    body.fast(self.scope.rate()).query(arc)
  }
}

///|
pub fn Section::section_body(self : Section) -> SectionBody {
  self.body.snapshot()
}

///|
pub fn Section::get_layer(
  self : Section,
  name : String,
) -> @pattern.Pat[@pattern.ControlMap]? {
  self.body.get_layer(name)
}

///|
pub fn Section::layer_count(self : Section) -> Int32 {
  self.body.layer_count()
}

///|
pub fn Section::layer(
  self : Section,
  name~ : String,
  body~ : @pattern.Pat[@pattern.ControlMap],
) -> Section {
  {
    name: self.name,
    length_cycles: self.length_cycles,
    scope: self.scope,
    body: self.body.upsert_layer(name, body),
    source_snapshot: None,
  }
}

///|
pub fn Section::apply_patch(
  self : Section,
  patch : SectionPatch,
) -> Section raise SectionPatchError {
  let body = match patch {
    SetLayer(name, body) => self.body.set_layer(name, body)
    AddLayer(name, body) => self.body.add_layer(name, body)
  }
  {
    name: self.name,
    length_cycles: self.length_cycles,
    scope: self.scope,
    body,
    source_snapshot: None,
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
