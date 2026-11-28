///|
/// The player of one performance: it accepts scores, plays, pauses and ends
/// them, and renders blocks of stereo audio. It knows no platform; the
/// browser's AudioWorklet and an offline renderer drive it the same way.
pub struct Player {
  priv scheduler : @scheduler.PatternScheduler
  priv sampler_pool : @moondsp.BoundVoicePool
  priv onsets : @scheduler.OnsetBuffer
  priv signals : @scheduler.SignalBuffer
  priv context : @moondsp.DspContext
  priv reverb : @moondsp.StereoReverb
  priv send_left : @moondsp.AudioBuffer
  priv send_right : @moondsp.AudioBuffer
  priv wet_left : @moondsp.AudioBuffer
  priv wet_right : @moondsp.AudioBuffer
  priv mut gain : Double
  priv mut session : Session
}

///|
/// A player whose drums, instruments and samples sound as `sounds` says,
/// rendering in `ctx`'s format and reading samples from its store. Raises
/// `UnsupportedFormat` when a voice pool or the scheduler cannot run that
/// format.
pub fn Player::Player(
  ctx : @moondsp.DspContext,
  sounds : Sounds,
) -> Player raise UnsupportedFormat {
  guard scheduler_with_sounds(ctx, sounds) is Some((scheduler, sampler_pool)) else {
    raise UnsupportedFormat
  }
  let size = ctx.block_size()
  let onsets = @scheduler.OnsetBuffer()
  scheduler.attach_onset_buffer(onsets)
  let signals = @scheduler.SignalBuffer()
  scheduler.attach_signal_buffer(signals)
  {
    scheduler,
    sampler_pool,
    onsets,
    signals,
    context: ctx,
    reverb: @moondsp.StereoReverb::StereoReverb(ctx.sample_rate()),
    send_left: @moondsp.AudioBuffer::filled(size),
    send_right: @moondsp.AudioBuffer::filled(size),
    wet_left: @moondsp.AudioBuffer::filled(size),
    wet_right: @moondsp.AudioBuffer::filled(size),
    gain: 0.5,
    session: Empty,
  }
}

///|
/// Reclaim replaced waveforms no sounding sampler voice reads. Call before
/// loading a waveform into this player's context store (ADR-0026). Allocates
/// nothing; the pool stays private to the player.
pub fn Player::reclaim_samples(self : Player) -> Unit {
  let store = self.context.samples()
  store.begin_scan()
  self.sampler_pool.mark_samples()
  store.end_scan()
}

///|
priv enum Session {
  Empty
  Ready(Score)
  Playing(Score)
  Paused(Score)
  Ended(Score, Int64, Double)
  Fault(FaultReason)
}

///|
/// Kind of an accepted score.
#derive(Eq, Debug)
pub enum ScoreKind {
  Pattern
  Song
}

///|
pub extend ScoreKind with Eq::{not_equal, equal}

///|
pub extend ScoreKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Why a player went into Fault.
#derive(Eq, Debug)
pub enum FaultReason {
  /// The transport's range ran out while rendering.
  TransportExhausted
  /// The playing song's end lies past the transport's range.
  SongEndUnreachable
}

///|
pub extend FaultReason with Eq::{not_equal, equal}

///|
pub extend FaultReason with @moonbitlang/core/debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub enum PlayState {
  Empty
  Ready
  Playing
  Paused
  Ended
  Fault
}

///|
pub extend PlayState with Eq::{not_equal, equal}

///|
pub extend PlayState with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A tempo outside 0.001..1000 BPM.
#derive(Eq, Debug)
pub suberror TempoOutOfRange

///|
pub fn TempoOutOfRange::message(self : TempoOutOfRange) -> String {
  ignore(self)
  "tempo must be 0.001..1000 BPM"
}

///|
/// Why a score cannot be built.
#derive(Eq, Debug)
pub suberror ScoreError {
  /// Mini refused the input.
  InvalidSource(@mini.SourceProblem)
  /// The score's tempo is out of range.
  Tempo(TempoOutOfRange)
}

///|
/// The diagnostic the browser shows for `self`.
pub fn ScoreError::message(self : ScoreError) -> String {
  match self {
    InvalidSource(problem) => problem.to_string()
    Tempo(error) => error.message()
  }
}

///|
/// A voice pool or the scheduler cannot run the context's format.
#derive(Eq, Debug)
pub suberror UnsupportedFormat

