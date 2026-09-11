///|
fn copy_control_events(
  events : Array[@pattern.Event[@pattern.ControlMap]],
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  @voice_runtime.copy_control_events(events)
}

///|
fn copy_playback_events(events : Array[PlaybackEvent]) -> Array[PlaybackEvent] {
  events.copy()
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
  { transform, voice_action }
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
      } else if k == "attack" || k == "release" {
        Some((k, v * 1000.0))
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
  priv mut clock : @transport.Clock
  priv mut last_error : @transport.TransportError?
  priv contexts : Array[@moondsp.DspContext]
  priv scratch_left : @moondsp.AudioBuffer
  priv scratch_right : @moondsp.AudioBuffer
  priv mut previous_events : Array[@pattern.Event[@pattern.ControlMap]]
  priv mut previous_clock : @transport.Clock
  priv ctx : @moondsp.DspContext
  priv active_notes : @voice_runtime.ActiveNotes
  priv mapper : ControlMapper
  priv playback_state : @playback.PlaybackState
}

///|
pub fn PatternScheduler::new(
  bpm~ : Double,
  ctx~ : @moondsp.DspContext,
  mapper? : ControlMapper,
) -> Result[PatternScheduler, @transport.TransportError] {
  let tempo = match @transport.Tempo::from_bpm(bpm) {
    Ok(tempo) => tempo
    Err(e) => return Err(e)
  }
  let clock = match @transport.Clock::at_start(tempo, ctx.sample_rate()) {
    Ok(clock) => clock
    Err(e) => return Err(e)
  }
  if ctx.block_size() <= 0 || ctx.block_size() > 65536 {
    return Err(@transport.TransportError::TimeOutOfRange)
  }
  Ok({
    clock,
    last_error: None,
    contexts: Array::makei(ctx.block_size() + 1, n => {
      @moondsp.DspContext(sample_rate=ctx.sample_rate(), block_size=n)
    }),
    scratch_left: ctx.make_buffer(),
    scratch_right: ctx.make_buffer(),
    previous_events: [],
    previous_clock: clock,
    ctx,
    active_notes: @voice_runtime.ActiveNotes(),
    mapper: mapper.unwrap_or(default_control_mapper()),
    playback_state: @playback.PlaybackState(),
  })
}

///|
/// Gate-off all notes whose end sample has been reached, then remove them.
/// Block rendering calls this at each event boundary, including note endings.
pub fn PatternScheduler::expire_notes_at(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  time : PerformanceTime,
) -> Unit {
  self.active_notes.expire_at_sample(pool, time.sample)
}

///|
/// Expire at a musical position on the current clock.
pub fn PatternScheduler::expire_notes(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  arc : @pattern.TimeSpan,
) -> Result[Unit, TransportError] {
  let sample = match self.clock.sample_at(arc.begin) {
    Ok(sample) => sample
    Err(e) => return Err(e)
  }
  self.expire_notes_at(pool, PerformanceTime(sample))
  Ok(())
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
  self.process_events_with_source(
    copy_control_events(events),
    arc,
    pool,
    EventSource::none(),
  )
}

