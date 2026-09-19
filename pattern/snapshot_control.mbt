///|
/// Select a sound route without losing the authored origin of its events.
/// The canonical entry keys and content fingerprints remain stable across edits.
pub fn PatternSnapshot::select_control(
  self : PatternSnapshot[ControlMap],
  key : String,
  value? : Double,
) -> PatternSnapshot[ControlMap] {
  fn selected(event : PatternSnapshotEvent[ControlMap]) -> Bool {
    match event.event().value.get(key) {
      None => false
      Some(actual) =>
        match value {
          None => true
          Some(expected) => actual == expected
        }
    }
  }
  fn project(source : SourcedPat[ControlMap]) -> SourcedPat[ControlMap] {
    { query: arc => source.query(arc).filter(selected), }
  }
  {
    root: self.root,
    revision: self.revision,
    pat: self.pat.select_control(key, value?),
    sourced: project(self.sourced),
    entry_sourced: self.entry_sourced.map(entry => {
      key: entry.key,
      source: project(entry.source),
    }),
  }
}
