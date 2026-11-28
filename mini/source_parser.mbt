///|
/// The source accepted by the player, after pattern bindings and declarations
/// have been separated from the playable body.
/// A song is lowered while parsing, its sections to `S`: tracked snapshots
/// when the source is tracked, untracked ones otherwise.
priv enum PlayBody[S] {
  Pattern(ScoreDoc)
  Arrangement(@song.Song[S], Bool)
}

///|
/// Tempo of a source that declares no `bpm(...)`.
pub const DEFAULT_BPM : Double = 120.0

///|
priv struct PlaySource[S] {
  body : PlayBody[S]
  bpm : Double
}

///|
fn[S] PlaySource::body(self : PlaySource[S]) -> PlayBody[S] {
  self.body
}

///|
fn[S] PlaySource::bpm(self : PlaySource[S]) -> Double {
  self.bpm
}

///|
/// The tempo of the `bpm(` statement written at `start`, read from after its
/// `(` through its `;`.
fn Parser::parse_bpm_statement(
  self : Parser,
  start : Int32,
) -> Double raise SourceProblem {
  self.skip_whitespace()
  let value = self.read_number()
  self.skip_whitespace()
  self.expect_char(')')
  self.skip_whitespace()
  self.expect_char(';')
  guard value > 0.0 else {
    raise Mistake(start, "bpm() requires a positive number, got \{value}")
  }
  value
}

///|
/// Parse one player source. Bindings use the existing mini parser and are
/// resolved before dispatching the body by its leading token (`song(` versus
/// an ordinary pattern expression); no parser fallback is used.
///
/// A top-level `bpm(number);` is optional. A song may also contain its
/// historical `bpm(number)` item, but declaring both is rejected.
/// Supplying `query_window` enables conservative browser playback admission.
/// It bounds source construction and every query up to that window,
/// including future conditional branches; no pattern queries are executed.
fn parse_untracked_source(
  input : String,
  query_window : @pattern.QueryWindow?,
) -> PlaySource[@pattern.UntrackedPatternSnapshot[@score.ScoreEvent]] raise SourceProblem {
  parse_source(input, query_window, origins=None, syntax_depth_limit=None, lower=doc => {
    doc.lower()
  })
}

///|
/// Parse a Draft's source with its source map: song sections are tracked.
fn parse_tracked_source(
  input : String,
  query_window : @pattern.QueryWindow?,
  origins : SourceMap,
) -> PlaySource[@pattern.TrackedPatternSnapshot[@score.ScoreEvent]] raise SourceProblem {
  parse_source(
    input,
    query_window,
    origins=Some(origins),
    syntax_depth_limit=Some(32),
    lower=doc => doc.lower_tracked(),
  )
}

///|
fn[S] parse_source(
  input : String,
  query_window : @pattern.QueryWindow?,
  origins~ : SourceMap?,
  syntax_depth_limit~ : Int32?,
  lower~ : (ScoreDoc) -> S raise @pattern.PatternDocError,
) -> PlaySource[S] raise SourceProblem {
  guard !input.is_empty() else { raise Mistake(0, "empty input") }
  // A bounded parse, by syntax depth or by playback admission, first bounds the text.
  if syntax_depth_limit is Some(_) || query_window is Some(_) {
    check_playback_source_size(input)
  }
  let admission = query_window.map(window => {
    PlaybackAdmission(window.span().to_double())
  })
  let parser = Parser(input, admission~, syntax_depth_limit~)
  let builder = MiniDocBuilder(origins~)
  // A top-level `bpm(...)` and where it was written.
  let mut authored_bpm : (Int32, Double)? = None
  // Where `song(` opens the body, when it does.
  let song_at : Int32? = while true {
    parser.parse_bindings(builder)
    parser.skip_whitespace()
    let at = parser.pos
    match parser.read_call(Declaration::parse) {
      Some(Bpm) => {
        guard authored_bpm is None else {
          raise Mistake(at, "duplicate bpm(...)")
        }
        authored_bpm = Some((at, parser.parse_bpm_statement(at)))
      }
      None =>
        break match parser.read_call(Arrangement::parse) {
          Some(Song) => Some(at)
          None => None
        }
    }
  } nobreak {
    None
  }
  let body_at = parser.pos
  if song_at is Some(song_at) {
    let (song, repeating, bpm) = parser.parse_play_song(
      song_at,
      builder,
      admission,
      authored_bpm,
      lower~,
    )
    { body: Arrangement(song, repeating), bpm, }
  } else {
    guard !parser.at_end() else { raise Mistake(body_at, "empty input") }
    let doc = match mini_collect_dollar_blocks(input, start=parser.pos) {
      Some(blocks) =>
        parse_doc_dollar_stack_program(input, parser, builder, blocks)
      None => {
        let doc = parser.parse_doc_expr(builder)
        parser.skip_whitespace()
        guard parser.at_end() else {
          raise Mistake(
            parser.pos,
            "unexpected trailing input '\{input[parser.pos:].to_owned()}'",
          )
        }
        doc
      }
    }
    {
      body: Pattern(doc),
      bpm: authored_bpm.map(declared => declared.1).unwrap_or(DEFAULT_BPM),
    }
  }
}

///|
/// Parse the `song(` body opened at `song_at`, from after its `(`, and its
/// optional `.repeat()`, returning the song, whether it repeats, and its tempo.
fn[C] Parser::parse_play_song(
  self : Parser,
  song_at : Int32,
  builder : MiniDocBuilder,
  admission : PlaybackAdmission?,
  authored_bpm : (Int32, Double)?,
  lower~ : (ScoreDoc) -> C raise @pattern.PatternDocError,
) -> (@song.Song[C], Bool, Double) raise SourceProblem {
  let parsed = self.parse_song_body(song_at, builder, lower~)
  self.skip_whitespace()
  let before_method = self.pos
  let repeating = if !self.at_end() && self.input[self.pos] == '.' {
    self.pos += 1
    match self.read_call(ArrangementMethod::parse) {
      Some(Repeat) => {
        self.expect_char(')')
        true
      }
      None => {
        self.pos = before_method
        false
      }
    }
  } else {
    false
  }
  self.skip_whitespace()
  guard self.at_end() else {
    raise Mistake(
      self.pos,
      "unexpected trailing input '\{self.input[self.pos:].to_owned()}'",
    )
  }
  if authored_bpm is Some((at, _)) && parsed.bpm() is Some(_) {
    raise Mistake(at, "duplicate bpm(...)")
  }
  let bpm = match authored_bpm {
    Some((_, value)) => value
    None => parsed.bpm().unwrap_or(DEFAULT_BPM)
  }
  if admission is Some(admission) {
    admission.arrangement(parsed.song(), repeating)
  }
  (parsed.song(), repeating, bpm)
}
