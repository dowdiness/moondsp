///|
/// The source accepted by the player, after pattern bindings and declarations
/// have been separated from the playable body.
/// A song's sections are lowered while parsing: to exact snapshots when the
/// source is tracked, to anonymous runtime patterns otherwise.
pub enum PlayBody {
  Pattern(@pattern.PatternDoc)
  Arrangement(@song.Song[@pattern.Pat[@pattern.ControlMap]], Bool)
  ExactArrangement(@song.Song[@pattern.PatternSnapshotWithOrigins], Bool)
}

///|
/// Tempo of a source that declares no `bpm(...)`.
pub const DEFAULT_BPM : Double = 120.0

///|
pub struct PlaySource {
  priv body : PlayBody
  priv bpm : Double
}

///|
pub fn PlaySource::body(self : PlaySource) -> PlayBody {
  self.body
}

///|
pub fn PlaySource::bpm(self : PlaySource) -> Double {
  self.bpm
}

///|
fn parse_play_bpm_declaration(parser : Parser) -> Double raise ParseError {
  let start = parser.pos
  guard parser.match_keyword("bpm(") else {
    raise ParseError("position \{start}: expected bpm(...)")
  }
  parser.skip_whitespace()
  let value = parser.read_number()
  parser.skip_whitespace()
  parser.expect_char(')')
  parser.skip_whitespace()
  parser.expect_char(';')
  guard value > 0.0 else {
    raise ParseError(
      "position \{start}: bpm() requires a positive number, got \{value}",
    )
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
pub fn parse_play_source(
  input : String,
  previous~ : @pattern.PatternDoc? = None,
  query_window? : @pattern.QueryWindow,
) -> Result[PlaySource, String] {
  parse_play_source_with_origins(
    input,
    previous,
    query_window,
    origins=None,
    syntax_depth_limit=None,
  )
}

///|
fn parse_play_source_with_origins(
  input : String,
  previous : @pattern.PatternDoc?,
  query_window : @pattern.QueryWindow?,
  origins~ : SourceMap? = None,
  syntax_depth_limit~ : Int32? = None,
) -> Result[PlaySource, String] {
  guard !input.is_empty() else { return Err("empty input") }
  // A bounded parse, by syntax depth or by playback admission, first bounds the text.
  if syntax_depth_limit is Some(_) || query_window is Some(_) {
    check_playback_source_size(input) catch {
      ParseError(message) => return Err(message)
    }
  }
  let admission = query_window.map(window => {
    PlaybackAdmission(window.span().to_double())
  })
  let parser = Parser(input, admission~, syntax_depth_limit~)
  let builder = MiniDocBuilder(previous~, origins~)
  let mut authored_bpm : Double? = None
  while true {
    parser.parse_bindings(builder) catch {
      ParseError(msg) => return Err(msg)
    }
    parser.skip_whitespace()
    guard parser.match_keyword("bpm(") else { break }
    guard authored_bpm is None else { return Err("duplicate bpm(...)") }
    parser.pos -= 4
    authored_bpm = Some(
      parse_play_bpm_declaration(parser) catch {
        ParseError(msg) => return Err(msg)
      },
    )
  }
  if parser.match_keyword("song(") {
    parser.pos -= 5
    let arrangement = if origins is Some(_) {
      parser
      .parse_play_song(builder, admission, authored_bpm, lower=doc => {
        doc.lower_with_origins()
      })
      .map(song => (ExactArrangement(song.0, song.1), song.2))
    } else {
      parser
      .parse_play_song(builder, admission, authored_bpm, lower=doc => {
        doc.lower().pat()
      })
      .map(song => (Arrangement(song.0, song.1), song.2))
    }
    arrangement.map(arrangement => { body: arrangement.0, bpm: arrangement.1, })
  } else {
    guard !parser.at_end() else { return Err("empty input") }
    let doc = match mini_collect_dollar_stack_lines(input, start=parser.pos) {
      Err(msg) => return Err(msg)
      Ok(Some(lines)) =>
        match parse_doc_dollar_stack_program(input, parser, builder, lines) {
          Ok(doc) => doc
          Err(msg) => return Err(msg)
        }
      Ok(None) => {
        let doc = parser.parse_doc_expr(builder) catch {
          ParseError(msg) => return Err(msg)
        }
        parser.skip_whitespace()
        guard parser.at_end() else {
          return Err(
            "position \{parser.pos}: unexpected trailing input '\{input[parser.pos:].to_owned()}'",
          )
        }
        doc
      }
    }
    Ok({ body: Pattern(doc), bpm: authored_bpm.unwrap_or(DEFAULT_BPM), })
  }
}

///|
/// Parse a `song(...)` body and its optional `.repeat()`, returning the song,
/// whether it repeats, and its tempo.
fn[C] Parser::parse_play_song(
  self : Parser,
  builder : MiniDocBuilder,
  admission : PlaybackAdmission?,
  authored_bpm : Double?,
  lower~ : (@pattern.PatternDoc) -> C raise @pattern.PatternDocError,
) -> Result[(@song.Song[C], Bool, Double), String] {
  let parsed = self.parse_song_expr(builder, lower~) catch {
    ParseError(msg) => return Err(msg)
  }
  self.skip_whitespace()
  let repeating = self.match_keyword(".repeat()")
  self.skip_whitespace()
  guard self.at_end() else {
    return Err(
      "position \{self.pos}: unexpected trailing input '\{self.input[self.pos:].to_owned()}'",
    )
  }
  guard !(authored_bpm is Some(_) && parsed.bpm() is Some(_)) else {
    return Err("duplicate bpm(...)")
  }
  let bpm = match authored_bpm {
    Some(value) => value
    None => parsed.bpm().unwrap_or(DEFAULT_BPM)
  }
  if admission is Some(admission) {
    admission.arrangement(parsed.song(), repeating) catch {
      ParseError(message) => return Err(message)
    }
  }
  Ok((parsed.song(), repeating, bpm))
}