///|
pub fn UnsupportedFormat::message(self : UnsupportedFormat) -> String {
  ignore(self)
  "the player cannot run this sample rate and block size"
}

///|
/// Why a player refuses a score, a command or a block.
#derive(Eq, Debug)
pub suberror PlayerError {
  /// A repeated song lasts less than one block.
  RepeatShorterThanBlock
  /// The score has more materials than a player plays.
  TooManyMaterials
  /// Accepting would retain more materials than a player plays.
  TooManyRetainedMaterials
  /// The score was compiled for a player with shorter blocks.
  CompiledForShorterBlocks
  /// The song is arranged differently from the playing one; accept it with
  /// `restart`.
  RestartRequired
  /// There is no score to play or pause.
  NoSong
  /// The tempo change would leave the transport's range.
  TransportRange
  /// The song's end would leave the transport's range.
  SongEndOutOfRange
  /// The player is in Fault and accepts nothing.
  Faulted(FaultReason)
  /// `process` was given buffers of the wrong length.
  BufferSizeMismatch(expected~ : Int32, actual~ : Int32)
}

///|
/// The diagnostic the browser shows for `self`.
pub fn PlayerError::message(self : PlayerError) -> String {
  match self {
    RepeatShorterThanBlock => "repeated song must span at least one audio block"
    TooManyMaterials => "playback source exceeds 256 material entries"
    TooManyRetainedMaterials =>
      "playback would retain more than 256 material entries; wait for their boundaries or Restart"
    CompiledForShorterBlocks =>
      "score was compiled for a player with shorter blocks; compile it for this player"
    RestartRequired => "song layout changed; restart required"
    NoSong => "no Current song; update source before Play"
    TransportRange => "tempo change exceeds transport range"
    SongEndOutOfRange | Faulted(SongEndUnreachable) =>
      "song end exceeds transport range"
    Faulted(TransportExhausted) => "transport range exhausted"
    BufferSizeMismatch(expected~, actual~) =>
      "output buffers hold \{actual} samples, not the block's \{expected}"
  }
}

///|
fn Session::score(self : Session) -> Score? {
  match self {
    Empty | Fault(_) => None
    Ready(score) | Playing(score) | Paused(score) | Ended(score, _, _) =>
      Some(score)
  }
}

///|
/// Compile frozen Mini input into a score this player can accept: the input
/// must fit the work this player admits at every tempo it supports.
pub fn Player::compile(
  self : Player,
  input : @mini.PlaybackInput,
) -> Score raise ScoreError {
  // Admission covers every supported future tempo, including the demo control.
  let window = self.scheduler.max_query_window()
  let compiled = input.compile(query_window=window) catch {
    problem => raise InvalidSource(problem)
  }
  let tempo = score_tempo(compiled.bpm())
  let score = match compiled.material() {
    TrackedPattern(snapshot) => Score::pattern(snapshot.playback(), tempo~)
    UntrackedPattern(snapshot) => Score::pattern(snapshot.playback(), tempo~)
    TrackedSong(song, repeat) => Score::song(song, tempo~, repeat~)
    UntrackedSong(song, repeat) => Score::song(song, tempo~, repeat~)
  }
  { ..score, admitted: Some(window), }
}

///|
/// A score's tempo from the BPM its source declares.
fn score_tempo(bpm : Double) -> Tempo raise ScoreError {
  Tempo(bpm) catch {
    error => raise Tempo(error)
  }
}

///|
/// Whether `score` can play at `tempo` on this player; the scheduler decides.
fn Player::check_fits(
  self : Player,
  score : Score,
  tempo : @scheduler.Tempo,
) -> Unit raise PlayerError {
  match self.scheduler.check_fits(score.snapshot, tempo) {
    Ok(_) => ()
    Err(error) => raise fit_error(error)
  }
}

///|
fn fit_error(error : @scheduler.PlaybackFitError) -> PlayerError {
  match error {
    RepetitionShorterThanBlock => RepeatShorterThanBlock
    EndOutOfRange => SongEndOutOfRange
    Transport(_) => TransportRange
  }
}

///|
/// What this player requires of any score it accepts. A compiled score must
/// have been admitted for a window at least as long as this player's, so a
/// score compiled by a player with shorter blocks cannot overrun this one.
fn Player::admit(self : Player, score : Score) -> Unit raise PlayerError {
  if self.session is Fault(reason) {
    raise Faulted(reason)
  }
  if score.admitted is Some(window) &&
    window.span() < self.scheduler.max_query_window().span() {
    raise CompiledForShorterBlocks
  }
  self.check_fits(score, score.tempo)
  guard score.snapshot.material_count() <= PLAYBACK_MATERIAL_LIMIT else {
    raise TooManyMaterials
  }
}

