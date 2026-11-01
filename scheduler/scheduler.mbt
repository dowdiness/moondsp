///|
fn copy_control_events(
  events : Array[@pattern.Event[@pattern.ControlMap]],
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  @voice_runtime.copy_control_events(events)
}

///|
/// Which events an instrument plays. The scheduler routes each event to the
/// first instrument whose selector matches its controls; an event no
/// instrument selects stays silent.
pub(all) enum InstrumentSelector {
  AllEvents
  HasControl(String)
  ControlEquals(String, Double)
} derive(Eq, Debug)

///|
pub extend InstrumentSelector with Eq::{not_equal, equal}

///|
pub extend InstrumentSelector with @moonbitlang/core/debug.Debug::{to_repr}

///|
fn InstrumentSelector::selects(
  self : InstrumentSelector,
  controls : @pattern.ControlMap,
) -> Bool {
  match self {
    AllEvents => true
    HasControl(key) => controls.get(key) is Some(_)
    ControlEquals(key, expected) =>
      controls.get(key) is Some(v) && v == expected
  }
}

///|
pub struct PatternScheduler {
  priv mut clock : @transport.Clock
  priv mut last_error : @transport.TransportError?
  priv contexts : Array[@moondsp.DspContext]
  priv scratch_left : @moondsp.AudioBuffer
  priv scratch_right : @moondsp.AudioBuffer
  priv scratch_send_left : @moondsp.AudioBuffer
  priv scratch_send_right : @moondsp.AudioBuffer
  priv mut previous_events : Array[@playback.PlaybackSourcedEvent]
  priv mut previous_clock : @transport.Clock
  priv ctx : @moondsp.DspContext
  priv selectors : Array[InstrumentSelector]
  priv pools : Array[@moondsp.BoundVoicePool]
  priv active_notes : @voice_runtime.ActiveNotes
  priv playback_state : @playback.PlaybackState
  priv mut onsets : OnsetBuffer?
}

///|
///
/// `instruments` lists every voice pool this scheduler plays, in routing
/// order. All instruments share one clock, one accepted score, and one mix.
pub fn PatternScheduler::PatternScheduler(
  bpm~ : Double,
  ctx~ : @moondsp.DspContext,
  instruments~ : Array[(InstrumentSelector, @moondsp.BoundVoicePool)],
) -> PatternScheduler raise @transport.TransportError {
  let tempo = @transport.Tempo::from_bpm(bpm).unwrap_or_error()
  let clock = @transport.Clock::at_start(tempo, ctx.sample_rate()).unwrap_or_error()
  if ctx.block_size() <= 0 || ctx.block_size() > 65536 {
    raise @transport.TransportError::TimeOutOfRange
  }
  {
    clock,
    last_error: None,
    contexts: Array::makei(ctx.block_size() + 1, n => {
      @moondsp.DspContext(sample_rate=ctx.sample_rate(), block_size=n)
    }),
    scratch_left: ctx.make_buffer(),
    scratch_right: ctx.make_buffer(),
    scratch_send_left: ctx.make_buffer(),
    scratch_send_right: ctx.make_buffer(),
    previous_events: [],
    previous_clock: clock,
    ctx,
    selectors: instruments.map(instrument => instrument.0),
    pools: instruments.map(instrument => instrument.1),
    active_notes: @voice_runtime.ActiveNotes(),
    playback_state: @playback.PlaybackState(),
    onsets: None,
  }
}

///|
/// Gate-off all notes whose end sample has been reached, then remove them.
/// Block rendering calls this at each event boundary, including note endings.
pub fn PatternScheduler::expire_notes_at(
  self : PatternScheduler,
  time : PerformanceTime,
) -> Unit {
  self.active_notes.expire_at_sample(self.pools, time.sample)
}

///|
/// Expire at a musical position on the current clock.
pub fn PatternScheduler::expire_notes(
  self : PatternScheduler,
  arc : @pattern.TimeSpan,
) -> Result[Unit, TransportError] {
  let sample = match self.clock.sample_at(arc.begin) {
    Ok(sample) => sample
    Err(e) => return Err(e)
  }
  self.expire_notes_at(PerformanceTime(sample))
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
) -> Unit {
  self.process_events_with_origin(
    copy_control_events(events),
    arc,
    @model.VoiceOrigin::Anonymous,
  )
}

