///|
/// Section-local timing context.
///
/// The first implementation is intentionally identity-only. Groove, meter,
/// key, and rubato can be added behind this opaque representation without
/// changing the scheduler compatibility path.
pub struct TimeScope {
  priv identity : Bool
}

///|
pub fn TimeScope::TimeScope() -> TimeScope {
  { identity: true }
}

///|
pub fn TimeScope::identity() -> TimeScope {
  TimeScope()
}

///|
pub fn TimeScope::is_identity(self : TimeScope) -> Bool {
  self.identity
}
