///|
pub struct PatternVoiceScope {
  priv raw : @model.PatternVoiceScope
} derive(Eq, Debug)

///|
pub extend PatternVoiceScope with Eq::{not_equal, equal}

///|
pub extend PatternVoiceScope with @moonbitlang/core/debug.Debug::{to_repr}

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
pub extend SongVoiceScope with Eq::{not_equal, equal}

///|
pub extend SongVoiceScope with @moonbitlang/core/debug.Debug::{to_repr}

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
/// Graph controls for the voices of one instrument: node indices only mean
/// something for that instrument's graph.
pub struct VoiceControlBatch {
  priv instrument : Int
  priv controls : Array[@moondsp.GraphControl]
}

///|
/// `instrument` is an index into the scheduler's instrument list.
pub fn VoiceControlBatch::VoiceControlBatch(
  instrument~ : Int,
  first : @moondsp.GraphControl,
  rest? : Array[@moondsp.GraphControl] = [],
) -> VoiceControlBatch {
  let controls = Array(capacity=rest.length() + 1)
  controls.push(first)
  controls.append(rest)
  { instrument, controls, }
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
) -> Result[ActiveVoiceEffectOutcome, @moondsp.VoiceControlError] {
  match effect {
    Release =>
      Ok({
        retuned_voice_count: 0,
        detached_note_count: self.active_notes.remove_matching(
          matches,
          self.pools,
          kill=false,
        ),
      })
    Kill =>
      Ok({
        retuned_voice_count: 0,
        detached_note_count: self.active_notes.remove_matching(
          matches,
          self.pools,
          kill=true,
        ),
      })
    Retune(batch) => {
      let voices = self.active_notes.matching_voices(
        matches,
        batch.instrument,
        self.pools,
      )
      match @moondsp.apply_controls_to_voices(voices, batch.borrow()) {
        Err(error) => Err(error)
        Ok(_) =>
          Ok({ retuned_voice_count: voices.length(), detached_note_count: 0, })
      }
    }
  }
}

///|
pub fn PatternScheduler::apply_pattern_voice_effect_result(
  self : PatternScheduler,
  scope : PatternVoiceScope,
  effect : ActiveVoiceEffect,
) -> Result[ActiveVoiceEffectOutcome, @moondsp.VoiceControlError] {
  self.apply_matching_voice_effect_result(
    source => source.matches_pattern_scope(scope.raw),
    effect,
  )
}

///|
pub fn PatternScheduler::apply_song_voice_effect_result(
  self : PatternScheduler,
  scope : SongVoiceScope,
  effect : ActiveVoiceEffect,
) -> Result[ActiveVoiceEffectOutcome, @moondsp.VoiceControlError] {
  self.apply_matching_voice_effect_result(
    source => source.matches_song_scope(scope.raw),
    effect,
  )
}
