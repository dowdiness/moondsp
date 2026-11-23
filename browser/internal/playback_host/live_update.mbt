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
/// Internal observation value, projected into the browser's public enum.
#derive(Eq, Debug)
pub enum PlaybackMode {
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
pub(all) enum PlayState {
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
pub(all) enum PlayerError {
  InvalidSource(String)
  RestartRequired
  NoSong
  TransportRange
  Failed(String)
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
) -> Result[Unit, PlayerError] {
  guard span is Repeating(period) else { return Ok(()) }
  let block_span = match
    tempo.span_for_samples(
      self.context.block_size(),
      sample_rate=self.context.sample_rate(),
    ) {
    Ok(span) => span
    Err(_) => return Err(TransportRange)
  }
  guard period >= block_span else {
    return Err(
      InvalidSource("repeated song must span at least one audio block"),
    )
  }
  Ok(())
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
) -> Result[PreparedSong, PlayerError] {
  // Admission covers every supported future tempo, including the demo control.
  let prepared = match
    input.compile(query_window=self.scheduler.max_query_window()) {
    Ok(prepared) => prepared
    Err(message) => return Err(InvalidSource(message))
  }
  let source = input.source()
  let prepared = match prepared {
    @mini.PreparedPlayback::Pattern(snapshot, bpm) => {
      let tempo = match @scheduler.Tempo::from_bpm(bpm) {
        Ok(tempo) => tempo
        Err(_) => return Err(InvalidSource("tempo must be 0.001..1000 BPM"))
      }
      Ok({
        source,
        tempo,
        layout: PatternLayout,
        snapshot: @scheduler.PlaybackSnapshot::pattern_with_origins(snapshot),
        span: Continuous,
      })
    }
    @mini.PreparedPlayback::Runtime(parsed) => {
      let tempo = match @scheduler.Tempo::from_bpm(parsed.bpm()) {
        Ok(tempo) => tempo
        Err(_) => return Err(InvalidSource("tempo must be 0.001..1000 BPM"))
      }
      match parsed.body() {
        Pattern(doc) => {
          let snapshot = doc.lower() catch {
            error =>
              return Err(
                InvalidSource("could not lower source: \{Repr(error)}"),
              )
          }
          Ok({
            source,
            tempo,
            layout: PatternLayout,
            snapshot: @scheduler.PlaybackSnapshot::pattern(snapshot),
            span: Continuous,
          })
        }
        Arrangement(song, repeated) =>
          self.prepare_arrangement(source, tempo, song, repeated, snapshot => {
            @scheduler.SongMaterial::Runtime(snapshot)
          })
        ExactArrangement(song, repeated) =>
          self.prepare_arrangement(source, tempo, song, repeated, snapshot => {
            @scheduler.SongMaterial::Exact(snapshot)
          })
      }
    }
  }
  let song = match prepared {
    Err(error) => return Err(error)
    Ok(song) => song
  }
  guard song.snapshot.material_count() <= PLAYBACK_MATERIAL_LIMIT else {
    return Err(InvalidSource("playback source exceeds 256 material entries"))
  }
  Ok(song)
}

///|
fn[C : @song.SongContent] Player::prepare_arrangement(
  self : Player,
  source : String,
  tempo : @scheduler.Tempo,
  song : @song.Song[C],
  repeated : Bool,
  material : (@song.SongSnapshot[C]) -> @scheduler.SongMaterial,
) -> Result[PreparedSong, PlayerError] {
  guard song.duration() > @pattern.Rational::from_int(0) else {
    return Err(InvalidSource("song must end after its beginning"))
  }
  let span = if repeated {
    Repeating(song.duration())
  } else {
    Finite(song.duration())
  }
  match self.check_repeat_span(span, tempo) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let snapshot = song_update_snapshot(song) catch {
    error => return Err(InvalidSource(error.to_string()))
  }
  Ok({
    source,
    tempo,
    layout: song_layout(song, repeated),
    snapshot: if repeated {
      @scheduler.PlaybackSnapshot::repeat_song(material(snapshot))
    } else {
      @scheduler.PlaybackSnapshot::song(material(snapshot))
    },
    span,
  })
}

///|
/// All state-dependent planning and installation happen in this owner turn.
/// No prepared handle or execution plan can survive an intervening render.
fn Player::install(
  self : Player,
  song : PreparedSong,
  restart : Bool,
) -> Result[Unit, PlayerError] {
  match
    self.scheduler.accept_playback(
      song.snapshot,
      song.tempo,
      material_limit=PLAYBACK_MATERIAL_LIMIT,
      restart~,
      end_?=song.finite_end(),
    ) {
    Err(MaterialLimit) =>
      return Err(
        InvalidSource(
          "playback would retain more than 256 material entries; wait for their boundaries or Restart",
        ),
      )
    Err(Transport(_)) => return Err(TransportRange)
    Ok(_) => ()
  }
  if restart {
    self.reverb.reset()
    self.scheduler.kill_all_voices()
  }
  Ok(())
}

///|
/// Accept source without starting or rewinding the performance.
pub fn Player::update(
  self : Player,
  input : @mini.PlaybackInput,
) -> Result[Unit, PlayerError] {
  if self.session is Fault(message) {
    return Err(Failed(message))
  }
  let next = match self.prepare(input) {
    Ok(song) => song
    Err(error) => return Err(error)
  }
  match self.session {
    Empty | Ready(_) | Ended(_, _, _) =>
      if next.finite_end() is Some(end_) {
        match
          next.tempo.sample_at_start(
            end_,
            sample_rate=self.context.sample_rate(),
          ) {
          Err(_) => return Err(TransportRange)
          Ok(_) => ()
        }
      }
    Playing(_) | Paused(_) | Fault(_) => ()
  }
  match self.session {
    Playing(current) | Paused(current) => {
      guard current.layout == next.layout else { return Err(RestartRequired) }
      match self.install(next, false) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      self.session = match self.session {
        Paused(_) => Paused(next)
        _ => Playing(next)
      }
    }
    Ended(_, position, cycle) => self.session = Ended(next, position, cycle)
    Empty | Ready(_) => self.session = Ready(next)
    Fault(message) => return Err(Failed(message))
  }
  Ok(())
}

///|
/// Parse current editor source first; invalid input cannot reset a voice or clock.
pub fn Player::restart(
  self : Player,
  input : @mini.PlaybackInput,
) -> Result[Unit, PlayerError] {
  if self.session is Fault(message) {
    return Err(Failed(message))
  }
  let song = match self.prepare(input) {
    Ok(song) => song
    Err(error) => return Err(error)
  }
  match self.install(song, true) {
    Err(error) => Err(error)
    Ok(_) => {
      self.session = Playing(song)
      Ok(())
    }
  }
}

///|
pub fn Player::play(self : Player) -> Result[Unit, PlayerError] {
  match self.session {
    Empty => Err(NoSong)
    Fault(message) => Err(Failed(message))
    Playing(_) => Ok(())
    Paused(song) => {
      self.session = Playing(song)
      Ok(())
    }
    Ready(song) | Ended(song, _, _) =>
      match self.install(song, true) {
        Err(error) => Err(error)
        Ok(_) => {
          self.session = Playing(song)
          Ok(())
        }
      }
  }
}

///|
pub fn Player::pause(self : Player) -> Result[Unit, PlayerError] {
  match self.session {
    Empty => Err(NoSong)
    Fault(message) => Err(Failed(message))
    Playing(song) => {
      self.session = Paused(song)
      Ok(())
    }
    Ready(_) | Paused(_) | Ended(_, _, _) => Ok(())
  }
}

///|
/// Return the accepted source kind without constructing a `PlayerView`.
fn Player::mode(self : Player) -> PlaybackMode {
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
fn Player::cycle_position(self : Player) -> Double {
  match self.session {
    Empty | Ready(_) | Fault(_) => 0.0
    Playing(_) | Paused(_) => self.scheduler.cycle_position()
    Ended(_, _, cycle) => cycle
  }
}

///|
pub fn Player::view(self : Player) -> PlayerView {
  let state = match self.session {
    Empty => PlayState::Empty
    Ready(_) => Ready
    Playing(_) => Playing
    Paused(_) => Paused
    Ended(_, _, _) => Ended
    Fault(_) => Fault
  }
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
fn PlayerError::message(self : PlayerError) -> String {
  match self {
    InvalidSource(message) | Failed(message) => message
    RestartRequired => "song layout changed; restart required"
    NoSong => "no Current song; update source before Play"
    TransportRange => "tempo change exceeds transport range"
  }
}

///|
fn player_command(command : (Player) -> Result[Unit, PlayerError]) -> Int32 {
  guard player.val is Some(owner) else {
    return set_scheduler_parse_error("Player is not initialized")
  }
  match command(owner) {
    Ok(_) => set_scheduler_parse_success()
    Err(error) => {
      ignore(set_scheduler_parse_error(error.message()))
      if error is RestartRequired {
        2
      } else {
        1
      }
    }
  }
}

///|
fn take_playback_input() -> Result[@mini.PlaybackInput, String] {
  let result = if playback_input_overflow.val {
    Err("playback input exceeds 2097152 UTF-16 code units")
  } else {
    match input_chars_to_string(playback_input_chars) {
      Err(message) => Err(message)
      Ok(wire) => @mini.PlaybackInput::decode_wire(wire)
    }
  }
  playback_input_chars.clear()
  playback_input_overflow.val = false
  result
}

///|
pub fn player_update_input() -> Int32 {
  match take_playback_input() {
    Err(message) => set_scheduler_parse_error(message)
    Ok(input) => player_command(owner => owner.update(input))
  }
}

///|
pub fn player_restart_input() -> Int32 {
  match take_playback_input() {
    Err(message) => set_scheduler_parse_error(message)
    Ok(input) => player_command(owner => owner.restart(input))
  }
}

///|
pub fn player_play() -> Int32 {
  player_command(owner => owner.play())
}

///|
pub fn player_pause() -> Int32 {
  player_command(owner => owner.pause())
}

///|
pub fn player_state() -> Int32 {
  match player.val {
    None => 0
    Some(owner) =>
      match owner.session {
        Empty => 0
        Ready(_) => 1
        Playing(_) => 2
        Paused(_) => 3
        Ended(_, _, _) => 4
        Fault(_) => 5
      }
  }
}

///|
pub fn player_mode() -> PlaybackMode {
  match player.val {
    Some(owner) => owner.mode()
    None => None
  }
}

///|
pub fn scheduler_cycle_position() -> Double {
  match player.val {
    Some(owner) => owner.cycle_position()
    None => 0.0
  }
}

///|
pub fn player_pending_count() -> Int32 {
  match player.val {
    Some(owner) => owner.view().pending_materials
    None => 0
  }
}

///|
pub fn player_skipped_count() -> Int32 {
  match player.val {
    Some(owner) => owner.view().skipped_materials
    None => 0
  }
}

///|
pub fn scheduler_bpm() -> Double {
  match player.val {
    Some(owner) => owner.view().bpm
    None => 0.0
  }
}

///|
pub fn scheduler_sample_position() -> Double {
  match player.val {
    Some(owner) => owner.view().sample_position
    None => 0.0
  }
}

///|
pub fn player_onset_enable(enabled : Int32) -> Unit {
  if player.val is Some(owner) {
    owner.onsets.enable(enabled == 1)
  }
}

///|
pub fn player_onset_count() -> Int32 {
  match player.val {
    Some(owner) => owner.onsets.count()
    None => 0
  }
}

///|
/// Read the shared bounded ring; no array or binding path is copied.
pub fn player_onset_field(index : Int32, field : Int32) -> Double {
  guard index >= 0 else { return 0.0 }
  match player.val {
    None => 0.0
    Some(owner) => owner.onsets.field(index, field)
  }
}

///|
pub fn player_onset_clear() -> Unit {
  if player.val is Some(owner) {
    owner.onsets.clear()
  }
}

///|
pub fn player_onset_dropped() -> Double {
  match player.val {
    Some(owner) => owner.onsets.dropped()
    None => 0.0
  }
}

///|
pub fn player_signal_enable(enabled : Int32) -> Unit {
  if player.val is Some(owner) {
    owner.signals.enable(enabled == 1)
  }
}

///|
pub fn player_signal_count() -> Int32 {
  match player.val {
    Some(owner) => owner.signals.count()
    None => 0
  }
}

///|
/// Read one scalar field of the bounded signal-value ring.
pub fn player_signal_field(index : Int32, field : Int32) -> Double {
  match player.val {
    None => 0.0
    Some(owner) => owner.signals.field(index, field)
  }
}

///|
pub fn player_signal_clear() -> Unit {
  if player.val is Some(owner) {
    owner.signals.clear()
  }
}

///|
pub fn player_signal_dropped() -> Double {
  match player.val {
    Some(owner) => owner.signals.dropped()
    None => 0.0
  }
}
