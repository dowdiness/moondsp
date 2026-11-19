///|
/// Result of applying an active-voice effect, with or without snapshot queuing.
///
/// `retuned_voice_count` counts voices successfully controlled by Retune.
/// `detached_note_count` counts note records removed from scheduler tracking by
/// Release or Kill, not voices destroyed in the pool. Release tails may still
/// sound after detachment. Each effect leaves the other counter at zero.
#derive(Eq, Debug)
pub struct ActiveVoiceEffectOutcome {
  retuned_voice_count : Int32
  detached_note_count : Int32
}

///|
pub extend ActiveVoiceEffectOutcome with Eq::{not_equal, equal}

///|
pub extend ActiveVoiceEffectOutcome with @moonbitlang/core/debug.Debug::{
  to_repr,
}

///|
pub fn PatternScheduler::queue_pattern_snapshot_effect_result(
  self : PatternScheduler,
  snapshot : @pattern.PatternSnapshot,
  scope : PatternVoiceScope,
  effect : ActiveVoiceEffect,
) -> Result[ActiveVoiceEffectOutcome, @moondsp.VoiceControlError] {
  match self.apply_pattern_voice_effect_result(scope, effect) {
    Err(error) => Err(error)
    Ok(outcome) => {
      self.queue_pattern_snapshot(snapshot)
      Ok(outcome)
    }
  }
}

///|
pub fn PatternScheduler::queue_song_snapshot_effect_result(
  self : PatternScheduler,
  snapshot : @song.SongSnapshot,
  scope : SongVoiceScope,
  effect : ActiveVoiceEffect,
) -> Result[ActiveVoiceEffectOutcome, @moondsp.VoiceControlError] {
  match self.apply_song_voice_effect_result(scope, effect) {
    Err(error) => Err(error)
    Ok(outcome) => {
      self.queue_song_snapshot(snapshot)
      Ok(outcome)
    }
  }
}
