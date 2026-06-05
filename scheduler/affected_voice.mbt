///|
/// Provenance selector for active voices affected by an authoring edit.
///
/// Empty selectors intentionally match nothing. Use the existing pool-level
/// all-notes controls for broad emergency stops; this target is for precise
/// provenance-bound edit policies.
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
fn AffectedVoiceTarget::to_edit_policy(
  self : AffectedVoiceTarget,
) -> @edit_policy.AffectedVoiceTarget {
  @edit_policy.AffectedVoiceTarget(
    pattern_node=self.pattern_node,
    section=self.section,
    layer=self.layer,
    occurrence=self.occurrence,
  )
}

///|
pub fn AffectedVoiceTarget::matches(
  self : AffectedVoiceTarget,
  source : EventSource,
) -> Bool {
  @edit_policy.source_parts_match_target(
    pattern_nodes=source.pattern_nodes,
    section=source.section,
    layer=source.layer,
    occurrence=source.occurrence,
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
  let raw_target = target.to_edit_policy()
  match self.active_notes.get(index) {
    Some(note) => Some(note.matches_edit_policy(raw_target))
    None => None
  }
}

///|
pub fn PatternScheduler::affected_active_note_count(
  self : PatternScheduler,
  target : AffectedVoiceTarget,
) -> Int {
  let raw_target = target.to_edit_policy()
  let count = for note in self.active_notes; total = 0 {
    if note.matches_edit_policy(raw_target) {
      continue total + 1
    }
    continue total
  } nobreak {
    total
  }
  count
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
    Some(stop) => self.remove_affected_notes(raw_target, pool, stop~)
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

///|
fn stop_affected_note(
  handle : @moondsp.VoiceHandle,
  pool : @moondsp.BoundVoicePool,
  stop : @edit_policy.AffectedVoiceStop,
) -> Unit {
  match stop {
    @edit_policy.AffectedVoiceStop::GateOff => ignore(pool.note_off(handle))
    @edit_policy.AffectedVoiceStop::Kill => ignore(pool.kill(handle))
  }
}

///|
fn PatternScheduler::remove_affected_notes(
  self : PatternScheduler,
  target : @edit_policy.AffectedVoiceTarget,
  pool : @moondsp.BoundVoicePool,
  stop~ : @edit_policy.AffectedVoiceStop,
) -> Int {
  let mut count = 0
  let mut i = 0
  while i < self.active_notes.length() {
    if self.active_notes[i].matches_edit_policy(target) {
      stop_affected_note(self.active_notes[i].handle(), pool, stop)
      let last = self.active_notes.length() - 1
      if i < last {
        self.active_notes[i] = self.active_notes[last]
      }
      ignore(self.active_notes.pop())
      count = count + 1
    } else {
      i = i + 1
    }
  }
  count
}
