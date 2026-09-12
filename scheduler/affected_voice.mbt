///|
pub struct PatternVoiceScope {
  priv raw : @model.PatternVoiceScope
} derive(Eq, Debug)

///|
pub fn PatternVoiceScope::node(
  node : @identity.PatternNodeId,
) -> PatternVoiceScope {
  { raw: @model.PatternVoiceScope(node), }
}

///|
pub struct SongVoiceScope {
  priv raw : @model.SongVoiceScope
} derive(Eq, Debug)

///|
pub fn SongVoiceScope::occurrence(
  occurrence : @identity.OccurrenceId,
) -> SongVoiceScope {
  { raw: @model.SongVoiceScope::Occurrence(occurrence), }
}

///|
pub fn SongVoiceScope::section(section : @identity.SectionId) -> SongVoiceScope {
  { raw: @model.SongVoiceScope::Section(section), }
}

///|
pub fn SongVoiceScope::layer(
  section : @identity.SectionId,
  layer : @identity.SectionLayerId,
) -> SongVoiceScope {
  { raw: @model.SongVoiceScope::Layer(section, layer), }
}

///|
pub struct VoiceControlBatch {
  priv controls : Array[@moondsp.GraphControl]
}

///|
pub fn VoiceControlBatch::VoiceControlBatch(
  first : @moondsp.GraphControl,
  rest? : Array[@moondsp.GraphControl] = [],
) -> VoiceControlBatch {
  let controls = Array(capacity=rest.length() + 1)
  controls.push(first)
  controls.append(rest)
  { controls, }
}

///|
fn VoiceControlBatch::borrow(
  self : VoiceControlBatch,
) -> Array[@moondsp.GraphControl] {
  self.controls
}

///|
pub(all) enum ActiveVoiceEffect {
  Release
  Kill
  Retune(VoiceControlBatch)
}

///|
fn PatternScheduler::apply_matching_voice_effect_result(
  self : PatternScheduler,
  matches : (@model.VoiceOrigin) -> Bool,
  effect : ActiveVoiceEffect,
  pool : @moondsp.BoundVoicePool,
) -> Result[ActiveVoiceEffectOutcome, @moondsp.VoiceControlError] {
  match effect {
    Release =>
      Ok({
        retuned_voice_count: 0,
        detached_note_count: self.active_notes.remove_matching(
          matches,
          pool,
          kill=false,
        ),
      })
    Kill =>
      Ok({
        retuned_voice_count: 0,
        detached_note_count: self.active_notes.remove_matching(
          matches,
          pool,
          kill=true,
        ),
      })
    Retune(batch) => {
      let controls = batch.borrow()
      match
        self.active_notes.try_each_matching(matches, fn(handle) {
          pool.validate_voice_controls_result(handle, controls)
        }) {
        Err(error) => Err(error)
        Ok(_) =>
          match
            self.active_notes.try_count_matching(matches, fn(handle) {
              pool.apply_voice_controls_result(handle, controls)
            }) {
            Err(error) => Err(error)
            Ok(count) =>
              Ok({ retuned_voice_count: count, detached_note_count: 0, })
          }
      }
    }
  }
}

///|
pub fn PatternScheduler::apply_pattern_voice_effect_result(
  self : PatternScheduler,
  scope : PatternVoiceScope,
  effect : ActiveVoiceEffect,
  pool : @moondsp.BoundVoicePool,
) -> Result[ActiveVoiceEffectOutcome, @moondsp.VoiceControlError] {
  self.apply_matching_voice_effect_result(
    source => source.matches_pattern_scope(scope.raw),
    effect,
    pool,
  )
}

///|
pub fn PatternScheduler::apply_song_voice_effect_result(
  self : PatternScheduler,
  scope : SongVoiceScope,
  effect : ActiveVoiceEffect,
  pool : @moondsp.BoundVoicePool,
) -> Result[ActiveVoiceEffectOutcome, @moondsp.VoiceControlError] {
  self.apply_matching_voice_effect_result(
    source => source.matches_song_scope(scope.raw),
    effect,
    pool,
  )
}
