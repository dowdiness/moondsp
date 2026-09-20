///|
/// Select a sound route while preserving voice scopes and material keys.
pub fn PatternSnapshot::select_control(
  self : PatternSnapshot[ControlMap],
  key : String,
  value? : Double,
) -> PatternSnapshot[ControlMap] {
  fn project(
    source : Pat[ScopedValue[ControlMap, Unit]],
  ) -> Pat[ScopedValue[ControlMap, Unit]] {
    select_control_kernel(source, payload => payload.value, key, value)
  }
  {
    root: self.root,
    revision: self.revision,
    pat: self.pat.select_control(key, value?),
    sourced: project(self.sourced),
    entry_sourced: self.entry_sourced.map(entry => {
      CompiledEntry(entry.key, project(entry.source))
    }),
  }
}

///|
/// Routing preserves exact origins; it never erases and reattributes events.
pub fn PatternSnapshotWithOrigins::select_control(
  self : PatternSnapshotWithOrigins[ControlMap],
  key : String,
  value? : Double,
) -> PatternSnapshotWithOrigins[ControlMap] {
  fn project(
    source : Pat[ScopedValue[ControlMap, EventOrigin]],
  ) -> Pat[ScopedValue[ControlMap, EventOrigin]] {
    select_control_kernel(source, payload => payload.value, key, value)
  }
  let sourced = project(self.sourced)
  {
    root: self.root,
    revision: self.revision,
    pat: sourced.map_payload(erase_value),
    sourced,
    entry_sourced: self.entry_sourced.map(entry => {
      CompiledEntry(entry.key, project(entry.source))
    }),
  }
}
