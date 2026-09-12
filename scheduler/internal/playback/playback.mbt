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
    Pattern(snapshot) => query_pattern_events(snapshot, arc)
    Song(snapshot) => query_song_events(snapshot, arc)
  }
}

///|
/// Internal active/pending playback snapshot queue. Pending commits are explicit
/// so the scheduler facade can preserve block-boundary commit semantics.
pub struct PlaybackState {
  priv mut active : PlaybackSnapshot?
  priv mut pending : PlaybackSnapshot?
}

///|
pub fn PlaybackState::PlaybackState() -> PlaybackState {
  { active: None, pending: None, }
}

///|
pub fn PlaybackState::queue(
  self : PlaybackState,
  snapshot : PlaybackSnapshot,
) -> Unit {
  self.pending = Some(snapshot)
}

///|
pub fn PlaybackState::commit_pending(self : PlaybackState) -> Unit {
  match self.pending {
    Some(snapshot) => {
      self.active = Some(snapshot)
      self.pending = None
    }
    None => ()
  }
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
    None => false
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
    None => false
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
  match self.pending {
    Some(_) => true
    None => false
  }
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
pub fn PlaybackState::active_snapshot(
  self : PlaybackState,
) -> PlaybackSnapshot? {
  self.active
}

///|
fn query_pattern_events(
  snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  snapshot.query(arc)
}

///|
fn query_song_events(
  snapshot : @song.SongSnapshot[@pattern.ControlMap],
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  snapshot.query(arc)
}