///|
fn PatternScheduler::process_single_event(
  self : PatternScheduler,
  event : @pattern.Event[@pattern.ControlMap],
  origin : @model.VoiceOrigin,
  source_origin : @pattern.EventOrigin?,
  source_frame : @identity.SourceFrameId?,
  source_start : Double,
  source_pitch : Double,
  buses : @pattern.EventBuses,
  onset_sample : Int64,
  arc : @pattern.TimeSpan,
) -> Unit {
  let instrument = for i in 0..<self.selectors.length() {
    if self.selectors[i].selects(event.value) {
      break i
    }
  } nobreak {
    return
  }
  let pool = self.pools[instrument]
  match event.whole {
    None => ()
    Some(whole) =>
      if !arc.contains(whole.begin) {
        ()
      } else {
        // The pool's bindings decide what each key sets and in which unit.
        let map : Map[String, Double] = Map([])
        event.value.each(fn(k, v) { map[k] = v })
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
        let follow : Array[(String, (Int64, Int64) -> Double)] = []
        buses.each_reader((key, read) => follow.push((key, read)))
        match pool.note_on_controls(map, follow~) {
          None => ()
          Some(handle) => {
            let musical_end = if gate is AfterSeconds(_) {
              None
            } else {
              Some(whole.end_)
            }
            self.active_notes.push_note(
              instrument~,
              handle~,
              origin~,
              end_sample~,
              musical_end?,
            )
            if onset_sample >= 0L && self.onsets is Some(buffer) {
              buffer.record(
                onset_sample,
                source_origin,
                source_frame~,
                source_start~,
                source_pitch~,
              )
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
  origin : @model.VoiceOrigin,
) -> Unit {
  if events.length() > 1 {
    events.sort_by(fn(a, b) { @voice_runtime.compare_event_onset(a, b) })
  }
  for event in events {
    self.process_single_event(
      event,
      origin,
      None,
      None,
      -1.0,
      -1.0,
      @pattern.EventBuses::none(),
      -1L,
      arc,
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
fn anonymous_playback_events(
  events : Array[@pattern.Event[@pattern.ControlMap]],
) -> Array[@playback.PlaybackSourcedEvent] {
  events.map(event => @playback.PlaybackSourcedEvent::anonymous(event))
}

///|
/// Render to an event boundary using preallocated buffers and contexts.
fn PatternScheduler::render_until(
  self : PatternScheduler,
  cursor : Int64,
  stop : Int64,
  frame : BlockFrame,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
  send_left : @moondsp.AudioBuffer,
  send_right : @moondsp.AudioBuffer,
  write_send : Bool,
) -> Int64 {
  let mut cursor = cursor
  while cursor < stop {
    self.active_notes.expire_at_sample(self.pools, cursor)
    let next = self.active_notes.next_end_sample(stop)
    let count = (next - cursor).to_int()
    let offset = (cursor - frame.sample_begin).to_int()
    // WHY per-instrument scratch: each pool sanitizes its own output, so one
    // instrument's non-finite sample cannot erase another's contribution.
    for pool in self.pools {
      for i in 0..<count {
        self.scratch_left.set(i, 0.0)
        self.scratch_right.set(i, 0.0)
        if write_send {
          self.scratch_send_left.set(i, 0.0)
          self.scratch_send_right.set(i, 0.0)
        }
      }
      if write_send {
        pool.process_with_send(
          self.contexts[count],
          self.scratch_left,
          self.scratch_right,
          self.scratch_send_left,
          self.scratch_send_right,
        )
      } else {
        pool.process(
          self.contexts[count],
          self.scratch_left,
          self.scratch_right,
        )
      }
      for i in 0..<count {
        left.set(offset + i, left.get(offset + i) + self.scratch_left.get(i))
        right.set(offset + i, right.get(offset + i) + self.scratch_right.get(i))
        if write_send {
          send_left.set(
            offset + i,
            send_left.get(offset + i) + self.scratch_send_left.get(i),
          )
          send_right.set(
            offset + i,
            send_right.get(offset + i) + self.scratch_send_right.get(i),
          )
        }
      }
    }
    cursor = next
  }
  self.active_notes.expire_at_sample(self.pools, cursor)
  cursor
}

///|
fn PatternScheduler::process_block_events(
  self : PatternScheduler,
  events : Array[@playback.PlaybackSourcedEvent],
  frame : BlockFrame,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
  send_left : @moondsp.AudioBuffer,
  send_right : @moondsp.AudioBuffer,
  write_send : Bool,
) -> Unit {
  left.fill(0.0)
  right.fill(0.0)
  if write_send {
    send_left.fill(0.0)
    send_right.fill(0.0)
  }
  // Voices started earlier follow their buses from this block's start; a
  // voice starting inside the block begins from its own onset value.
  let at = frame.logical_arc.begin
  for pool in self.pools {
    pool.update_follows(at.num, at.den)
  }
  // Ceil may put a preceding block's final fractional onset at this block's
  // first sample. Retain that query result for one block; never query history.
  for sourced in self.previous_events {
    let event = sourced.event()
    if event.whole is Some(whole) {
      match self.previous_clock.sample_at(whole.begin) {
        Ok(sample) if sample == frame.sample_begin =>
          self.process_single_event(
            event,
            sourced.origin(),
            sourced.source_origin(),
            sourced.source_frame(),
            sourced.source_start(),
            sourced.source_pitch(),
            sourced.buses(),
            frame.sample_begin,
            @pattern.TimeSpan(whole.begin, whole.end_),
          )
        _ => ()
      }
    }
  }
  if events.length() > 1 {
    events.sort_by(fn(a, b) {
      @voice_runtime.compare_event_onset(a.event(), b.event())
    })
  }
  let mut cursor = frame.sample_begin
  for sourced in events {
    let event = sourced.event()
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
      cursor = self.render_until(
        cursor, start, frame, left, right, send_left, send_right, write_send,
      )
      self.process_single_event(
        event,
        sourced.origin(),
        sourced.source_origin(),
        sourced.source_frame(),
        sourced.source_start(),
        sourced.source_pitch(),
        sourced.buses(),
        start,
        frame.logical_arc,
      )
    }
  }
  ignore(
    self.render_until(
      cursor,
      frame.sample_end,
      frame,
      left,
      right,
      send_left,
      send_right,
      write_send,
    ),
  )
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
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let frame = match self.render_frame(left, right) {
    Some(frame) => frame
    None => return
  }
  self.expire_notes_at(PerformanceTime(frame.sample_begin))
  let events = self.query_pattern_block(pat, frame)
  self.process_block_events(
    anonymous_playback_events(events),
    frame,
    left,
    right,
    left,
    right,
    false,
  )
}

///|
/// Render one dry stereo block from the current playback snapshot.
/// A queued replacement is accepted at block start before note expiry and
/// event query. Each successful call advances the transport by one block.
/// Buffers must have at least the configured block size and non-overlapping
/// storage; no caller-side clearing is required. If the next transport frame
/// is unrepresentable, both outputs are silenced, the queued snapshot stays
/// staged, and `last_transport_error()` is set.
pub fn PatternScheduler::render_block(
  self : PatternScheduler,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  self.render_snapshot_outputs(left, right, left, right, false)
}

///|
/// Render one snapshot block into dry stereo and a post-pan, pre-master-gain
/// stereo send. Output buffers must have at least the configured block size
/// and non-overlapping storage. No caller-side clearing is required.
/// If the next transport frame is unrepresentable, all outputs are silenced,
/// the queued snapshot stays staged, and `last_transport_error()` is set.
pub fn PatternScheduler::render_block_with_send(
  self : PatternScheduler,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
  send_left : @moondsp.AudioBuffer,
  send_right : @moondsp.AudioBuffer,
) -> Unit {
  self.render_snapshot_outputs(left, right, send_left, send_right, true)
}

///|
fn PatternScheduler::render_snapshot_outputs(
  self : PatternScheduler,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
  send_left : @moondsp.AudioBuffer,
  send_right : @moondsp.AudioBuffer,
  write_send : Bool,
) -> Unit {
  // Clear sends before frame validation so early failure cannot leak old audio.
  if write_send {
    send_left.fill(0.0)
    send_right.fill(0.0)
  }
  let frame = match self.render_frame(left, right) {
    Some(frame) => frame
    None => return
  }
  self.commit_pending_playback_snapshot()
  self.expire_notes_at(PerformanceTime(frame.sample_begin))
  let events = self.playback_state.query_active_sourced_events(
    frame.logical_arc,
  )
  self.process_block_events(
    events, frame, left, right, send_left, send_right, write_send,
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
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let frame = match self.render_frame(left, right) {
    Some(frame) => frame
    None => return
  }
  self.expire_notes_at(PerformanceTime(frame.sample_begin))
  let events = section.query(frame.logical_arc)
  self.process_block_events(
    anonymous_playback_events(events),
    frame,
    left,
    right,
    left,
    right,
    false,
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
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let frame = match self.render_frame(left, right) {
    Some(frame) => frame
    None => return
  }
  self.expire_notes_at(PerformanceTime(frame.sample_begin))
  let events = song.query(frame.logical_arc)
  self.process_block_events(
    anonymous_playback_events(events),
    frame,
    left,
    right,
    left,
    right,
    false,
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
