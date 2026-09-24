///|
const PLAYBACK_MATERIAL_LIMIT = 256

///|
priv struct PlaybackLayoutRow {
  id : String
  name : String
  section : String
  start : @pattern.Rational
  length : @pattern.Rational
  rate : @pattern.Rational
} derive(Eq)

///|
priv enum PlaybackLayout {
  PatternLayout
  SongLayout(Array[PlaybackLayoutRow], Bool)
} derive(Eq)

///|
priv struct PreparedRoute {
  target : SoundPool
  snapshot : @scheduler.PlaybackSnapshot
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
  doc : @pattern.PatternDoc[@pattern.ControlMap]?
  routes : Array[PreparedRoute]
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
pub enum PlaybackMode {
  None
  Pattern
  Song
} derive(Eq, Debug)

///|
pub(all) enum PlayState {
  Empty
  Ready
  Playing
  Paused
  Ended
  Fault
} derive(Eq, Debug)

///|
pub(all) enum PlayerError {
  InvalidSource(String)
  RestartRequired
  NoSong
  TransportRange
  Failed(String)
} derive(Eq, Debug)

///|
pub struct PlayerView {
  state : PlayState
  source : String?
  bpm : Double
  sample_position : Double
  pending_materials : Int
  skipped_materials : Int
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
fn song_layout(
  song : @song.Song[@pattern.ControlMap],
  repeated : Bool,
) -> PlaybackLayout {
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
fn song_update_snapshot(
  song : @song.Song[@pattern.ControlMap],
) -> @song.SongSnapshot[@pattern.ControlMap] raise {
  let parts = song
    .occurrences()
    .map(o => {
      let section = @song.SectionDoc::single(
        id=@identity.SectionId::from_string("live:" + o.id().value()),
        name=o.section().name(),
        length_cycles=o.section().length_cycles(),
        scope=o.section().scope(),
        layer_id=@identity.SectionLayerId::from_string("live:body"),
        body=o.section().body(),
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
  let previous = match self.session.song() {
    Some(song) => song.doc
    None => None
  }
  // Admission covers every supported future tempo, including the demo control.
  let maximum_tempo = match @scheduler.Tempo::from_bpm(1000.0) {
    Ok(tempo) => tempo
    Err(_) => return Err(TransportRange)
  }
  let max_query_span = match
    maximum_tempo.span_for_samples(
      self.context.block_size(),
      sample_rate=self.context.sample_rate(),
    ) {
    Ok(span) => span
    Err(_) => return Err(TransportRange)
  }
  let prepared = match
    input.compile(max_query_span=Some(max_query_span), previous~) {
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
      let routes = self.routes.map(route => {
        let selected = match route.selector {
          RouteSynth => snapshot.select_control("note")
          RouteSound(code) => snapshot.select_control("sound", value=code)
        }
        {
          target: route.pool,
          snapshot: @scheduler.PlaybackSnapshot::pattern_with_origins(selected),
        }
      })
      Ok({
        source,
        tempo,
        layout: PatternLayout,
        doc: None,
        routes,
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
          let routes = self.routes.map(route => {
            let selected = match route.selector {
              RouteSynth => snapshot.select_control("note")
              RouteSound(code) => snapshot.select_control("sound", value=code)
            }
            {
              target: route.pool,
              snapshot: @scheduler.PlaybackSnapshot::pattern(selected),
            }
          })
          Ok({
            source,
            tempo,
            layout: PatternLayout,
            doc: Some(doc),
            routes,
            span: Continuous,
          })
        }
        Arrangement(song, repeated) => {
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
          let routes : Array[PreparedRoute] = []
          for route in self.routes {
            let routed = match filter_song_for_route(route.selector, song) {
              Ok(song) => song
              Err(message) => return Err(InvalidSource(message))
            }
            let snapshot = song_update_snapshot(routed) catch {
              error => return Err(InvalidSource(error.to_string()))
            }
            routes.push({
              target: route.pool,
              snapshot: if repeated {
                @scheduler.PlaybackSnapshot::repeat_song(snapshot)
              } else {
                @scheduler.PlaybackSnapshot::song(snapshot)
              },
            })
          }
          Ok({
            source,
            tempo,
            layout: song_layout(song, repeated),
            doc: None,
            routes,
            span,
          })
        }
      }
    }
  }
  let song = match prepared {
    Err(error) => return Err(error)
    Ok(song) => song
  }
  guard song.routes.all(route => {
    route.snapshot.material_count() <= PLAYBACK_MATERIAL_LIMIT
  }) else {
    return Err(InvalidSource("playback source exceeds 256 material entries"))
  }
  Ok(song)
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
    @scheduler.accept_playback_all(
      song.routes.map(route => (route.target.scheduler, route.snapshot)),
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
    for route in song.routes {
      route.target.pool.kill_all()
    }
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
/// Return the zero-based musical cycle position from the route clock.
///
/// Ready and Empty are anchored at zero. Paused reads the frozen clock, and
/// Ended reports the accepted finite song's exact musical endpoint rather than
/// deriving it from a BPM/sample approximation.
fn Player::cycle_position(self : Player) -> Double {
  match self.session {
    Empty | Ready(_) | Fault(_) => 0.0
    Playing(_) | Paused(_) => self.schedulers[0].cycle_position()
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
  // Pattern control projection and song route filtering preserve each
  // material's source identity, period, and transition boundary. Every route
  // therefore observes the same transition set (with route-local content);
  // do not count six copies.
  let mut pending = 0
  let mut skipped = 0
  if self.session is Playing(_) || self.session is Paused(_) {
    for scheduler in self.schedulers {
      pending = Int::max(pending, scheduler.pending_material_change_count())
      skipped = Int::max(skipped, scheduler.skipped_material_change_count())
    }
  }
  {
    state,
    source: song.map(song => song.source),
    bpm: match song {
      Some(song) => song.tempo.bpm()
      None => self.schedulers[0].bpm()
    },
    sample_position: match self.session {
      Ended(_, position, _) => position.to_double()
      Empty | Ready(_) => 0.0
      _ => self.schedulers[0].sample_counter().to_double()
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
fn player_command(command : (Player) -> Result[Unit, PlayerError]) -> Int {
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
pub fn player_update_input() -> Int {
  match take_playback_input() {
    Err(message) => set_scheduler_parse_error(message)
    Ok(input) => player_command(owner => owner.update(input))
  }
}

///|
pub fn player_restart_input() -> Int {
  match take_playback_input() {
    Err(message) => set_scheduler_parse_error(message)
    Ok(input) => player_command(owner => owner.restart(input))
  }
}

///|
pub fn player_play() -> Int {
  player_command(owner => owner.play())
}

///|
pub fn player_pause() -> Int {
  player_command(owner => owner.pause())
}

///|
pub fn player_state() -> Int {
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
pub fn player_pending_count() -> Int {
  match player.val {
    Some(owner) => owner.view().pending_materials
    None => 0
  }
}

///|
pub fn player_skipped_count() -> Int {
  match player.val {
    Some(owner) => owner.view().skipped_materials
    None => 0
  }
}

///|
pub fn scheduler_bpm() -> Double {
  match player.val {
    Some(owner) => owner.view().bpm
    None => 60.0
  }
}

///|
pub fn scheduler_sample_position() -> Double {
  match player.val {
    Some(owner) => owner.view().sample_position
    None => 0.0
  }
}
