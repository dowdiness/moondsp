///|
/// Internal scheduler provenance payload shared by facade wrappers and runtime
/// helpers.
pub struct EventSource {
  priv pattern_node : @identity.PatternNodeId?
  priv pattern_nodes : Array[@identity.PatternNodeId]
  priv section : @identity.SectionId?
  priv layer : @identity.SectionLayerId?
  priv occurrence : @identity.OccurrenceId?
} derive(Eq, Debug)

///|
fn pattern_node_path_from_primary(
  pattern_node : @identity.PatternNodeId?,
) -> Array[@identity.PatternNodeId] {
  match pattern_node {
    Some(id) => [id]
    None => []
  }
}

///|
fn primary_pattern_node(
  pattern_nodes : Array[@identity.PatternNodeId],
) -> @identity.PatternNodeId? {
  if pattern_nodes.is_empty() {
    None
  } else {
    Some(pattern_nodes[pattern_nodes.length() - 1])
  }
}

///|
pub fn EventSource::EventSource(
  pattern_node~ : @identity.PatternNodeId?,
  section~ : @identity.SectionId?,
  layer~ : @identity.SectionLayerId?,
  occurrence~ : @identity.OccurrenceId?,
) -> EventSource {
  {
    pattern_node,
    pattern_nodes: pattern_node_path_from_primary(pattern_node),
    section,
    layer,
    occurrence,
  }
}

///|
pub fn EventSource::from_pattern_nodes(
  pattern_nodes~ : Array[@identity.PatternNodeId],
  section~ : @identity.SectionId?,
  layer~ : @identity.SectionLayerId?,
  occurrence~ : @identity.OccurrenceId?,
) -> EventSource {
  let nodes = pattern_nodes.copy()
  {
    pattern_node: primary_pattern_node(nodes),
    pattern_nodes: nodes,
    section,
    layer,
    occurrence,
  }
}

///|
pub fn EventSource::none() -> EventSource {
  {
    pattern_node: None,
    pattern_nodes: [],
    section: None,
    layer: None,
    occurrence: None,
  }
}

///|
pub fn EventSource::pattern_node(
  self : EventSource,
) -> @identity.PatternNodeId? {
  self.pattern_node
}

///|
pub fn EventSource::pattern_nodes(
  self : EventSource,
) -> Array[@identity.PatternNodeId] {
  self.pattern_nodes.copy()
}

///|
pub fn EventSource::borrow_pattern_nodes(
  self : EventSource,
) -> Array[@identity.PatternNodeId] {
  self.pattern_nodes
}

///|
pub fn EventSource::section(self : EventSource) -> @identity.SectionId? {
  self.section
}

///|
pub fn EventSource::layer(self : EventSource) -> @identity.SectionLayerId? {
  self.layer
}

///|
pub fn EventSource::occurrence(self : EventSource) -> @identity.OccurrenceId? {
  self.occurrence
}

///|
pub fn EventSource::is_empty(self : EventSource) -> Bool {
  self.pattern_node is None &&
  self.pattern_nodes.is_empty() &&
  self.section is None &&
  self.layer is None &&
  self.occurrence is None
}

///|
/// Internal scheduler event wrapper with provenance kept out of pattern.Event.
pub struct PlaybackEvent {
  priv event : @pattern.Event[@pattern.ControlMap]
  priv source : EventSource
}

///|
pub fn PlaybackEvent::PlaybackEvent(
  event~ : @pattern.Event[@pattern.ControlMap],
  source~ : EventSource,
) -> PlaybackEvent {
  { event, source }
}

///|
pub fn PlaybackEvent::event(
  self : PlaybackEvent,
) -> @pattern.Event[@pattern.ControlMap] {
  self.event
}

///|
pub fn PlaybackEvent::source(self : PlaybackEvent) -> EventSource {
  self.source
}

