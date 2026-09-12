///|
/// Scheduler-owned active voice with its performance-sample gate-off time.
priv struct ActiveNote {
  handle : @voice.VoiceHandle
  origin : @model.VoiceOrigin
  end_sample : Int64
}

///|
fn ActiveNote::ActiveNote(
  handle~ : @voice.VoiceHandle,
  origin? : @model.VoiceOrigin = @model.VoiceOrigin::Anonymous,
  end_sample~ : Int64,
) -> ActiveNote {
  { handle, origin, end_sample, }
}

///|
fn ActiveNote::handle(self : ActiveNote) -> @voice.VoiceHandle {
  self.handle
}

///|
fn ActiveNote::origin(self : ActiveNote) -> @model.VoiceOrigin {
  self.origin
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
  { notes: [], }
}

///|
pub fn ActiveNotes::length(self : ActiveNotes) -> Int {
  self.notes.length()
}

///|
pub fn ActiveNotes::push_note(
  self : ActiveNotes,
  handle~ : @voice.VoiceHandle,
  origin? : @model.VoiceOrigin = @model.VoiceOrigin::Anonymous,
  end_sample~ : Int64,
) -> Unit {
  self.notes.push(ActiveNote(handle~, origin~, end_sample~))
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
pub fn ActiveNotes::matching_count(
  self : ActiveNotes,
  matches : (@model.VoiceOrigin) -> Bool,
) -> Int {
  for note in self.notes; total = 0 {
    continue total + (if matches(note.origin()) { 1 } else { 0 })
  } nobreak {
    total
  }
}

///|
pub fn ActiveNotes::remove_matching(
  self : ActiveNotes,
  matches : (@model.VoiceOrigin) -> Bool,
  pool : @voice.BoundVoicePool,
  kill~ : Bool,
) -> Int {
  let mut count = 0
  let mut i = 0
  while i < self.notes.length() {
    if matches(self.notes[i].origin()) {
      if kill {
        self.notes[i].kill(pool)
      } else {
        self.notes[i].note_off(pool)
      }
      let last = self.notes.length() - 1
      if i < last {
        self.notes[i] = self.notes[last]
      }
      ignore(self.notes.pop())
      count += 1
    } else {
      i += 1
    }
  }
  count
}

///|
pub fn[E] ActiveNotes::try_each_matching(
  self : ActiveNotes,
  matches : (@model.VoiceOrigin) -> Bool,
  f : (@voice.VoiceHandle) -> Result[Unit, E],
) -> Result[Unit, E] {
  for note in self.notes {
    if matches(note.origin()) {
      match f(note.handle()) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    }
  }
  Ok(())
}

///|
pub fn[E] ActiveNotes::try_count_matching(
  self : ActiveNotes,
  matches : (@model.VoiceOrigin) -> Bool,
  f : (@voice.VoiceHandle) -> Result[Unit, E],
) -> Result[Int, E] {
  for note in self.notes; count = 0 {
    if matches(note.origin()) {
      match f(note.handle()) {
        Ok(_) => continue count + 1
        Err(error) => return Err(error)
      }
    }
    continue count
  } nobreak {
    Ok(count)
  }
}
