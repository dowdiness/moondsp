///|
fn copy_control_events(
  events : Array[@pattern.Event[@pattern.ControlMap]],
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  @voice_runtime.copy_control_events(events)
}

///|
/// Per-voice side-effect extracted from a control map entry.
/// The scheduler applies these after note-on, outside the control binding path.
pub enum VoiceAction {
  SetPan(Double)
}

///|
/// Decouples control key routing from the scheduler's event loop.
///
/// `transform` maps a raw (key, value) pair to an optional (key, value) for the
/// control binding map. Return `None` to drop the entry (e.g. "pan" is consumed
/// as a side-effect, not a DSP control). Return `Some((key, transformed_value))`
/// to include it.
///
/// `voice_action` inspects a raw (key, value) pair and optionally returns a
/// `VoiceAction` to apply after note-on (e.g. `SetPan`).
pub struct ControlMapper {
  transform : (String, Double) -> (String, Double)?
  voice_action : (String, Double) -> VoiceAction?
}

///|
#alias(new)
pub fn ControlMapper::ControlMapper(
  transform~ : (String, Double) -> (String, Double)?,
  voice_action~ : (String, Double) -> VoiceAction?,
) -> ControlMapper {
  { transform, voice_action, }
}

///|
/// Default mapper that preserves the original hardcoded behavior:
/// - "note" values are converted from MIDI note numbers to Hz
/// - "pan" values are extracted as `SetPan` voice actions (not passed to controls)
/// - All other keys pass through unchanged
pub fn default_control_mapper() -> ControlMapper {
  ControlMapper(
    transform=fn(k, v) {
      if k == "pan" {
        None
      } else if k == "note" {
        Some(("note", midi_to_hz(v)))
      } else {
        Some((k, v))
      }
    },
    voice_action=fn(k, v) { if k == "pan" { Some(SetPan(v)) } else { None } },
  )
}

///|
pub struct PatternScheduler {
  priv mut bpm : Double
  priv mut sample_counter : Int64
  priv ctx : @moondsp.DspContext
  // Preserve the historical opaque ActiveNote entry in scheduler/pkg.generated.mbti
  // while scheduler/internal/voice_runtime owns the concrete collection.
  priv active_note_interface_anchor : ActiveNote?
  priv active_notes : @voice_runtime.ActiveNotes
  priv mapper : ControlMapper
  priv playback_state : @playback.PlaybackState
}

///|
#alias(new)
pub fn PatternScheduler::PatternScheduler(
  bpm~ : Double,
  ctx~ : @moondsp.DspContext,
  mapper? : ControlMapper,
) -> PatternScheduler {
  {
    bpm: sanitize_bpm(bpm),
    sample_counter: 0L,
    ctx,
    active_note_interface_anchor: Some(ActiveNote()),
    active_notes: @voice_runtime.ActiveNotes(),
    mapper: mapper.unwrap_or(default_control_mapper()),
    playback_state: @playback.PlaybackState(),
  }
}

///|
/// Gate-off all notes whose end sample has been reached, then remove them.
/// Block-quantized: notes ending mid-block stay active until the next block
/// (~2.7ms at 48kHz/128 samples — inaudible for musical purposes).
pub fn PatternScheduler::expire_notes_at(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  time : PerformanceTime,
) -> Unit {
  self.active_notes.expire_at_sample(pool, time.sample)
}

///|
/// Compatibility wrapper for callers that still expire against a logical arc.
pub fn PatternScheduler::expire_notes(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  arc : @pattern.TimeSpan,
) -> Unit {
  self.expire_notes_at(
    pool,
    PerformanceTime(cycle_to_sample(arc.begin, self.bpm, self.ctx)),
  )
}

///|
/// Process pattern events: sort by onset, trigger note-ons, handle pan.
///
/// In the Strudel/Tidal model, each event has a `whole` span (the note's full
/// intended duration) and a `part` span (the fragment within the query arc).
/// Onset detection uses `whole.begin` — an event fires when its musical start
/// time falls within the current block. Events with `whole = None` are
/// continuous signals (no onset) and are skipped.
pub fn PatternScheduler::process_events(
  self : PatternScheduler,
  events : Array[@pattern.Event[@pattern.ControlMap]],
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  self.process_events_with_origin(
    copy_control_events(events),
    arc,
    pool,
    @model.VoiceOrigin::Anonymous,
  )
}

///|
fn PatternScheduler::process_single_event(
  self : PatternScheduler,
  event : @pattern.Event[@pattern.ControlMap],
  origin : @model.VoiceOrigin,
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  match event.whole {
    None => ()
    Some(whole) =>
      if !arc.contains(whole.begin) {
        ()
      } else {
        let map : Map[String, Double] = {}
        let actions : Array[VoiceAction] = []
        let mapper = self.mapper
        event.value.each(fn(k, v) {
          match (mapper.voice_action)(k, v) {
            Some(action) => actions.push(action)
            None => ()
          }
          match (mapper.transform)(k, v) {
            Some((tk, tv)) => map[tk] = tv
            None => ()
          }
        })
        match pool.note_on_controls(map) {
          None => ()
          Some(handle) => {
            self.active_notes.push_note(
              handle~,
              origin~,
              end_sample=cycle_to_sample(whole.end_, self.bpm, self.ctx),
            )
            for action in actions {
              match action {
                SetPan(pan) => ignore(pool.set_voice_pan_result(handle, pan))
              }
            }
          }
        }
      }
  }
}

