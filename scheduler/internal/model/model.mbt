///|
#derive(Eq, Debug)
pub struct PatternVoiceScope {
  priv node : @identity.PatternNodeId
}

///|
pub extend PatternVoiceScope with Eq::{not_equal, equal}

///|
pub extend PatternVoiceScope with @moonbitlang/core/debug.Debug::{to_repr}

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
#derive(Eq, Debug)
pub(all) enum SongVoiceScope {
  Occurrence(@identity.OccurrenceId)
  Section(@identity.SectionId)
  Layer(@identity.SectionId, @identity.SectionLayerId)
}

///|
pub extend SongVoiceScope with Eq::{not_equal, equal}

///|
pub extend SongVoiceScope with @moonbitlang/core/debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum VoiceOrigin {
  Anonymous
  Pattern(@pattern.PatternNodePath)
  Song(@song.SongEventOrigin)
}

///|
pub extend VoiceOrigin with Eq::{not_equal, equal}

///|
pub extend VoiceOrigin with @moonbitlang/core/debug.Debug::{to_repr}

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
