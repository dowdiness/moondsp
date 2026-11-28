///|
const PLAYBACK_MATERIAL_LIMIT = 256

///|
priv enum PlaybackSpan {
  Continuous
  Finite(@pattern.Rational)
  Repeating(@pattern.Rational)
}

///|
/// A score the player can accept: lowered material with its tempo and how
/// long it plays. `Player::compile` builds one from Mini
/// input and records the query window Mini admitted its work for;
/// `pattern` and `song` build one from
/// content that has no source text, whose work nothing bounds: the caller
/// answers for it, as it does when it hands the scheduler a snapshot.
pub struct Score {
  priv tempo : @scheduler.Tempo
  priv snapshot : @scheduler.PlaybackSnapshot
  priv span : PlaybackSpan
  /// The window Mini bounded this score's work for, when it was compiled.
  priv admitted : @pattern.QueryWindow?
}

///|
fn Score::finite_end(self : Score) -> @pattern.Rational? {
  match self.span {
    Finite(end_) => Some(end_)
    Continuous | Repeating(_) => None
  }
}

///|
/// A pattern that plays forever at `tempo`. Its events carry event origins
/// when it was built from a tracked snapshot.
pub fn Score::pattern(
  pattern : @pattern.PlaybackPattern[@score.ScoreEvent],
  tempo~ : Tempo,
) -> Score {
  {
    admitted: None,
    tempo: tempo.value,
    snapshot: @scheduler.PlaybackSnapshot::pattern(pattern),
    span: Continuous,
  }
}

///|
/// A lowered song at `tempo` that ends after its last occurrence, or repeats
/// when `repeat` is true. Its events carry event origins when its sections
/// hold tracked snapshots.
pub fn[C : @song.SongContent] Score::song(
  snapshot : @song.SongSnapshot[C],
  tempo~ : Tempo,
  repeat~ : Bool = false,
) -> Score raise ScoreError {
  let song = snapshot.song()
  guard song.duration() > @pattern.Rational::from_int(0) else {
    raise EmptySong
  }
  {
    admitted: None,
    tempo: tempo.value,
    snapshot: @scheduler.PlaybackSnapshot::song(snapshot, repeat~),
    span: if repeat {
      Repeating(song.duration())
    } else {
      Finite(song.duration())
    },
  }
}

///|
/// A tempo a player can play: 0.001..1000 BPM.
pub struct Tempo {
  priv value : @scheduler.Tempo
}

///|
/// `bpm` beats per minute, or `TempoOutOfRange` outside 0.001..1000.
pub fn Tempo::Tempo(bpm : Double) -> Tempo raise TempoOutOfRange {
  guard @scheduler.Tempo::from_bpm(bpm) is Ok(value) else {
    raise TempoOutOfRange
  }
  { value, }
}

///|
pub fn Tempo::bpm(self : Tempo) -> Double {
  self.value.bpm()
}