///|
/// Internal provenance selector backing the public affected-voice facade.
pub struct AffectedVoiceTarget {
  priv pattern_node : @identity.PatternNodeId?
  priv section : @identity.SectionId?
  priv layer : @identity.SectionLayerId?
  priv occurrence : @identity.OccurrenceId?
} derive(Eq, Debug)

///|
pub fn AffectedVoiceTarget::AffectedVoiceTarget(
  pattern_node~ : @identity.PatternNodeId?,
  section~ : @identity.SectionId?,
  layer~ : @identity.SectionLayerId?,
  occurrence~ : @identity.OccurrenceId?,
) -> AffectedVoiceTarget {
  { pattern_node, section, layer, occurrence }
}

///|
pub fn AffectedVoiceTarget::from_pattern_node(
  pattern_node : @identity.PatternNodeId,
) -> AffectedVoiceTarget {
  {
    pattern_node: Some(pattern_node),
    section: None,
    layer: None,
    occurrence: None,
  }
}

///|
pub fn AffectedVoiceTarget::from_section(
  section : @identity.SectionId,
) -> AffectedVoiceTarget {
  { pattern_node: None, section: Some(section), layer: None, occurrence: None }
}

///|
pub fn AffectedVoiceTarget::from_layer(
  layer : @identity.SectionLayerId,
) -> AffectedVoiceTarget {
  { pattern_node: None, section: None, layer: Some(layer), occurrence: None }
}

///|
pub fn AffectedVoiceTarget::from_occurrence(
  occurrence : @identity.OccurrenceId,
) -> AffectedVoiceTarget {
  {
    pattern_node: None,
    section: None,
    layer: None,
    occurrence: Some(occurrence),
  }
}

///|
pub fn AffectedVoiceTarget::pattern_node(
  self : AffectedVoiceTarget,
) -> @identity.PatternNodeId? {
  self.pattern_node
}

///|
pub fn AffectedVoiceTarget::section(
  self : AffectedVoiceTarget,
) -> @identity.SectionId? {
  self.section
}

///|
pub fn AffectedVoiceTarget::layer(
  self : AffectedVoiceTarget,
) -> @identity.SectionLayerId? {
  self.layer
}

///|
pub fn AffectedVoiceTarget::occurrence(
  self : AffectedVoiceTarget,
) -> @identity.OccurrenceId? {
  self.occurrence
}

///|
pub fn AffectedVoiceTarget::is_empty(self : AffectedVoiceTarget) -> Bool {
  self.pattern_node is None &&
  self.section is None &&
  self.layer is None &&
  self.occurrence is None
}

///|
/// Internal authoring edit boundary backing the public affected-voice facade.
pub struct AffectedVoiceEditScope {
  priv target : AffectedVoiceTarget
} derive(Eq, Debug)

///|
pub fn AffectedVoiceEditScope::pattern_node(
  pattern_node : @identity.PatternNodeId,
) -> AffectedVoiceEditScope {
  { target: AffectedVoiceTarget::from_pattern_node(pattern_node) }
}

///|
pub fn AffectedVoiceEditScope::song_occurrence(
  occurrence : @identity.OccurrenceId,
) -> AffectedVoiceEditScope {
  { target: AffectedVoiceTarget::from_occurrence(occurrence) }
}

///|
pub fn AffectedVoiceEditScope::song_section(
  section : @identity.SectionId,
) -> AffectedVoiceEditScope {
  { target: AffectedVoiceTarget::from_section(section) }
}

///|
pub fn AffectedVoiceEditScope::song_layer(
  section~ : @identity.SectionId,
  layer~ : @identity.SectionLayerId,
) -> AffectedVoiceEditScope {
  {
    target: AffectedVoiceTarget(
      pattern_node=None,
      section=Some(section),
      layer=Some(layer),
      occurrence=None,
    ),
  }
}

///|
pub fn AffectedVoiceEditScope::target(
  self : AffectedVoiceEditScope,
) -> AffectedVoiceTarget {
  self.target
}
