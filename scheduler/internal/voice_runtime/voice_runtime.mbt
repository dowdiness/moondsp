///|
/// Scheduler-owned active voice with its performance-sample gate-off time.
priv struct ActiveNote {
  handle : @voice.VoiceHandle
  source : @model.EventSource
  end_sample : Int64
}

///|
fn ActiveNote::ActiveNote(
  handle~ : @voice.VoiceHandle,
  source~ : @model.EventSource,
  end_sample~ : Int64,
) -> ActiveNote {
  { handle, source, end_sample }
}

///|
fn ActiveNote::handle(self : ActiveNote) -> @voice.VoiceHandle {
  self.handle
}

///|
fn ActiveNote::source(self : ActiveNote) -> @model.EventSource {
  self.source
}

///|
fn ActiveNote::matches_edit_policy(
  self : ActiveNote,
  target : @edit_policy.AffectedVoiceTarget,
) -> Bool {
  let source = self.source
  @edit_policy.source_parts_match_target(
    pattern_nodes=source.borrow_pattern_nodes(),
    section=source.section(),
    layer=source.layer(),
    occurrence=source.occurrence(),
    target,
  )
}

///|
fn ActiveNote::expires_at(self : ActiveNote, sample : Int64) -> Bool {
  self.end_sample <= sample
}

///|
fn ActiveNote::note_off(
  self : ActiveNote,
  pool : @voice.BoundVoicePool,
) -> Unit {
  ignore(pool.note_off_result(self.handle))
}

///|
fn ActiveNote::kill(self : ActiveNote, pool : @voice.BoundVoicePool) -> Unit {
  ignore(pool.kill_result(self.handle))
}

///|
/// Scheduler-owned collection of active voice records.
pub struct ActiveNotes {
  priv notes : Array[ActiveNote]
}

///|
pub fn ActiveNotes::ActiveNotes() -> ActiveNotes {
  { notes: [] }
}

///|
pub fn ActiveNotes::length(self : ActiveNotes) -> Int {
  self.notes.length()
}

///|
pub fn ActiveNotes::source(
  self : ActiveNotes,
  index : Int,
) -> @model.EventSource? {
  match self.notes.get(index) {
    Some(note) => Some(note.source())
    None => None
  }
}

///|
pub fn ActiveNotes::push_note(
  self : ActiveNotes,
  handle~ : @voice.VoiceHandle,
  source~ : @model.EventSource,
  end_sample~ : Int64,
) -> Unit {
  self.notes.push(ActiveNote(handle~, source~, end_sample~))
}

///|
pub fn ActiveNotes::clear(self : ActiveNotes) -> Unit {
  self.notes.clear()
}

///|
pub fn ActiveNotes::kill_all(
  self : ActiveNotes,
  pool : @voice.BoundVoicePool,
) -> Unit {
  for note in self.notes {
    note.kill(pool)
  }
}

///|
pub fn ActiveNotes::expire_at_sample(
  self : ActiveNotes,
  pool : @voice.BoundVoicePool,
  sample : Int64,
) -> Unit {
  let mut i = 0
  while i < self.notes.length() {
    if self.notes[i].expires_at(sample) {
      self.notes[i].note_off(pool)
      // WHY swap-remove: Array::remove shifts all later elements O(n).
      // Swap with last + pop is O(1). Active-note order is not observable;
      // gate-off correctness depends only on end_sample, not position.
      let last = self.notes.length() - 1
      if i < last {
        self.notes[i] = self.notes[last]
      }
      ignore(self.notes.pop())
    } else {
      i = i + 1
    }
  }
}

///|
pub fn ActiveNotes::matches_edit_policy(
  self : ActiveNotes,
  index : Int,
  target : @edit_policy.AffectedVoiceTarget,
) -> Bool? {
  match self.notes.get(index) {
    Some(note) => Some(note.matches_edit_policy(target))
    None => None
  }
}

///|
pub fn ActiveNotes::affected_count(
  self : ActiveNotes,
  target : @edit_policy.AffectedVoiceTarget,
) -> Int {
  for note in self.notes; total = 0 {
    if note.matches_edit_policy(target) {
      continue total + 1
    }
    continue total
  } nobreak {
    total
  }
}

///|
fn stop_affected_note(
  handle : @voice.VoiceHandle,
  pool : @voice.BoundVoicePool,
  stop : @edit_policy.AffectedVoiceStop,
) -> Unit {
  match stop {
    @edit_policy.AffectedVoiceStop::GateOff =>
      ignore(pool.note_off_result(handle))
    @edit_policy.AffectedVoiceStop::Kill => ignore(pool.kill_result(handle))
  }
}

///|
pub fn ActiveNotes::remove_affected(
  self : ActiveNotes,
  target : @edit_policy.AffectedVoiceTarget,
  pool : @voice.BoundVoicePool,
  stop~ : @edit_policy.AffectedVoiceStop,
) -> Int {
  let mut count = 0
  let mut i = 0
  while i < self.notes.length() {
    if self.notes[i].matches_edit_policy(target) {
      stop_affected_note(self.notes[i].handle(), pool, stop)
      let last = self.notes.length() - 1
      if i < last {
        self.notes[i] = self.notes[last]
      }
      ignore(self.notes.pop())
      count = count + 1
    } else {
      i = i + 1
    }
  }
  count
}

///|
pub fn[E] ActiveNotes::try_each_matching_handle(
  self : ActiveNotes,
  target : @edit_policy.AffectedVoiceTarget,
  f : (@voice.VoiceHandle) -> Result[Unit, E],
) -> Result[Unit, E] {
  for note in self.notes {
    if note.matches_edit_policy(target) {
      match f(note.handle()) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    }
  }
  Ok(())
}

///|
pub fn[E] ActiveNotes::try_count_matching_handles(
  self : ActiveNotes,
  target : @edit_policy.AffectedVoiceTarget,
  f : (@voice.VoiceHandle) -> Result[Unit, E],
) -> Result[Int, E] {
  let count = for note in self.notes; count = 0 {
    if note.matches_edit_policy(target) {
      match f(note.handle()) {
        Ok(_) => continue count + 1
        Err(error) => return Err(error)
      }
    }
    continue count
  } nobreak {
    count
  }
  Ok(count)
}

///|
/// Convert MIDI note number to frequency in Hz.
pub fn midi_to_hz(midi : Double) -> Double {
  440.0 * @math.pow(2.0, (midi - 69.0) / 12.0)
}

///|
pub fn copy_control_events(
  events : Array[@pattern.Event[@pattern.ControlMap]],
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  events.copy()
}

///|
/// Sort note-on capable events before continuous/no-whole events.
pub fn compare_event_onset(
  a : @pattern.Event[@pattern.ControlMap],
  b : @pattern.Event[@pattern.ControlMap],
) -> Int {
  match (a.whole, b.whole) {
    (Some(wa), Some(wb)) => wa.begin.compare(wb.begin)
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (None, None) => 0
  }
}
