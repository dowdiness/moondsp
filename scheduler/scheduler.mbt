///|
/// Tracks a sounding voice for gate-off scheduling.
struct ActiveNote {
  handle : @moondsp.VoiceHandle
  /// WHY end_time from whole.end_: In the Strudel/Tidal model, `whole` is the
  /// event's full intended duration in cycle time, while `part` is just the
  /// fragment visible within the queried arc. Gate-off uses `whole.end_`
  /// because that represents the musical note boundary, not the query window.
  end_time : @pattern.Rational
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

  fn new(
    transform~ : (String, Double) -> (String, Double)?,
    voice_action~ : (String, Double) -> VoiceAction?,
  ) -> ControlMapper
}

///|
pub fn ControlMapper::new(
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
  mut bpm : Double
  mut sample_counter : Int64
  ctx : @moondsp.DspContext
  active_notes : Array[ActiveNote]
  bindings : @moondsp.ControlBindingMap
  mapper : ControlMapper

  fn new(
    bpm~ : Double,
    bindings~ : @moondsp.ControlBindingMap,
    ctx~ : @moondsp.DspContext,
    mapper? : ControlMapper,
  ) -> PatternScheduler
}

///|
/// Reject NaN/Inf and clamp to minimum 1.0 BPM.
fn sanitize_bpm(bpm : Double) -> Double {
  if bpm.is_nan() || bpm.is_inf() || bpm < 1.0 {
    1.0
  } else {
    bpm
  }
}

///|
pub fn PatternScheduler::new(
  bpm~ : Double,
  bindings~ : @moondsp.ControlBindingMap,
  ctx~ : @moondsp.DspContext,
  mapper? : ControlMapper,
) -> PatternScheduler {
  {
    bpm: sanitize_bpm(bpm),
    sample_counter: 0L,
    ctx,
    active_notes: [],
    bindings,
    mapper: mapper.unwrap_or(default_control_mapper()),
  }
}

///|
pub fn PatternScheduler::sample_counter(self : PatternScheduler) -> Int64 {
  self.sample_counter
}

///|
pub fn PatternScheduler::active_note_count(self : PatternScheduler) -> Int {
  self.active_notes.length()
}

///|
/// Update tempo in-place. Active notes continue with existing gate-off times —
/// those cycle positions simply arrive faster/slower with the new BPM.
pub fn PatternScheduler::set_bpm(self : PatternScheduler, bpm : Double) -> Unit {
  self.bpm = sanitize_bpm(bpm)
}

///|
/// Convert MIDI note number to frequency in Hz.
/// Uses equal temperament: A4 (MIDI 69) = 440 Hz, each semitone is 2^(1/12).
pub fn midi_to_hz(midi : Double) -> Double {
  440.0 * @math.pow(2.0, (midi - 69.0) / 12.0)
}

///|
/// Test helper: inject an active note for testing gate-off logic.
/// The caller must ensure the VoiceHandle is currently active in the pool,
/// or gate-off at expiry will silently no-op (note_off returns false).
pub fn PatternScheduler::push_active_note(
  self : PatternScheduler,
  handle : @moondsp.VoiceHandle,
  end_time : @pattern.Rational,
) -> Unit {
  self.active_notes.push({ handle, end_time })
}

