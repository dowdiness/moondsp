///|
/// The source accepted by the player, after pattern bindings and declarations
/// have been separated from the playable body.
pub enum PlayBody {
  Pattern(@pattern.PatternDoc[@pattern.ControlMap])
  Arrangement(@song.Song[@pattern.ControlMap], Bool)
}

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
/// Supplying `max_query_span` enables conservative browser playback admission.
/// It bounds source construction and every query window up to that duration,
/// including future conditional branches; no pattern queries are executed.
pub fn parse_play_source(
  input : String,
  previous? : @pattern.PatternDoc[@pattern.ControlMap]? = None,
  max_query_span? : @pattern.Rational? = None,
) -> Result[PlaySource, String] {
  guard !input.is_empty() else { return Err("empty input") }
  let admission = match max_query_span {
    None => None
    Some(span) => {
      check_playback_source_size(input) catch {
        ParseError(message) => return Err(message)
      }
      guard span.num > 0L else { return Err("query span must be positive") }
      Some(PlaybackAdmission(span.to_double()))
    }
  }
  let parser = Parser::new(input, admission~)
  let builder = MiniDocBuilder::new(previous~)
  let mut authored_bpm : Double? = None
  while true {
    parser.parse_bindings(builder=Some(builder)) catch {
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
    for name, doc in parser.doc_bindings {
      let lowered = doc.lower() catch {
        _ => return Err("could not lower section binding '\{name}'")
      }
      parser.bindings[name] = lowered.pat()
    }
    let parsed = parser.parse_song_expr() catch {
      ParseError(msg) => return Err(msg)
    }
    parser.skip_whitespace()
    let repeating = if parser.match_keyword(".repeat()") { true } else { false }
    parser.skip_whitespace()
    guard parser.at_end() else {
      return Err(
        "position \{parser.pos}: unexpected trailing input '\{input[parser.pos:].to_owned()}'",
      )
    }
    guard !(authored_bpm is Some(_) && parsed.bpm() is Some(_)) else {
      return Err("duplicate bpm(...)")
    }
    let bpm = match authored_bpm {
      Some(value) => value
      None =>
        match parsed.bpm() {
          Some(value) => value
          None => 60.0
        }
    }
    if admission is Some(admission) {
      admission.arrangement(parsed.song(), repeating) catch {
        ParseError(message) => return Err(message)
      }
    }
    Ok({ body: Arrangement(parsed.song(), repeating), bpm, })
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
    Ok({ body: Pattern(doc), bpm: authored_bpm.unwrap_or(60.0), })
  }
}