///|
fn PatternScheduler::process_events_with_origin(
  self : PatternScheduler,
  events : Array[@pattern.Event[@pattern.ControlMap]],
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
  origin : @model.VoiceOrigin,
) -> Unit {
  if events.length() > 1 {
    events.sort_by(fn(a, b) { @voice_runtime.compare_event_onset(a, b) })
  }
  for event in events {
    self.process_single_event(event, origin, arc, pool)
  }
}

///|
fn PatternScheduler::process_pattern_snapshot_events(
  self : PatternScheduler,
  events : Array[@pattern.PatternSnapshotEvent[@pattern.ControlMap]],
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  if events.length() > 1 {
    events.sort_by(fn(a, b) {
      @voice_runtime.compare_event_onset(a.event(), b.event())
    })
  }
  for sourced in events {
    self.process_single_event(
      sourced.event(),
      @model.VoiceOrigin::Pattern(sourced.pattern_node_path()),
      arc,
      pool,
    )
  }
}

///|
fn PatternScheduler::process_song_snapshot_events(
  self : PatternScheduler,
  events : Array[@song.SongSnapshotEvent[@pattern.ControlMap]],
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  if events.length() > 1 {
    events.sort_by(fn(a, b) {
      @voice_runtime.compare_event_onset(a.event(), b.event())
    })
  }
  for sourced in events {
    self.process_single_event(
      sourced.event(),
      @model.VoiceOrigin::Song(sourced.origin()),
      arc,
      pool,
    )
  }
}

///|
fn PatternScheduler::process_active_snapshot(
  self : PatternScheduler,
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  match self.playback_state.active_snapshot() {
    Some(@playback.PlaybackSnapshot::Pattern(snapshot)) =>
      self.process_pattern_snapshot_events(
        snapshot.query_sourced_events(arc),
        arc,
        pool,
      )
    Some(@playback.PlaybackSnapshot::Song(snapshot)) =>
      self.process_song_snapshot_events(
        snapshot.query_sourced_events(arc),
        arc,
        pool,
      )
    None => ()
  }
}

///|
fn PatternScheduler::query_pattern_block(
  self : PatternScheduler,
  pat : @pattern.Pat[@pattern.ControlMap],
  frame : BlockFrame,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  ignore(self)
  pat.query(frame.logical_arc)
}

///|
fn PatternScheduler::render_block(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  left.fill(0.0)
  right.fill(0.0)
  pool.process(self.ctx, left, right)
}

///|
fn PatternScheduler::process_block_events(
  self : PatternScheduler,
  events : Array[@pattern.Event[@pattern.ControlMap]],
  source : @model.VoiceOrigin,
  frame : BlockFrame,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  self.process_events_with_origin(events, frame.logical_arc, pool, source)
  self.advance_block()
  self.render_block(pool, left, right)
}

///|
/// Main entry point: called once per audio block (128 samples at 48kHz).
/// Computes the cycle-time arc, expires old notes, queries the pattern for
/// new events, triggers voices, advances the sample counter, and renders.
pub fn PatternScheduler::process_block(
  self : PatternScheduler,
  pat : @pattern.Pat[@pattern.ControlMap],
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let frame = self.current_block()
  self.expire_notes_at(pool, PerformanceTime(frame.sample_begin))
  let events = self.query_pattern_block(pat, frame)
  self.process_block_events(
    events,
    @model.VoiceOrigin::Anonymous,
    frame,
    pool,
    left,
    right,
  )
}

///|
/// Unified snapshot entry point for prepared pattern or song playback edits.
/// Pending snapshots are swapped in once at block start; note expiry and event
/// queries then observe the same committed playback state for the whole block.
pub fn PatternScheduler::process_playback_snapshot_block(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let frame = self.current_block()
  self.commit_pending_playback_snapshot()
  self.expire_notes_at(pool, PerformanceTime(frame.sample_begin))
  self.process_active_snapshot(frame.logical_arc, pool)
  self.advance_block()
  self.render_block(pool, left, right)
}

///|
/// Section entry point with section-local timing semantics.
///
/// This intentionally routes through `Section::query` rather than the raw
/// `Section::body()` pattern so non-identity `TimeScope`s affect event timing
/// while keeping the scheduler's logical frame unchanged.
pub fn PatternScheduler::process_section_block(
  self : PatternScheduler,
  section : @song.Section[@pattern.ControlMap],
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let frame = self.current_block()
  self.expire_notes_at(pool, PerformanceTime(frame.sample_begin))
  let events = section.query(frame.logical_arc)
  self.process_block_events(
    events,
    @model.VoiceOrigin::Anonymous,
    frame,
    pool,
    left,
    right,
  )
}

///|
/// Song entry point with song-global layout timing semantics.
///
/// The song layer returns events in song-global logical time, matching the
/// scheduler frame's logical arc.
pub fn PatternScheduler::process_song_block(
  self : PatternScheduler,
  song : @song.Song[@pattern.ControlMap],
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let frame = self.current_block()
  self.expire_notes_at(pool, PerformanceTime(frame.sample_begin))
  let events = song.query(frame.logical_arc)
  self.process_block_events(
    events,
    @model.VoiceOrigin::Anonymous,
    frame,
    pool,
    left,
    right,
  )
}
