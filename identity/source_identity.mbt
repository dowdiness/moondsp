///|
/// A validated namespace for one uninterrupted source-tracking lifetime.
pub struct SourceEpoch {
  priv value : Int64
} derive(Eq, Debug)

///|
/// A validated source atom identity qualified by its source epoch.
pub struct SourceAtomId {
  priv epoch : SourceEpoch
  priv serial : Int64
} derive(Eq, Debug)

///|
/// A validated definition identity qualified by its source epoch.
pub struct DefinitionId {
  priv epoch : SourceEpoch
  priv serial : Int64
} derive(Eq, Debug)

///|
/// A validated reference identity qualified by its source epoch.
pub struct ReferenceId {
  priv epoch : SourceEpoch
  priv serial : Int64
} derive(Eq, Debug)

///|
/// A validated reference binding identity qualified by its source epoch.
pub struct ReferenceBindingId {
  priv epoch : SourceEpoch
  priv serial : Int64
} derive(Eq, Debug)

///|
/// JavaScript-safe positive integer upper bound, inclusive.
const SOURCE_IDENTITY_MAX : Int64 = 9007199254740991L

///|
fn validate_source_identity_component(
  value : Int64,
) -> Int64 raise StableIdError {
  guard value > 0L && value <= SOURCE_IDENTITY_MAX else {
    raise StableIdError::InvalidId(value.to_string())
  }
  value
}

///|
/// Construct a validated source epoch.
pub fn SourceEpoch::SourceEpoch(
  value : Int64,
) -> SourceEpoch raise StableIdError {
  { value: validate_source_identity_component(value), }
}

///|
/// Return the serialized epoch number.
pub fn SourceEpoch::serial(self : SourceEpoch) -> Int64 {
  self.value
}

///|
/// Construct a validated source atom identity.
pub fn SourceAtomId::SourceAtomId(
  epoch : SourceEpoch,
  serial : Int64,
) -> SourceAtomId raise StableIdError {
  { epoch, serial: validate_source_identity_component(serial), }
}

///|
/// Return the source epoch of this atom identity.
pub fn SourceAtomId::epoch(self : SourceAtomId) -> SourceEpoch {
  self.epoch
}

///|
/// Return the serial number of this atom identity.
pub fn SourceAtomId::serial(self : SourceAtomId) -> Int64 {
  self.serial
}

///|
/// Construct a validated definition identity.
pub fn DefinitionId::DefinitionId(
  epoch : SourceEpoch,
  serial : Int64,
) -> DefinitionId raise StableIdError {
  { epoch, serial: validate_source_identity_component(serial), }
}

///|
/// Return the source epoch of this definition identity.
pub fn DefinitionId::epoch(self : DefinitionId) -> SourceEpoch {
  self.epoch
}

///|
/// Return the serial number of this definition identity.
pub fn DefinitionId::serial(self : DefinitionId) -> Int64 {
  self.serial
}

///|
/// Construct a validated reference identity.
pub fn ReferenceId::ReferenceId(
  epoch : SourceEpoch,
  serial : Int64,
) -> ReferenceId raise StableIdError {
  { epoch, serial: validate_source_identity_component(serial), }
}

///|
/// Return the source epoch of this reference identity.
pub fn ReferenceId::epoch(self : ReferenceId) -> SourceEpoch {
  self.epoch
}

///|
/// Return the serial number of this reference identity.
pub fn ReferenceId::serial(self : ReferenceId) -> Int64 {
  self.serial
}

///|
/// Construct a validated reference binding identity.
pub fn ReferenceBindingId::ReferenceBindingId(
  epoch : SourceEpoch,
  serial : Int64,
) -> ReferenceBindingId raise StableIdError {
  { epoch, serial: validate_source_identity_component(serial), }
}

///|
/// Return the source epoch of this reference binding identity.
pub fn ReferenceBindingId::epoch(self : ReferenceBindingId) -> SourceEpoch {
  self.epoch
}

///|
/// Return the serial number of this reference binding identity.
pub fn ReferenceBindingId::serial(self : ReferenceBindingId) -> Int64 {
  self.serial
}

///|
pub extend SourceEpoch with Eq::{equal, not_equal}

///|
pub extend SourceEpoch with Debug::{to_repr}

///|
pub extend SourceAtomId with Eq::{equal, not_equal}

///|
pub extend SourceAtomId with Debug::{to_repr}

///|
pub extend DefinitionId with Eq::{equal, not_equal}

///|
pub extend DefinitionId with Debug::{to_repr}

///|
pub extend ReferenceId with Eq::{equal, not_equal}

///|
pub extend ReferenceId with Debug::{to_repr}

///|
pub extend ReferenceBindingId with Eq::{equal, not_equal}

///|
pub extend ReferenceBindingId with Debug::{to_repr}
