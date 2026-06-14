///|
/// Provenance selector for active voices affected by an authoring edit.
///
/// Empty selectors intentionally match nothing. Use the existing pool-level
/// all-notes controls for broad emergency stops; this target is for precise
/// provenance-bound edit policies.
pub struct AffectedVoiceTarget {
  priv raw : @model.AffectedVoiceTarget
} derive(Eq, Debug)

///|
pub fn AffectedVoiceTarget::AffectedVoiceTarget(
  pattern_node~ : @identity.PatternNodeId?,
  section~ : @identity.SectionId?,
  layer~ : @identity.SectionLayerId?,
  occurrence~ : @identity.OccurrenceId?,
) -> AffectedVoiceTarget {
  {
    raw: @model.AffectedVoiceTarget(
      pattern_node~,
      section~,
      layer~,
      occurrence~,
    ),
  }
}

///|
pub fn AffectedVoiceTarget::from_pattern_node(
  pattern_node : @identity.PatternNodeId,
) -> AffectedVoiceTarget {
  { raw: @model.AffectedVoiceTarget::from_pattern_node(pattern_node) }
}

///|
pub fn AffectedVoiceTarget::from_section(
  section : @identity.SectionId,
) -> AffectedVoiceTarget {
  { raw: @model.AffectedVoiceTarget::from_section(section) }
}

///|
pub fn AffectedVoiceTarget::from_layer(
  layer : @identity.SectionLayerId,
) -> AffectedVoiceTarget {
  { raw: @model.AffectedVoiceTarget::from_layer(layer) }
}

///|
pub fn AffectedVoiceTarget::from_occurrence(
  occurrence : @identity.OccurrenceId,
) -> AffectedVoiceTarget {
  { raw: @model.AffectedVoiceTarget::from_occurrence(occurrence) }
}

///|
fn AffectedVoiceTarget::from_model(
  target : @model.AffectedVoiceTarget,
) -> AffectedVoiceTarget {
  { raw: target }
}

///|
pub fn AffectedVoiceTarget::pattern_node(
  self : AffectedVoiceTarget,
) -> @identity.PatternNodeId? {
  self.raw.pattern_node()
}

///|
pub fn AffectedVoiceTarget::section(
  self : AffectedVoiceTarget,
) -> @identity.SectionId? {
  self.raw.section()
}

///|
pub fn AffectedVoiceTarget::layer(
  self : AffectedVoiceTarget,
) -> @identity.SectionLayerId? {
  self.raw.layer()
}

///|
pub fn AffectedVoiceTarget::occurrence(
  self : AffectedVoiceTarget,
) -> @identity.OccurrenceId? {
  self.raw.occurrence()
}

///|
pub fn AffectedVoiceTarget::is_empty(self : AffectedVoiceTarget) -> Bool {
  self.raw.is_empty()
}

///|
fn AffectedVoiceTarget::to_edit_policy(
  self : AffectedVoiceTarget,
) -> @edit_policy.AffectedVoiceTarget {
  @edit_policy.AffectedVoiceTarget(
    pattern_node=self.raw.pattern_node(),
    section=self.raw.section(),
    layer=self.raw.layer(),
    occurrence=self.raw.occurrence(),
  )
}

///|
pub fn AffectedVoiceTarget::matches(
  self : AffectedVoiceTarget,
  source : EventSource,
) -> Bool {
  let raw_source = source.to_model()
  @edit_policy.source_parts_match_target(
    pattern_nodes=raw_source.borrow_pattern_nodes(),
    section=raw_source.section(),
    layer=raw_source.layer(),
    occurrence=raw_source.occurrence(),
    self.to_edit_policy(),
  )
}

///|
pub fn EventSource::matches(
  self : EventSource,
  target : AffectedVoiceTarget,
) -> Bool {
  target.matches(self)
}

