///|
/// Internal provenance selector used by scheduler edit policies.
pub struct AffectedVoiceTarget {
  priv pattern_node : @identity.PatternNodeId?
  priv section : @identity.SectionId?
  priv layer : @identity.SectionLayerId?
  priv occurrence : @identity.OccurrenceId?
}

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
fn AffectedVoiceTarget::is_empty(self : AffectedVoiceTarget) -> Bool {
  self.pattern_node is None &&
  self.section is None &&
  self.layer is None &&
  self.occurrence is None
}

///|
pub fn source_parts_match_target(
  pattern_nodes~ : Array[@identity.PatternNodeId],
  section~ : @identity.SectionId?,
  layer~ : @identity.SectionLayerId?,
  occurrence~ : @identity.OccurrenceId?,
  target : AffectedVoiceTarget,
) -> Bool {
  if target.is_empty() {
    return false
  }
  let pattern_matches = match target.pattern_node {
    Some(id) => pattern_nodes.contains(id)
    None => true
  }
  let section_matches = match target.section {
    Some(id) => section == Some(id)
    None => true
  }
  let layer_matches = match target.layer {
    Some(id) => layer == Some(id)
    None => true
  }
  let occurrence_matches = match target.occurrence {
    Some(id) => occurrence == Some(id)
    None => true
  }
  pattern_matches && section_matches && layer_matches && occurrence_matches
}

///|
/// Internal edit policy enum mirroring the public scheduler facade policy.
pub(all) enum AffectedVoicePolicy {
  LetRing
  GateOffAffected
  KillAffected
}

///|
pub enum AffectedVoiceStop {
  GateOff
  Kill
}

///|
pub fn stop_for_policy(
  policy : AffectedVoicePolicy,
  target : AffectedVoiceTarget,
) -> AffectedVoiceStop? {
  if target.is_empty() {
    return None
  }
  match policy {
    LetRing => None
    GateOffAffected => Some(GateOff)
    KillAffected => Some(Kill)
  }
}
