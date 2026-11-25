///|
/// The player of one performance: it prepares scores, accepts them, and
/// renders blocks of stereo audio. It knows no platform; the browser's
/// AudioWorklet and an offline renderer drive it the same way.
pub struct Player {
  priv scheduler : @scheduler.PatternScheduler
  priv onsets : @scheduler.OnsetBuffer
  priv signals : @scheduler.SignalBuffer
  priv context : @moondsp.DspContext
  priv left : @moondsp.AudioBuffer
  priv right : @moondsp.AudioBuffer
  priv reverb : @moondsp.StereoReverb
  priv send_left : @moondsp.AudioBuffer
  priv send_right : @moondsp.AudioBuffer
  priv wet_left : @moondsp.AudioBuffer
  priv wet_right : @moondsp.AudioBuffer
  priv mut gain : Double
  priv mut session : Session
}

///|
/// A player whose drums, instruments and sampler sound as `drum`,
/// `instrument` and `sampler` describe, rendering in `ctx`'s format and
/// reading samples from its store. Raises `UnsupportedFormat` when a voice
/// pool or the scheduler cannot run `ctx`'s format.
pub fn Player::Player(
  ctx : @moondsp.DspContext,
  drum~ : (@score.Drum) -> @moondsp.AnalyzedGraph,
  instrument~ : (@score.Instrument) -> NoteVoice,
  sampler~ : SamplerVoice,
) -> Player raise PlayerError {
  guard scheduler_with_sounds(ctx, drum, instrument, sampler) is Some(scheduler) else {
    raise UnsupportedFormat
  }
  let size = ctx.block_size()
  let onsets = @scheduler.OnsetBuffer()
  scheduler.attach_onset_buffer(onsets)
  let signals = @scheduler.SignalBuffer()
  scheduler.attach_signal_buffer(signals)
  {
    scheduler,
    onsets,
    signals,
    context: ctx,
    left: @moondsp.AudioBuffer::filled(size),
    right: @moondsp.AudioBuffer::filled(size),
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
const PLAYBACK_MATERIAL_LIMIT = 256

///|
#derive(Eq)
priv struct PlaybackLayoutRow {
  id : String
  name : String
  section : String
  start : @pattern.Rational
  length : @pattern.Rational
  rate : @pattern.Rational
}

///|
#derive(Eq)
priv enum PlaybackLayout {
  PatternLayout
  SongLayout(Array[PlaybackLayoutRow], Bool)
}

///|
priv enum PlaybackSpan {
  Continuous
  Finite(@pattern.Rational)
  Repeating(@pattern.Rational)
}

///|
priv struct PreparedSong {
  source : String
  tempo : @scheduler.Tempo
  layout : PlaybackLayout
  snapshot : @scheduler.PlaybackSnapshot
  span : PlaybackSpan
}

///|
priv enum Session {
  Empty
  Ready(PreparedSong)
  Playing(PreparedSong)
  Paused(PreparedSong)
  Ended(PreparedSong, Int64, Double)
  Fault(String)
}

///|
/// Kind of the latest accepted score, independent of the visible draft.
#derive(Eq, Debug)
pub(all) enum PlaybackMode {
  None
  Pattern
  Song
}

///|
pub extend PlaybackMode with Eq::{not_equal, equal}

///|
pub extend PlaybackMode with @moonbitlang/core/debug.Debug::{to_repr}

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
#derive(Eq, Debug)
pub suberror PlayerError {
  InvalidSource(String)
  RestartRequired
  NoSong
  TransportRange
  Failed(String)
  /// A voice pool or the scheduler cannot run the context's format.
  UnsupportedFormat
}

///|
pub extend PlayerError with Eq::{not_equal, equal}

///|
pub extend PlayerError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub struct PlayerView {
  state : PlayState
  source : String?
  bpm : Double
  sample_position : Double
  pending_materials : Int32
  skipped_materials : Int32
}

///|
fn Session::song(self : Session) -> PreparedSong? {
  match self {
    Empty | Fault(_) => None
    Ready(song) | Playing(song) | Paused(song) | Ended(song, _, _) => Some(song)
  }
}

///|
fn PreparedSong::finite_end(self : PreparedSong) -> @pattern.Rational? {
  match self.span {
    Finite(end_) => Some(end_)
    Continuous | Repeating(_) => None
  }
}

///|
fn Player::check_repeat_span(
  self : Player,
  span : PlaybackSpan,
  tempo : @scheduler.Tempo,
) -> Unit raise PlayerError {
  guard span is Repeating(period) else { return }
  guard tempo.span_for_samples(
      self.context.block_size(),
      sample_rate=self.context.sample_rate(),
    )
    is Ok(block_span) else {
    raise TransportRange
  }
  guard period >= block_span else {
    raise InvalidSource("repeated song must span at least one audio block")
  }
}

///|
fn tempo_of(bpm : Double) -> @scheduler.Tempo raise PlayerError {
  guard @scheduler.Tempo::from_bpm(bpm) is Ok(tempo) else {
    raise InvalidSource("tempo must be 0.001..1000 BPM")
  }
  tempo
}

///|
fn[C] song_layout(song : @song.Song[C], repeated : Bool) -> PlaybackLayout {
  SongLayout(
    song
    .occurrences()
    .map(o => {
      id: o.id().value(),
      name: o.name(),
      section: o.section().name(),
      start: o.start(),
      length: o.section().length_cycles(),
      rate: o.section().scope().rate(),
    }),
    repeated,
  )
}

///|
fn[C] live_section_doc_body(
  body : @song.SectionBody[C],
) -> @song.SectionDocBody[C] raise {
  match body {
    Single(content) =>
      @song.SectionDocBody::single(
        @song.SectionLayerDoc(
          id=@identity.SectionLayerId::from_string("live:body"),
          name="main",
          body=content,
        ),
      )
    Layers(layers) => {
      let docs : Array[@song.SectionLayerDoc[C]] = []
      for layer in layers {
        docs.push(
          @song.SectionLayerDoc(
            id=@identity.SectionLayerId::from_string(
              "live:layer:" + layer.name(),
            ),
            name=layer.name(),
            body=layer.body(),
          ),
        )
      }
      @song.SectionDocBody::layers(docs)
    }
  }
}

///|
fn[C : @song.SongContent] song_update_snapshot(
  song : @song.Song[C],
) -> @song.SongSnapshot[C] raise {
  let parts = song
    .occurrences()
    .map(o => {
      let section = @song.SectionDoc(
        id=@identity.SectionId::from_string("live:" + o.id().value()),
        name=o.section().name(),
        length_cycles=o.section().length_cycles(),
        scope=o.section().scope(),
        body=live_section_doc_body(o.section().section_body()),
      )
      @song.SongOccurrenceDoc::at(
        id=o.id(),
        start=o.start(),
        name=o.name(),
        section~,
      )
    })
  @song.SongDoc(parts~).lower()
}

///|
fn Player::prepare(
  self : Player,
  input : @mini.PlaybackInput,
) -> PreparedSong raise PlayerError {
  // Admission covers every supported future tempo, including the demo control.
  let prepared = match
    input.compile(query_window=self.scheduler.max_query_window()) {
    Ok(prepared) => prepared
    Err(message) => raise InvalidSource(message)
  }
  let source = input.source()
  let song : PreparedSong = match prepared {
    @mini.PreparedPlayback::TrackedPattern(snapshot, bpm) =>
      {
        source,
        tempo: tempo_of(bpm),
        layout: PatternLayout,
        snapshot: @scheduler.PlaybackSnapshot::tracked_pattern(snapshot),
        span: Continuous,
      }
    @mini.PreparedPlayback::Source(parsed) => {
      let tempo = tempo_of(parsed.bpm())
      match parsed.body() {
        Pattern(doc) => {
          let snapshot = doc.lower() catch {
            error =>
              raise InvalidSource("could not lower source: \{Repr(error)}")
          }
          {
            source,
            tempo,
            layout: PatternLayout,
            snapshot: @scheduler.PlaybackSnapshot::untracked_pattern(snapshot),
            span: Continuous,
          }
        }
        UntrackedArrangement(song, repeated) =>
          self.prepare_arrangement(source, tempo, song, repeated, snapshot => {
            @scheduler.SongMaterial::Untracked(snapshot)
          })
        TrackedArrangement(song, repeated) =>
          self.prepare_arrangement(source, tempo, song, repeated, snapshot => {
            @scheduler.SongMaterial::Tracked(snapshot)
          })
      }
    }
  }
  guard song.snapshot.material_count() <= PLAYBACK_MATERIAL_LIMIT else {
    raise InvalidSource("playback source exceeds 256 material entries")
  }
  song
}

///|
fn[C : @song.SongContent] Player::prepare_arrangement(
  self : Player,
  source : String,
  tempo : @scheduler.Tempo,
  song : @song.Song[C],
  repeated : Bool,
  material : (@song.SongSnapshot[C]) -> @scheduler.SongMaterial,
) -> PreparedSong raise PlayerError {
  guard song.duration() > @pattern.Rational::from_int(0) else {
    raise InvalidSource("song must end after its beginning")
  }
  let span = if repeated {
    Repeating(song.duration())
  } else {
    Finite(song.duration())
  }
  self.check_repeat_span(span, tempo)
  let snapshot = song_update_snapshot(song) catch {
    error => raise InvalidSource(error.to_string())
  }
  {
    source,
    tempo,
    layout: song_layout(song, repeated),
    snapshot: if repeated {
      @scheduler.PlaybackSnapshot::repeat_song(material(snapshot))
    } else {
      @scheduler.PlaybackSnapshot::song(material(snapshot))
    },
    span,
  }
}

///|
/// All state-dependent planning and installation happen in this owner turn.
/// No prepared handle or execution plan can survive an intervening render.
fn Player::install(
  self : Player,
  song : PreparedSong,
  restart : Bool,
) -> Unit raise PlayerError {
  match
    self.scheduler.accept_playback(
      song.snapshot,
      song.tempo,
      material_limit=PLAYBACK_MATERIAL_LIMIT,
      restart~,
      end_?=song.finite_end(),
    ) {
    Err(MaterialLimit) =>
      raise InvalidSource(
        "playback would retain more than 256 material entries; wait for their boundaries or Restart",
      )
    Err(Transport(_)) => raise TransportRange
    Ok(_) => ()
  }
  if restart {
    self.reverb.reset()
    self.scheduler.kill_all_voices()
  }
}

///|
/// Accept source without starting or rewinding the performance.
pub fn Player::update(
  self : Player,
  input : @mini.PlaybackInput,
) -> Unit raise PlayerError {
  if self.session is Fault(message) {
    raise Failed(message)
  }
  let next = self.prepare(input)
  match self.session {
    Empty | Ready(_) | Ended(_, _, _) =>
      if next.finite_end() is Some(end_) {
        guard next.tempo.sample_at_start(
            end_,
            sample_rate=self.context.sample_rate(),
          )
          is Ok(_) else {
          raise TransportRange
        }
      }
    Playing(_) | Paused(_) | Fault(_) => ()
  }
  match self.session {
    Playing(current) | Paused(current) => {
      guard current.layout == next.layout else { raise RestartRequired }
      self.install(next, false)
      self.session = match self.session {
        Paused(_) => Paused(next)
        _ => Playing(next)
      }
    }
    Ended(_, position, cycle) => self.session = Ended(next, position, cycle)
    Empty | Ready(_) => self.session = Ready(next)
    Fault(message) => raise Failed(message)
  }
}

///|
/// Parse current editor source first; invalid input cannot reset a voice or clock.
pub fn Player::restart(
  self : Player,
  input : @mini.PlaybackInput,
) -> Unit raise PlayerError {
  if self.session is Fault(message) {
    raise Failed(message)
  }
  let song = self.prepare(input)
  self.install(song, true)
  self.session = Playing(song)
}

///|
pub fn Player::play(self : Player) -> Unit raise PlayerError {
  match self.session {
    Empty => raise NoSong
    Fault(message) => raise Failed(message)
    Playing(_) => ()
    Paused(song) => self.session = Playing(song)
    Ready(song) | Ended(song, _, _) => {
      self.install(song, true)
      self.session = Playing(song)
    }
  }
}

///|
pub fn Player::pause(self : Player) -> Unit raise PlayerError {
  match self.session {
    Empty => raise NoSong
    Fault(message) => raise Failed(message)
    Playing(song) => self.session = Paused(song)
    Ready(_) | Paused(_) | Ended(_, _, _) => ()
  }
}

///|
/// Return the accepted source kind without constructing a `PlayerView`.
pub fn Player::mode(self : Player) -> PlaybackMode {
  match self.session {
    Empty | Fault(_) => None
    Ready(song) | Playing(song) | Paused(song) | Ended(song, _, _) =>
      match song.layout {
        PatternLayout => Pattern
        SongLayout(_, _) => Song
      }
  }
}

///|
/// Return the zero-based musical cycle position from the scheduler clock.
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
/// The state of the performance, without constructing a `PlayerView`.
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
pub fn Player::view(self : Player) -> PlayerView {
  let state = self.state()
  let song = self.session.song()
  let (pending, skipped) = if self.session is Playing(_) ||
    self.session is Paused(_) {
    (
      self.scheduler.pending_material_change_count(),
      self.scheduler.skipped_material_change_count(),
    )
  } else {
    (0, 0)
  }
  {
    state,
    source: song.map(song => song.source),
    bpm: match song {
      Some(song) => song.tempo.bpm()
      None => self.scheduler.bpm()
    },
    sample_position: match self.session {
      Ended(_, position, _) => position.to_double()
      Empty | Ready(_) => 0.0
      _ => self.scheduler.sample_counter().to_double()
    },
    pending_materials: pending,
    skipped_materials: skipped,
  }
}

///|
pub fn PlayerError::message(self : PlayerError) -> String {
  match self {
    InvalidSource(message) | Failed(message) => message
    RestartRequired => "song layout changed; restart required"
    NoSong => "no Current song; update source before Play"
    TransportRange => "tempo change exceeds transport range"
    UnsupportedFormat => "the player cannot run this sample rate and block size"
  }
}

///|
/// Render the next block into `left()` and `right()`; `false` in Fault, whose
/// reason `fault()` gives. Empty, Ready and Paused render silence without
/// advancing. A Playing finite song becomes Ended at its end; Ended keeps
/// rendering its tails. A scheduler transport error silences the block, kills
/// every voice and leaves the player in Fault; a song end the transport cannot
/// reach leaves it in Fault after the block rendered. It returns a `Bool` rather than raising because it runs on
/// the audio thread every block, and a `Result` there cost one construction
/// per block; the reason stays in `fault()`.
pub fn Player::process(self : Player) -> Bool {
  self.left.fill(0.0)
  self.right.fill(0.0)
  match self.session {
    Empty | Ready(_) | Paused(_) => return true
    Fault(_) => return false
    Playing(_) | Ended(_, _, _) => ()
  }
  self.scheduler.render_block_with_send(
    self.left,
    self.right,
    self.send_left,
    self.send_right,
  )
  if self.scheduler.last_transport_error() is Some(_) {
    self.session = Fault("transport range exhausted")
    self.left.fill(0.0)
    self.right.fill(0.0)
    self.scheduler.kill_all_voices()
    return false
  }
  self.reverb.process(
    self.context,
    self.send_left,
    self.send_right,
    self.wet_left,
    self.wet_right,
  )
  for i in 0..<self.context.block_size() {
    self.left.set(i, (self.left.get(i) + self.wet_left.get(i)) * self.gain)
    self.right.set(i, (self.right.get(i) + self.wet_right.get(i)) * self.gain)
  }
  if self.session is Playing(song) && song.finite_end() is Some(end_) {
    let scheduler = self.scheduler
    match scheduler.sample_at(end_) {
      Ok(end_sample) if scheduler.sample_counter() >= end_sample =>
        self.session = Ended(song, end_sample, end_.to_double())
      Ok(_) => ()
      Err(_) => {
        self.session = Fault("song end exceeds transport range")
        return false
      }
    }
  }
  true
}

///|
/// Why the player is in Fault; `None` in every other state.
pub fn Player::fault(self : Player) -> String? {
  match self.session {
    Fault(message) => Some(message)
    _ => None
  }
}

///|
/// The left channel of the last rendered block.
pub fn Player::left(self : Player) -> @moondsp.AudioBuffer {
  self.left
}

///|
/// The right channel of the last rendered block.
pub fn Player::right(self : Player) -> @moondsp.AudioBuffer {
  self.right
}

///|
/// Change the tempo at the next unrendered sample, keeping the musical
/// position. A change the accepted song cannot take changes nothing.
pub fn Player::set_tempo(self : Player, bpm : Double) -> Unit raise PlayerError {
  let tempo = tempo_of(bpm)
  if self.session.song() is Some(song) {
    self.check_repeat_span(song.span, tempo)
    if song.finite_end() is Some(end_) {
      guard tempo.sample_at_start(end_, sample_rate=self.context.sample_rate())
        is Ok(_) else {
        raise Failed("song end exceeds transport range")
      }
    }
  }
  let end_ = match self.session.song() {
    Some(song) => song.finite_end()
    None => None
  }
  guard self.scheduler.set_tempo(tempo, end_?) is Ok(_) else {
    raise TransportRange
  }
  if self.session.song() is Some(song) {
    let next = { ..song, tempo, }
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
/// The ring of playback onsets the player records when it is enabled.
pub fn Player::onsets(self : Player) -> @scheduler.OnsetBuffer {
  self.onsets
}

///|
/// The ring of control-signal values the player records when it is enabled.
pub fn Player::signals(self : Player) -> @scheduler.SignalBuffer {
  self.signals
}