///|
/// Gate-off all notes whose end_time has been reached, then remove them.
/// Block-quantized: notes ending mid-block stay active until the next block
/// (~2.7ms at 48kHz/128 samples — inaudible for musical purposes).
pub fn PatternScheduler::expire_notes(
  self : PatternScheduler,
  pool : @moondsp.VoicePool,
  arc : @pattern.TimeSpan,
) -> Unit {
  let mut i = 0
  while i < self.active_notes.length() {
    if self.active_notes[i].end_time <= arc.begin {
      ignore(pool.note_off(self.active_notes[i].handle))
      // WHY swap-remove: Array::remove shifts all later elements O(n).
      // Swap with last + pop is O(1). Order of active_notes doesn't matter
      // because gate-off correctness depends only on end_time, not position.
      let last = self.active_notes.length() - 1
      if i < last {
        self.active_notes[i] = self.active_notes[last]
      }
      ignore(self.active_notes.pop())
    } else {
      i = i + 1
    }
  }
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
  pool : @moondsp.VoicePool,
) -> Unit {
  // Sort by onset for deterministic voice allocation.
  // None-whole events sort last but are always skipped below.
  if events.length() > 1 {
    events.sort_by(fn(a, b) {
      match (a.whole, b.whole) {
        (Some(wa), Some(wb)) => wa.begin.compare(wb.begin)
        (Some(_), None) => -1
        (None, Some(_)) => 1
        (None, None) => 0
      }
    })
  }
  for i = 0; i < events.length(); i = i + 1 {
    let event = events[i]
    match event.whole {
      None => continue i + 1
      Some(whole) => {
        if !arc.contains(whole.begin) {
          continue i + 1
        }
        // WHY fresh map: process_events takes Array[Event] so callers may
        // reuse event arrays across calls. Building a fresh map avoids
        // mutating the original ControlMap. The ControlMapper transforms
        // values (e.g. MIDI→Hz) and extracts per-voice actions (e.g. pan).
        let raw_controls = event.value.0
        let map : Map[String, Double] = {}
        let actions : Array[VoiceAction] = []
        let mapper = self.mapper
        raw_controls.each(fn(k, v) {
          match (mapper.voice_action)(k, v) {
            Some(action) => actions.push(action)
            None => ()
          }
          match (mapper.transform)(k, v) {
            Some((tk, tv)) => map[tk] = tv
            None => ()
          }
        })
        let controls = self.bindings.resolve_controls(map)
        match pool.note_on(controls) {
          None => ()
          Some(handle) => {
            self.active_notes.push({ handle, end_time: whole.end_ })
            for action in actions {
              match action {
                SetPan(pan) => ignore(pool.set_voice_pan(handle, pan))
              }
            }
          }
        }
      }
    }
  }
}

///|
/// Main entry point: called once per audio block (128 samples at 48kHz).
/// Computes the cycle-time arc, expires old notes, queries the pattern for
/// new events, triggers voices, advances the sample counter, and renders.
pub fn PatternScheduler::process_block(
  self : PatternScheduler,
  pat : @pattern.Pat[@pattern.ControlMap],
  pool : @moondsp.VoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let arc = compute_arc(self.sample_counter, self.bpm, self.ctx)
  self.expire_notes(pool, arc)
  let events = pat.query(arc)
  self.process_events(events, arc, pool)
  self.sample_counter = self.sample_counter + self.ctx.block_size().to_int64()
  left.fill(0.0)
  right.fill(0.0)
  pool.process(self.ctx, left, right)
}

///|
/// Derive the cycle-time arc for a block from the integer sample counter.
///
/// At BPM, one cycle lasts 60/BPM seconds. The formula
/// `sample_counter * bpm / (sample_rate * 60)` gives the cycle position —
/// how many cycles have elapsed since playback started. Using Rational
/// arithmetic keeps this exact (no floating-point drift). Denominators are
/// bounded by `sample_rate * 60` (e.g. 2,880,000 for 48kHz).
pub fn compute_arc(
  sample_counter : Int64,
  bpm : Double,
  ctx : @moondsp.DspContext,
) -> @pattern.TimeSpan {
  // WHY scale by 10: BPM is a Double but Rational needs Int64. Multiplying
  // by 10 preserves one decimal place (120.5 → 1205) which covers all
  // standard tempos. The denominator becomes sample_rate * 600 instead of
  // sample_rate * 60 — still well within Int64 range.
  let bpm_scaled = (bpm * 10.0).to_int64()
  let sr600 = ctx.sample_rate().to_int().to_int64() * 600L
  let block_size = ctx.block_size().to_int64()
  let arc_start = @pattern.Rational::new(sample_counter * bpm_scaled, sr600)
  let arc_end = @pattern.Rational::new(
    (sample_counter + block_size) * bpm_scaled,
    sr600,
  )
  @pattern.TimeSpan::new(arc_start, arc_end)
}