///|
/// All state-dependent planning and installation happen in this owner turn.
/// No prepared handle or execution plan can survive an intervening render.
fn Player::install(
  self : Player,
  score : Score,
  restart : Bool,
) -> Unit raise PlayerError {
  match
    self.scheduler.accept_playback(
      score.snapshot,
      score.tempo,
      material_limit=PLAYBACK_MATERIAL_LIMIT,
      restart~,
    ) {
    Err(ArrangementChanged) => raise RestartRequired
    Err(Unfit(error)) => raise fit_error(error)
    Err(MaterialLimit) => raise TooManyRetainedMaterials
    Err(Transport(_)) => raise TransportRange
    Ok(_) => ()
  }
  if restart {
    self.reverb.reset()
    self.scheduler.kill_all_voices()
  }
}

///|
/// Accept `score` without starting or rewinding the performance. Playing and
/// Paused continue with it; a song arranged differently (another set of
/// occurrences, starts, lengths or repetition, or a switch between pattern
/// and song) raises `RestartRequired`. Empty and Ready become Ready; Ended keeps its position,
/// and the next `play` starts `score`.
pub fn Player::update(self : Player, score : Score) -> Unit raise PlayerError {
  self.admit(score)
  match self.session {
    Playing(_) | Paused(_) => {
      self.install(score, false)
      self.session = match self.session {
        Paused(_) => Paused(score)
        _ => Playing(score)
      }
    }
    Ended(_, position, cycle) => self.session = Ended(score, position, cycle)
    Empty | Ready(_) => self.session = Ready(score)
    Fault(reason) => raise Faulted(reason)
  }
}

///|
/// Accept `score` and play it from its beginning. A score the player refuses
/// resets no voice or clock.
pub fn Player::restart(self : Player, score : Score) -> Unit raise PlayerError {
  self.admit(score)
  self.install(score, true)
  self.session = Playing(score)
}

///|
/// Resume Paused, or play Ready and Ended from the beginning.
pub fn Player::play(self : Player) -> Unit raise PlayerError {
  match self.session {
    Empty => raise NoSong
    Fault(reason) => raise Faulted(reason)
    Playing(_) => ()
    Paused(score) => self.session = Playing(score)
    Ready(score) | Ended(score, _, _) => {
      self.install(score, true)
      self.session = Playing(score)
    }
  }
}

///|
pub fn Player::pause(self : Player) -> Unit raise PlayerError {
  match self.session {
    Empty => raise NoSong
    Fault(reason) => raise Faulted(reason)
    Playing(score) => self.session = Paused(score)
    Ready(_) | Paused(_) | Ended(_, _, _) => ()
  }
}