///|
fn PatternScheduler::process_single_event(
  self : PatternScheduler,
  event : @pattern.Event[@pattern.ControlMap],
  source : EventSource,
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  match event.whole {
    None => ()
    Some(whole) =>
      if !arc.contains(whole.begin) {
        ()
      } else {
        // WHY fresh map: process_events takes Array[Event] so callers may
        // reuse event arrays across calls. Building a fresh map avoids
        // mutating the original ControlMap. The ControlMapper transforms
        // values (e.g. MIDI→Hz) and extracts per-voice actions (e.g. pan).
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
        let gate = pool.note_gate(map)
        let endpoint = match gate {
          EventEnd => self.clock.sample_at(whole.end_)
          AfterSeconds(seconds) =>
            physical_gate_end(
              self.clock,
              whole.begin,
              seconds,
              self.ctx.sample_rate(),
            )
          InvalidDuration => Err(@transport.TransportError::TimeOutOfRange)
        }
        let end_sample = match endpoint {
          Ok(sample) => sample
          Err(e) => {
            self.last_error = Some(e)
            return
          }
        }
        match pool.note_on_controls(map) {
          None => ()
          Some(handle) => {
            let musical_end = if gate is AfterSeconds(_) {
              None
            } else {
              Some(whole.end_)
            }
            self.active_notes.push_note(
              handle~,
              source=source.to_model(),
              end_sample~,
              musical_end?,
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
fn PatternScheduler::process_events_with_source(
  self : PatternScheduler,
  events : Array[@pattern.Event[@pattern.ControlMap]],
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
  source : EventSource,
) -> Unit {
  // Sort by onset for deterministic voice allocation.
  // None-whole events sort last but are always skipped below.
  if events.length() > 1 {
    events.sort_by(fn(a, b) { @voice_runtime.compare_event_onset(a, b) })
  }
  for i in 0..<events.length() {
    self.process_single_event(events[i], source, arc, pool)
  }
}

///|
pub fn PatternScheduler::process_playback_events(
  self : PatternScheduler,
  events : Array[PlaybackEvent],
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  self.process_owned_playback_events(copy_playback_events(events), arc, pool)
}

///|
fn PatternScheduler::process_owned_playback_events(
  self : PatternScheduler,
  events : Array[PlaybackEvent],
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  // Sort by onset for deterministic voice allocation.
  // None-whole events sort last but are always skipped below.
  if events.length() > 1 {
    events.sort_by(fn(a, b) {
      @voice_runtime.compare_event_onset(a.event(), b.event())
    })
  }
  for i in 0..<events.length() {
    let playback_event = events[i]
    self.process_single_event(
      playback_event.event(),
      playback_event.source(),
      arc,
      pool,
    )
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
fn PatternScheduler::query_snapshot_block(
  self : PatternScheduler,
  frame : BlockFrame,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  self.playback_state.query_active_events(frame.logical_arc)
}

///|
/// Render to an event boundary using preallocated buffers and contexts.
fn PatternScheduler::render_until(
  self : PatternScheduler,
  cursor : Int64,
  stop : Int64,
  frame : BlockFrame,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Int64 {
  let mut cursor = cursor
  while cursor < stop {
    self.active_notes.expire_at_sample(pool, cursor)
    let next = self.active_notes.next_end_sample(stop)
    let count = (next - cursor).to_int()
    for i in 0..<count {
      self.scratch_left.set(i, 0.0)
      self.scratch_right.set(i, 0.0)
    }
    pool.process(self.contexts[count], self.scratch_left, self.scratch_right)
    let offset = (cursor - frame.sample_begin).to_int()
    for i in 0..<count {
      left.set(offset + i, self.scratch_left.get(i))
      right.set(offset + i, self.scratch_right.get(i))
    }
    cursor = next
  }
  self.active_notes.expire_at_sample(pool, cursor)
  cursor
}

///|
fn PatternScheduler::process_block_events(
  self : PatternScheduler,
  events : Array[@pattern.Event[@pattern.ControlMap]],
  source : EventSource,
  frame : BlockFrame,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  left.fill(0.0)
  right.fill(0.0)
  // Ceil may put a preceding block's final fractional onset at this block's
  // first sample. Retain that query result for one block; never query history.
  for event in self.previous_events {
    if event.whole is Some(whole) {
      match self.previous_clock.sample_at(whole.begin) {
        Ok(sample) if sample == frame.sample_begin =>
          self.process_single_event(
            event,
            source,
            @pattern.TimeSpan::new(whole.begin, whole.end_),
            pool,
          )
        _ => ()
      }
    }
  }
  if events.length() > 1 {
    events.sort_by(fn(a, b) { @voice_runtime.compare_event_onset(a, b) })
  }
  let mut cursor = frame.sample_begin
  for event in events {
    if event.whole is Some(whole) {
      if !frame.logical_arc.contains(whole.begin) {
        continue
      }
      let start = match self.clock.sample_at(whole.begin) {
        Ok(sample) => sample
        Err(e) => {
          self.last_error = Some(e)
          continue
        }
      }
      if start < cursor || start >= frame.sample_end {
        continue
      }
      cursor = self.render_until(cursor, start, frame, pool, left, right)
      self.process_single_event(event, source, frame.logical_arc, pool)
    }
  }
  ignore(self.render_until(cursor, frame.sample_end, frame, pool, left, right))
  self.previous_events = events
  self.previous_clock = self.clock
  self.advance_block()
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
  let frame = match self.render_frame(pool, left, right) {
    Some(frame) => frame
    None => return
  }
  self.expire_notes_at(pool, PerformanceTime(frame.sample_begin))
  let events = self.query_pattern_block(pat, frame)
  self.process_block_events(
    events,
    EventSource::none(),
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
  let frame = match self.render_frame(pool, left, right) {
    Some(frame) => frame
    None => return
  }
  self.commit_pending_playback_snapshot()
  self.expire_notes_at(pool, PerformanceTime(frame.sample_begin))
  let events = self.query_snapshot_block(frame)
  self.process_block_events(
    events,
    EventSource::none(),
    frame,
    pool,
    left,
    right,
  )
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
  let frame = match self.render_frame(pool, left, right) {
    Some(frame) => frame
    None => return
  }
  self.expire_notes_at(pool, PerformanceTime(frame.sample_begin))
  let events = section.query(frame.logical_arc)
  self.process_block_events(
    events,
    EventSource::none(),
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
  let frame = match self.render_frame(pool, left, right) {
    Some(frame) => frame
    None => return
  }
  self.expire_notes_at(pool, PerformanceTime(frame.sample_begin))
  let events = song.query(frame.logical_arc)
  self.process_block_events(
    events,
    EventSource::none(),
    frame,
    pool,
    left,
    right,
  )
}

///|
/// Convert a note-local physical duration without attaching it to musical tempo.
fn physical_gate_end(
  clock : @transport.Clock,
  onset : @pattern.Rational,
  seconds : Double,
  sample_rate : Double,
) -> Result[Int64, @transport.TransportError] {
  if seconds.is_nan() || seconds.is_inf() || seconds < 0.0 || seconds > 172800.0 {
    return Err(@transport.TransportError::TimeOutOfRange)
  }
  let start = match clock.sample_at(onset) {
    Ok(sample) => sample
    Err(error) => return Err(error)
  }
  let exact = seconds * sample_rate
  let truncated = exact.to_int64()
  let samples = if truncated.to_double() < exact {
    truncated + 1L
  } else {
    truncated
  }
  if start > 9223372036854775807L - samples {
    return Err(@transport.TransportError::TimeOutOfRange)
  }
  Ok(start + samples)
}
