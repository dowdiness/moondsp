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
pub fn AffectedVoiceTarget::matches(
  self : AffectedVoiceTarget,
  source : EventSource,
) -> Bool {
  if self.is_empty() {
    return false
  }
  let pattern_matches = match self.pattern_node {
    Some(id) => source.has_pattern_node(id)
    None => true
  }
  let section_matches = match self.section {
    Some(id) => source.section == Some(id)
    None => true
  }
  let layer_matches = match self.layer {
    Some(id) => source.layer == Some(id)
    None => true
  }
  let occurrence_matches = match self.occurrence {
    Some(id) => source.occurrence == Some(id)
    None => true
  }
  pattern_matches && section_matches && layer_matches && occurrence_matches
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
priv enum AffectedVoiceStop {
  GateOff
  Kill
}

///|
pub fn PatternScheduler::active_note_matches(
  self : PatternScheduler,
  index : Int,
  target : AffectedVoiceTarget,
) -> Bool? {
  match self.active_notes.get(index) {
    Some(note) => Some(note.source.matches(target))
    None => None
  }
}

///|
pub fn PatternScheduler::affected_active_note_count(
  self : PatternScheduler,
  target : AffectedVoiceTarget,
) -> Int {
  let mut count = 0
  for note in self.active_notes {
    if note.source.matches(target) {
      count = count + 1
    }
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
  if target.is_empty() {
    return 0
  }
  match policy {
    LetRing => 0
    GateOffAffected => self.remove_affected_notes(target, pool, stop=GateOff)
    KillAffected => self.remove_affected_notes(target, pool, stop=Kill)
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
  stop : AffectedVoiceStop,
) -> Unit {
  match stop {
    GateOff => ignore(pool.note_off(handle))
    Kill => ignore(pool.kill(handle))
  }
}

///|
fn PatternScheduler::remove_affected_notes(
  self : PatternScheduler,
  target : AffectedVoiceTarget,
  pool : @moondsp.BoundVoicePool,
  stop~ : AffectedVoiceStop,
) -> Int {
  let mut count = 0
  let mut i = 0
  while i < self.active_notes.length() {
    if self.active_notes[i].source.matches(target) {
      stop_affected_note(self.active_notes[i].handle, pool, stop)
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
