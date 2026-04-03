///|
/// Tracks a sounding voice for gate-off scheduling.
struct ActiveNote {
  handle : @lib.VoiceHandle
  end_time : @pattern.Rational
}

///|
pub struct PatternScheduler {
  bpm : Double
  mut sample_counter : Int64
  sample_rate : Int
  block_size : Int
  active_notes : Array[ActiveNote]
  bindings : @lib.ControlBindingMap

  fn new(
    bpm~ : Double,
    bindings~ : @lib.ControlBindingMap,
    ctx~ : @lib.DspContext,
  ) -> PatternScheduler
}

///|
pub fn PatternScheduler::new(
  bpm~ : Double,
  bindings~ : @lib.ControlBindingMap,
  ctx~ : @lib.DspContext,
) -> PatternScheduler {
  {
    bpm,
    sample_counter: 0L,
    sample_rate: ctx.sample_rate().to_int(),
    block_size: ctx.block_size(),
    active_notes: [],
    bindings,
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
pub fn midi_to_hz(midi : Double) -> Double {
  440.0 * Double::pow(2.0, (midi - 69.0) / 12.0)
}

///|
/// Test helper: inject an active note for testing gate-off logic.
pub fn PatternScheduler::push_active_note(
  self : PatternScheduler,
  handle : @lib.VoiceHandle,
  end_time : @pattern.Rational,
) -> Unit {
  self.active_notes.push({ handle, end_time })
}

///|
/// Gate-off all notes whose end_time <= arc.begin, then remove them.
/// Block-quantized: notes ending mid-block stay active until the next block.
pub fn PatternScheduler::expire_notes(
  self : PatternScheduler,
  pool : @lib.VoicePool,
  arc : @pattern.TimeSpan,
) -> Unit {
  let mut i = 0
  while i < self.active_notes.length() {
    if self.active_notes[i].end_time <= arc.begin {
      ignore(pool.note_off(self.active_notes[i].handle))
      ignore(self.active_notes.remove(i))
    } else {
      i = i + 1
    }
  }
}

///|
/// Process pattern events: sort by onset, trigger note-ons, handle pan.
/// Events with no `whole` or whose onset is outside the arc are skipped.
pub fn PatternScheduler::process_events(
  self : PatternScheduler,
  events : Array[@pattern.Event[@pattern.ControlMap]],
  arc : @pattern.TimeSpan,
  pool : @lib.VoicePool,
) -> Unit {
  // Sort by onset time for deterministic voice allocation
  events.sort_by(fn(a, b) {
    match (a.whole, b.whole) {
      (Some(wa), Some(wb)) => wa.begin.compare(wb.begin)
      (Some(_), None) => -1
      (None, Some(_)) => 1
      (None, None) => 0
    }
  })
  for i = 0; i < events.length(); i = i + 1 {
    let event = events[i]
    match event.whole {
      None => continue i + 1
      Some(whole) => {
        if !arc.contains(whole.begin) {
          continue i + 1
        }
        // Extract inner map from ControlMap newtype
        let map = event.value.0
        // Convert MIDI note to Hz if present
        match map.get("note") {
          Some(midi) => map["note"] = midi_to_hz(midi)
          None => ()
        }
        // Extract and remove pan before resolve_controls
        let pan_value = map.get("pan")
        match pan_value {
          Some(_) => map.remove("pan")
          None => ()
        }
        // Resolve remaining controls through bindings
        let controls = self.bindings.resolve_controls(map)
        // Trigger voice
        match pool.note_on(controls) {
          None => () // silent skip
          Some(handle) => {
            self.active_notes.push({ handle, end_time: whole.end_ })
            // Apply per-voice pan if present
            match pan_value {
              Some(pan) => ignore(pool.set_voice_pan(handle, pan))
              None => ()
            }
          }
        }
      }
    }
  }
}

///|
/// Main entry point: called once per audio block.
/// 1. Compute block arc from sample counter
/// 2. Gate-off expired notes
/// 3. Query pattern
/// 4. Process note-ons (sorted, with pan and MIDI→Hz)
/// 5. Advance sample counter
/// 6. Zero buffers and render audio
pub fn PatternScheduler::process_block(
  self : PatternScheduler,
  pat : @pattern.Pat[@pattern.ControlMap],
  pool : @lib.VoicePool,
  ctx : @lib.DspContext,
  left : @lib.AudioBuffer,
  right : @lib.AudioBuffer,
) -> Unit {
  // Step 1: compute block arc
  let arc = compute_arc(
    self.sample_counter,
    self.bpm,
    self.sample_rate,
    self.block_size,
  )
  // Step 2: gate-off expired notes
  self.expire_notes(pool, arc)
  // Step 3: query pattern
  let events = pat.query(arc)
  // Step 4: process note-ons
  self.process_events(events, arc, pool)
  // Step 5: advance sample counter
  self.sample_counter = self.sample_counter + self.block_size.to_int64()
  // Step 6: zero buffers and render
  left.fill(0.0)
  right.fill(0.0)
  pool.process(ctx, left, right)
}

///|
/// Derive the cycle-time arc for a block from the integer sample counter.
/// Denominators are bounded by sample_rate * 60 — no overflow risk for
/// practical session lengths with Int64 numerators.
pub fn compute_arc(
  sample_counter : Int64,
  bpm : Double,
  sample_rate : Int,
  block_size : Int,
) -> @pattern.TimeSpan {
  let bpm_int = bpm.to_int().to_int64()
  let sr60 = sample_rate.to_int64() * 60L
  let arc_start = @pattern.Rational::new(sample_counter * bpm_int, sr60)
  let arc_end = @pattern.Rational::new(
    (sample_counter + block_size.to_int64()) * bpm_int,
    sr60,
  )
  @pattern.TimeSpan::new(arc_start, arc_end)
}
