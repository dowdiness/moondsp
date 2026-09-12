///|
pub struct PatternVoiceScope {
  priv node : @identity.PatternNodeId
} derive(Eq, Debug)

///|
pub fn PatternVoiceScope::PatternVoiceScope(
  node : @identity.PatternNodeId,
) -> PatternVoiceScope {
  { node, }
}

///|
pub fn PatternVoiceScope::node(
  self : PatternVoiceScope,
) -> @identity.PatternNodeId {
  self.node
}

///|
pub(all) enum SongVoiceScope {
  Occurrence(@identity.OccurrenceId)
  Section(@identity.SectionId)
  Layer(@identity.SectionId, @identity.SectionLayerId)
} derive(Eq, Debug)

///|
pub(all) enum VoiceOrigin {
  Anonymous
  Pattern(@pattern.PatternNodePath)
  Song(@song.SongEventOrigin)
} derive(Eq, Debug)

///|
pub fn VoiceOrigin::matches_pattern_scope(
  self : VoiceOrigin,
  scope : PatternVoiceScope,
) -> Bool {
  match self {
    Pattern(path) => path.nodes().contains(scope.node())
    Anonymous | Song(_) => false
  }
}

///|
pub fn VoiceOrigin::matches_song_scope(
  self : VoiceOrigin,
  scope : SongVoiceScope,
) -> Bool {
  match self {
    Song(origin) =>
      match scope {
        Occurrence(id) => origin.occurrence() == id
        Section(id) => origin.section() == id
        Layer(section, layer) =>
          origin.section() == section && origin.layer() == layer
      }
    Anonymous | Pattern(_) => false
  }
}