///|
/// Render the next block into `left` and `right`, which must hold one block
/// each. Empty, Ready and Paused render silence without advancing. A Playing
/// finite song becomes Ended at its end; Ended keeps rendering its tails. A
/// scheduler transport error silences the block, kills every voice and
/// leaves the player in Fault; a song end the transport cannot reach leaves
/// it in Fault after the block rendered. `None` is the rendered block, which
/// constructs nothing on the audio thread.
pub fn Player::process(
  self : Player,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> PlayerError? {
  let size = self.context.block_size()
  guard left.length() == size && right.length() == size else {
    return Some(
      BufferSizeMismatch(
        expected=size,
        actual=if left.length() != size {
          left.length()
        } else {
          right.length()
        },
      ),
    )
  }
  left.fill(0.0)
  right.fill(0.0)
  match self.session {
    Empty | Ready(_) | Paused(_) => return None
    Fault(reason) => return Some(Faulted(reason))
    Playing(_) | Ended(_, _, _) => ()
  }
  self.scheduler.render_block_with_send(
    left,
    right,
    self.send_left,
    self.send_right,
  )
  if self.scheduler.last_transport_error() is Some(_) {
    self.session = Fault(TransportExhausted)
    left.fill(0.0)
    right.fill(0.0)
    self.scheduler.kill_all_voices()
    return Some(Faulted(TransportExhausted))
  }
  self.reverb.process(
    self.context,
    self.send_left,
    self.send_right,
    self.wet_left,
    self.wet_right,
  )
  for i in 0..<size {
    left.set(i, (left.get(i) + self.wet_left.get(i)) * self.gain)
    right.set(i, (right.get(i) + self.wet_right.get(i)) * self.gain)
  }
  if self.session is Playing(score) {
    match self.scheduler.song_end() {
      Ahead => ()
      Reached(sample, position) =>
        self.session = Ended(score, sample, position.to_double())
      Unreachable => {
        self.session = Fault(SongEndUnreachable)
        return Some(Faulted(SongEndUnreachable))
      }
    }
  }
  None
}

///|
/// Change the tempo at the next unrendered sample, keeping the musical
/// position. A change the accepted song cannot take changes nothing.
pub fn Player::set_tempo(
  self : Player,
  tempo : Tempo,
) -> Unit raise PlayerError {
  let tempo = tempo.value
  // A Ready or Ended score is not installed yet; it must fit as well.
  if self.session.score() is Some(score) {
    self.check_fits(score, tempo)
  }
  match self.scheduler.set_tempo(tempo) {
    Ok(_) => ()
    Err(Transport(_)) => raise TransportRange
    Err(error) => raise fit_error(error)
  }
  if self.session.score() is Some(score) {
    let next = { ..score, tempo, }
    self.session = match self.session {
      Ready(_) => Ready(next)
      Playing(_) => Playing(next)
      Paused(_) => Paused(next)
      Ended(_, position, cycle) => Ended(next, position, cycle)
      other => other
    }
  }
}

///|
/// Set the output gain, clamped to 0..1; a non-finite gain resets it to 0.5.
pub fn Player::set_gain(self : Player, gain : Double) -> Unit {
  self.gain = if gain.is_nan() || gain.is_inf() {
    0.5
  } else {
    Double::min(1.0, Double::max(0.0, gain))
  }
}

///|
pub fn Player::state(self : Player) -> PlayState {
  match self.session {
    Empty => PlayState::Empty
    Ready(_) => Ready
    Playing(_) => Playing
    Paused(_) => Paused
    Ended(_, _, _) => Ended
    Fault(_) => Fault
  }
}

///|
/// Kind of the accepted score; `None` when there is none.
pub fn Player::mode(self : Player) -> ScoreKind? {
  self.session
  .score()
  .map(score => if score.snapshot.is_song() { Song } else { Pattern })
}

///|
/// The accepted score's tempo, or the scheduler's when there is none.
pub fn Player::bpm(self : Player) -> Double {
  match self.session.score() {
    Some(score) => score.tempo.bpm()
    None => self.scheduler.bpm()
  }
}

///|
/// The zero-based musical cycle position from the scheduler clock.
///
/// Ready and Empty are anchored at zero. Paused reads the frozen clock, and
/// Ended reports the accepted finite song's exact musical endpoint rather than
/// deriving it from a BPM/sample approximation.
pub fn Player::cycle_position(self : Player) -> Double {
  match self.session {
    Empty | Ready(_) | Fault(_) => 0.0
    Playing(_) | Paused(_) => self.scheduler.cycle_position()
    Ended(_, _, cycle) => cycle
  }
}

///|
/// The rendered sample position. Empty and Ready are at zero; Ended keeps the
/// song's end.
pub fn Player::sample_position(self : Player) -> Double {
  match self.session {
    Ended(_, position, _) => position.to_double()
    Empty | Ready(_) => 0.0
    _ => self.scheduler.sample_counter().to_double()
  }
}

///|
/// Accepted material changes still waiting for their entry boundary, while
/// Playing or Paused.
pub fn Player::pending_materials(self : Player) -> Int32 {
  match self.session {
    Playing(_) | Paused(_) => self.scheduler.pending_material_change_count()
    _ => 0
  }
}

///|
/// Accepted finite material changes that cannot enter during this Play.
pub fn Player::skipped_materials(self : Player) -> Int32 {
  match self.session {
    Playing(_) | Paused(_) => self.scheduler.skipped_material_change_count()
    _ => 0
  }
}

///|
/// The ring of playback onsets the player records when it is enabled.
pub fn Player::onsets(self : Player) -> @scheduler.OnsetBuffer {
  self.onsets
}

///|
/// The ring of control-signal values the player records when it is enabled.
pub fn Player::signals(self : Player) -> @scheduler.SignalBuffer {
  self.signals
}