///|
/// Authoring edit boundary that can be mapped to active voice provenance.
///
/// This does not choose a stop policy. Callers still choose whether matching
/// voices preserve, release, or stop immediately.
pub struct AffectedVoiceEditScope {
  priv raw : @model.AffectedVoiceEditScope
} derive(Eq, Debug)

///|
pub fn AffectedVoiceEditScope::pattern_node(
  pattern_node : @identity.PatternNodeId,
) -> AffectedVoiceEditScope {
  { raw: @model.AffectedVoiceEditScope::pattern_node(pattern_node) }
}

///|
pub fn AffectedVoiceEditScope::song_occurrence(
  occurrence : @identity.OccurrenceId,
) -> AffectedVoiceEditScope {
  { raw: @model.AffectedVoiceEditScope::song_occurrence(occurrence) }
}

///|
pub fn AffectedVoiceEditScope::song_section(
  section : @identity.SectionId,
) -> AffectedVoiceEditScope {
  { raw: @model.AffectedVoiceEditScope::song_section(section) }
}

///|
pub fn AffectedVoiceEditScope::song_layer(
  section~ : @identity.SectionId,
  layer~ : @identity.SectionLayerId,
) -> AffectedVoiceEditScope {
  { raw: @model.AffectedVoiceEditScope::song_layer(section~, layer~) }
}

///|
pub fn AffectedVoiceEditScope::target(
  self : AffectedVoiceEditScope,
) -> AffectedVoiceTarget {
  AffectedVoiceTarget::from_model(self.raw.target())
}

///|
/// Policy for already-sounding voices when an authoring edit is known to affect
/// their provenance.
pub(all) enum AffectedVoicePolicy {
  /// Preserve current behavior: active voices ring until their stored gate-off.
  LetRing
  /// Gate off matching voices now and stop scheduler ownership of those notes.
  GateOffAffected
  /// Immediately stop matching voices and stop scheduler ownership.
  KillAffected
} derive(Eq, Debug)

///|
fn AffectedVoicePolicy::to_edit_policy(
  self : AffectedVoicePolicy,
) -> @edit_policy.AffectedVoicePolicy {
  match self {
    LetRing => @edit_policy.AffectedVoicePolicy::LetRing
    GateOffAffected => @edit_policy.AffectedVoicePolicy::GateOffAffected
    KillAffected => @edit_policy.AffectedVoicePolicy::KillAffected
  }
}

///|
pub fn PatternScheduler::active_note_matches(
  self : PatternScheduler,
  index : Int,
  target : AffectedVoiceTarget,
) -> Bool? {
  self.active_notes.matches_edit_policy(index, target.to_edit_policy())
}

///|
pub fn PatternScheduler::affected_active_note_count(
  self : PatternScheduler,
  target : AffectedVoiceTarget,
) -> Int {
  self.active_notes.affected_count(target.to_edit_policy())
}

///|
/// Apply an edit policy to currently active scheduler-owned notes.
///
/// This is an explicit control/edit-boundary helper, not part of the
/// audio-block query path. It does not allocate and it leaves unmatched or
/// empty-source notes untouched. Returns the number of active-note records that
/// were removed from scheduler ownership.
pub fn PatternScheduler::apply_affected_voice_policy(
  self : PatternScheduler,
  policy : AffectedVoicePolicy,
  target : AffectedVoiceTarget,
  pool : @moondsp.BoundVoicePool,
) -> Int {
  let raw_target = target.to_edit_policy()
  match @edit_policy.stop_for_policy(policy.to_edit_policy(), raw_target) {
    None => 0
    Some(stop) => self.active_notes.remove_affected(raw_target, pool, stop~)
  }
}

///|
/// Apply an explicit voice policy for a concrete authoring edit boundary.
pub fn PatternScheduler::apply_affected_voice_policy_for_edit(
  self : PatternScheduler,
  policy : AffectedVoicePolicy,
  edit : AffectedVoiceEditScope,
  pool : @moondsp.BoundVoicePool,
) -> Int {
  self.apply_affected_voice_policy(policy, edit.target(), pool)
}
