///|
/// A playback event paired with its authored voice origin.
pub struct PlaybackSourcedEvent {
  priv event : @pattern.Event[@pattern.ControlMap]
  priv origin : @model.VoiceOrigin
}

///|
pub fn PlaybackSourcedEvent::anonymous(
  event : @pattern.Event[@pattern.ControlMap],
) -> PlaybackSourcedEvent {
  { event, origin: @model.VoiceOrigin::Anonymous, }
}

///|
pub fn PlaybackSourcedEvent::event(
  self : PlaybackSourcedEvent,
) -> @pattern.Event[@pattern.ControlMap] {
  self.event
}

///|
pub fn PlaybackSourcedEvent::origin(
  self : PlaybackSourcedEvent,
) -> @model.VoiceOrigin {
  self.origin
}

///|
/// Internal prepared scheduler input for active/pending playback state.
pub enum PlaybackSnapshot {
  Pattern(@pattern.PatternSnapshot[@pattern.ControlMap])
  Song(@song.SongSnapshot[@pattern.ControlMap])
}

///|
pub fn PlaybackSnapshot::pattern(
  snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
) -> PlaybackSnapshot {
  Pattern(snapshot)
}

///|
pub fn PlaybackSnapshot::song(
  snapshot : @song.SongSnapshot[@pattern.ControlMap],
) -> PlaybackSnapshot {
  Song(snapshot)
}

///|
pub fn PlaybackSnapshot::revision(
  self : PlaybackSnapshot,
) -> @identity.Revision {
  match self {
    Pattern(snapshot) => snapshot.revision()
    Song(snapshot) => snapshot.revision()
  }
}

///|
pub fn PlaybackSnapshot::song_layout_revision(
  self : PlaybackSnapshot,
) -> @identity.Revision? {
  match self {
    Pattern(_) => None
    Song(snapshot) => Some(snapshot.layout_revision())
  }
}

///|
fn PlaybackSnapshot::is_pattern(self : PlaybackSnapshot) -> Bool {
  match self {
    Pattern(_) => true
    Song(_) => false
  }
}

///|
fn PlaybackSnapshot::is_song(self : PlaybackSnapshot) -> Bool {
  match self {
    Pattern(_) => false
    Song(_) => true
  }
}

///|
pub fn PlaybackSnapshot::query_events(
  self : PlaybackSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  match self {
    Pattern(snapshot) => snapshot.query(arc)
    Song(snapshot) => snapshot.query(arc)
  }
}

///|
/// Internal active/pending playback snapshot queue. Pending commits are explicit
/// so the scheduler facade can preserve block-boundary commit semantics.
pub struct PlaybackState {
  priv mut active : PlaybackSnapshot?
  priv mut pending : PlaybackSnapshot?
  priv mut entries : Array[EntryState]
}

///|
pub fn PlaybackState::PlaybackState() -> PlaybackState {
  { active: None, pending: None, entries: [], }
}

///|
pub fn PlaybackState::queue(
  self : PlaybackState,
  snapshot : PlaybackSnapshot,
) -> Unit {
  self.pending = Some(snapshot)
}

///|
pub fn PlaybackState::commit_pending(
  self : PlaybackState,
  now : @pattern.Rational,
) -> Unit {
  self.entries = settle_entries(self.entries, now)
  if self.pending is Some(snapshot) {
    self.entries = if self.active is None {
      snapshot.start_entries()
    } else {
      snapshot.reconcile_entries(self.entries, now)
    }
    self.active = Some(snapshot)
    self.pending = None
    self.entries = settle_entries(self.entries, now)
  }
}

///|
pub fn PlaybackState::reset(self : PlaybackState) -> Unit {
  self.active = None
  self.pending = None
  self.entries = []
}

///|
pub fn PlaybackState::has_active_pattern(self : PlaybackState) -> Bool {
  match self.active {
    Some(snapshot) => snapshot.is_pattern()
    None => false
  }
}

///|
pub fn PlaybackState::has_pending_pattern(self : PlaybackState) -> Bool {
  match self.pending {
    Some(snapshot) => snapshot.is_pattern()
    None =>
      match self.active {
        Some(snapshot) => self.has_pending() && snapshot.is_pattern()
        None => false
      }
  }
}

///|
pub fn PlaybackState::has_active_song(self : PlaybackState) -> Bool {
  match self.active {
    Some(snapshot) => snapshot.is_song()
    None => false
  }
}

///|
pub fn PlaybackState::has_pending_song(self : PlaybackState) -> Bool {
  match self.pending {
    Some(snapshot) => snapshot.is_song()
    None =>
      match self.active {
        Some(snapshot) => self.has_pending() && snapshot.is_song()
        None => false
      }
  }
}

///|
pub fn PlaybackState::has_active(self : PlaybackState) -> Bool {
  match self.active {
    Some(_) => true
    None => false
  }
}

///|
pub fn PlaybackState::has_pending(self : PlaybackState) -> Bool {
  self.pending is Some(_) || self.entries.any(entry => entry.has_pending())
}

///|
pub fn PlaybackState::active_revision(
  self : PlaybackState,
) -> @identity.Revision? {
  match self.active {
    Some(snapshot) => Some(snapshot.revision())
    None => None
  }
}

///|
pub fn PlaybackState::active_song_revision(
  self : PlaybackState,
) -> @identity.Revision? {
  if self.has_active_song() {
    self.active_revision()
  } else {
    None
  }
}

///|
pub fn PlaybackState::active_song_layout_revision(
  self : PlaybackState,
) -> @identity.Revision? {
  match self.active {
    Some(snapshot) => snapshot.song_layout_revision()
    None => None
  }
}

///|
pub fn PlaybackState::query_active_events(
  self : PlaybackState,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  query_entries(self.entries, arc)
}

///|
pub fn PlaybackState::query_active_sourced_events(
  self : PlaybackState,
  arc : @pattern.TimeSpan,
) -> Array[PlaybackSourcedEvent] {
  query_sourced_entries(self.entries, arc)
}
