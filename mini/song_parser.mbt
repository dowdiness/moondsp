///|
priv struct SongPartSpec {
  at : Int32
  id : @identity.OccurrenceId?
  name : String
  section_name : String
  section_at : Int32
  start : @pattern.Rational?
}

///|
priv struct SongFillSpec {
  at : Int32
  prefix : String
  section_name : String
  section_at : Int32
}

///|
/// Song parse result with optional playback metadata.
pub struct ParsedSong[C] {
  song : @song.Song[C]
  bpm : Double?
}

///|
pub fn[C] ParsedSong::song(self : ParsedSong[C]) -> @song.Song[C] {
  self.song
}

///|
pub fn[C] ParsedSong::bpm(self : ParsedSong[C]) -> Double? {
  self.bpm
}

///|
/// Parse song mini-notation into the current song layout model.
///
/// Grammar:
/// - `song(item, ...)`
/// - `bpm(number)`
/// - `section("name", length, pattern_expr)`
/// - `part("occurrence", "section"[, start])`
/// - `part_id("id", "display name", "section"[, start])`
/// - `fill("prefix", "section")`
///
/// `pattern_expr` is the existing pattern mini-notation surface, such as
/// `s("bd sd")`, `note("60 64")`, `stack(...)`, and method chains. The result
/// keeps the optional `bpm(number)` metadata beside the layout. Sections are
/// untracked patterns, without source origins.
pub fn parse_song(
  input : String,
) -> Result[
  ParsedSong[@pattern.UntrackedPatternSnapshot[@score.ScoreEvent]],
  String,
] {
  guard !input.is_empty() else { return Err("empty input") }
  let p = Parser(input)
  let builder = MiniDocBuilder()
  p.parse_bindings(builder) catch {
    problem => return Err(problem.to_string())
  }
  p.skip_whitespace()
  let song_at = p.pos
  guard p.read_call(Arrangement::parse) is Some(Song) else {
    return Err("position \{song_at}: expected 'song('")
  }
  let result = p.parse_song_body(song_at, builder, lower=doc => doc.lower()) catch {
    problem => return Err(problem.to_string())
  }
  p.skip_whitespace()
  guard p.at_end() else {
    return Err(
      "position \{p.pos}: unexpected trailing input '\{input[p.pos:].to_owned()}'",
    )
  }
  Ok(result)
}

///|
/// The items of the `song(` opened at `song_start`, from after its `(`.
/// `lower` turns each section's compiled document into the song's content.
fn[C] Parser::parse_song_body(
  self : Parser,
  song_start : Int32,
  builder : MiniDocBuilder,
  lower~ : (ScoreDoc) -> C raise @pattern.PatternDocError,
) -> ParsedSong[C] raise SourceProblem {
  self.skip_whitespace()
  guard !self.at_end() && self.input[self.pos] != ')' else {
    raise Mistake(song_start, "song() requires at least one item")
  }
  let sections : Map[String, @song.Section[C]] = Map([])
  let part_specs : Array[SongPartSpec] = []
  let fill_specs : Array[SongFillSpec] = []
  let bpm_values : Array[Double] = []
  self.parse_song_item(
    sections,
    part_specs,
    fill_specs,
    bpm_values,
    builder~,
    lower~,
  )
  self.skip_whitespace()
  while !self.at_end() && self.input[self.pos] == ',' {
    self.pos += 1
    self.skip_whitespace()
    self.parse_song_item(
      sections,
      part_specs,
      fill_specs,
      bpm_values,
      builder~,
      lower~,
    )
    self.skip_whitespace()
  }
  self.expect_char(')')
  let mut song = build_song(part_specs, sections, at=song_start)
  for fill in fill_specs {
    let section = resolve_song_section(
      sections,
      fill.section_name,
      at=fill.section_at,
    )
    if self.admission is Some(_) &&
      song.occurrences().length() + song.gap_spans().length() > 128 {
      raise OverLimit(Occurrences)
    }
    song = song.fill_gaps(prefix=fill.prefix, section~) catch {
      error => raise song_mistake(error, [], at=fill.at)
    }
  }
  let bpm = match bpm_values.get(0) {
    Some(value) => Some(value)
    None => None
  }
  { song, bpm, }
}

///|
fn[C] Parser::parse_song_item(
  self : Parser,
  sections : Map[String, @song.Section[C]],
  part_specs : Array[SongPartSpec],
  fill_specs : Array[SongFillSpec],
  bpm_values : Array[Double],
  builder~ : MiniDocBuilder,
  lower~ : (ScoreDoc) -> C raise @pattern.PatternDocError,
) -> Unit raise SourceProblem {
  self.skip_whitespace()
  let item_start = self.pos
  guard self.read_call(SongItem::parse) is Some(item) else {
    let expected = or_list(SongItem::all().map(item => "\{item.name()}(...)"))
    raise Mistake(item_start, "expected \{expected}")
  }
  match item {
    Section => {
      let section = self.parse_song_section(item_start, builder~, lower~)
      if sections.contains(section.name()) {
        raise Mistake(item_start, "duplicate section '\{section.name()}'")
      }
      sections[section.name()] = section
    }
    Bpm => {
      if !bpm_values.is_empty() {
        raise Mistake(item_start, "duplicate bpm(...)")
      }
      bpm_values.push(self.parse_song_bpm(item_start))
    }
    PartId => part_specs.push(self.parse_song_part_with_id(item_start))
    Part => part_specs.push(self.parse_song_part(item_start))
    Fill => fill_specs.push(self.parse_song_fill(item_start))
  }
  if self.admission is Some(_) && part_specs.length() > 128 {
    raise OverLimit(Occurrences)
  }
}

///|
fn Parser::parse_song_bpm(
  self : Parser,
  item_start : Int32,
) -> Double raise SourceProblem {
  self.skip_whitespace()
  let value = self.read_number()
  self.skip_whitespace()
  self.expect_char(')')
  guard value > 0.0 else {
    raise Mistake(item_start, "bpm() requires a positive number, got \{value}")
  }
  value
}

///|
fn[C] Parser::parse_song_section(
  self : Parser,
  item_start : Int32,
  builder~ : MiniDocBuilder,
  lower~ : (ScoreDoc) -> C raise @pattern.PatternDocError,
) -> @song.Section[C] raise SourceProblem {
  self.skip_whitespace()
  let name = self.read_quoted_string()
  self.expect_comma()
  let length_cycles = self.read_song_rational("section length")
  self.expect_comma()
  // A section plays only within its occurrences, which `arrangement` bounds,
  // so it is not overlaid with the other sections.
  let syntax = resolve_mini_expr(self.parse_syntax_expr(), self.bindings)
  if self.admission is Some(admission) {
    admission.sections[name] = admission.expression(syntax)
  }
  let doc = compile_score(syntax, builder).doc()
  self.skip_whitespace()
  self.expect_char(')')
  let compile_error = Internal("could not compile section '\{name}'")
  let length_error = Mistake(
    item_start,
    "section '\{name}' requires a positive length",
  )
  let content = lower(doc) catch { _ => raise compile_error }
  @song.Section(
    name~,
    length_cycles~,
    scope=@song.TimeScope::identity(),
    body=@song.SectionBody::single(content),
  ) catch {
    _ => raise length_error
  }
}

///|
fn Parser::parse_song_part(
  self : Parser,
  item_start : Int32,
) -> SongPartSpec raise SourceProblem {
  self.skip_whitespace()
  let name = self.read_quoted_string()
  self.expect_comma()
  self.skip_whitespace()
  let section_at = self.pos
  let section_name = self.read_quoted_string()
  let start = self.read_optional_song_start()
  { at: item_start, id: None, name, section_name, section_at, start, }
}

///|
fn Parser::parse_song_part_with_id(
  self : Parser,
  item_start : Int32,
) -> SongPartSpec raise SourceProblem {
  self.skip_whitespace()
  let id_value = self.read_quoted_string()
  let id = parse_occurrence_id(id_value, item_start)
  self.expect_comma()
  let name = self.read_quoted_string()
  self.expect_comma()
  self.skip_whitespace()
  let section_at = self.pos
  let section_name = self.read_quoted_string()
  let start = self.read_optional_song_start()
  { at: item_start, id: Some(id), name, section_name, section_at, start, }
}

///|
fn Parser::parse_song_fill(
  self : Parser,
  item_start : Int32,
) -> SongFillSpec raise SourceProblem {
  self.skip_whitespace()
  let prefix = self.read_quoted_string()
  self.expect_comma()
  self.skip_whitespace()
  let section_at = self.pos
  let section_name = self.read_quoted_string()
  self.skip_whitespace()
  self.expect_char(')')
  { at: item_start, prefix, section_name, section_at, }
}

///|
fn Parser::read_optional_song_start(
  self : Parser,
) -> @pattern.Rational? raise SourceProblem {
  self.skip_whitespace()
  let start = if !self.at_end() && self.input[self.pos] == ',' {
    self.pos += 1
    self.skip_whitespace()
    Some(self.read_song_rational("part start"))
  } else {
    None
  }
  self.skip_whitespace()
  self.expect_char(')')
  start
}

///|
fn Parser::expect_comma(self : Parser) -> Unit raise SourceProblem {
  self.skip_whitespace()
  self.expect_char(',')
  self.skip_whitespace()
}

///|
fn Parser::read_song_rational(
  self : Parser,
  label : String,
) -> @pattern.Rational raise SourceProblem {
  self.skip_whitespace()
  let value_start = self.pos
  let num = self.read_song_int(value_start, label)
  let mut den = 1
  if !self.at_end() && self.input[self.pos] == '/' {
    self.pos += 1
    den = self.read_song_int(value_start, label)
  }
  guard den != 0 else {
    raise Mistake(value_start, "\{label} denominator cannot be zero")
  }
  @pattern.Rational(num.to_int64(), den.to_int64())
}

///|
fn Parser::read_song_int(
  self : Parser,
  err_pos : Int32,
  label : String,
) -> Int32 raise SourceProblem {
  let start = self.pos
  if !self.at_end() && self.input[self.pos] == '-' {
    self.pos += 1
  }
  let digits_start = self.pos
  while !self.at_end() &&
        self.input[self.pos] >= '0' &&
        self.input[self.pos] <= '9' {
    self.pos += 1
  }
  guard self.pos > digits_start else {
    self.pos = start
    raise Mistake(err_pos, "\{label} requires an integer")
  }
  let s = self.input[start:self.pos].to_owned()
  let mut value = 0
  let mut index = 0
  let negative = !s.is_empty() && s[0] == '-'
  if negative {
    index = 1
  }
  while index < s.length() {
    value = value * 10 + (s[index].to_int() - '0'.to_int())
    index += 1
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
fn parse_occurrence_id(
  value : String,
  pos : Int32,
) -> @identity.OccurrenceId raise SourceProblem {
  @identity.OccurrenceId::from_string(value) catch {
    _ => raise Mistake(pos, "invalid occurrence id '\{value}'")
  }
}

///|
fn[C] resolve_song_section(
  sections : Map[String, @song.Section[C]],
  name : String,
  at~ : Int32,
) -> @song.Section[C] raise SourceProblem {
  match sections.get(name) {
    Some(section) => section
    None => raise Mistake(at, "unknown song section '\{name}'")
  }
}

///|
fn[C] SongPartSpec::to_part(
  self : SongPartSpec,
  sections : Map[String, @song.Section[C]],
) -> @song.SongPart[C] raise SourceProblem {
  let section = resolve_song_section(
    sections,
    self.section_name,
    at=self.section_at,
  )
  match (self.id, self.start) {
    (Some(id), Some(start)) =>
      @song.SongPart::with_id_at(id~, start~, name=self.name, section~)
    (Some(id), None) => @song.SongPart::with_id(id~, name=self.name, section~)
    (None, Some(start)) => @song.SongPart::at(start~, name=self.name, section~)
    (None, None) => @song.SongPart(name=self.name, section~)
  }
}

///|
fn[C] build_song(
  specs : Array[SongPartSpec],
  sections : Map[String, @song.Section[C]],
  at~ : Int32,
) -> @song.Song[C] raise SourceProblem {
  let parts = [ for spec in specs => spec.to_part(sections) ]
  @song.Song(parts~) catch {
    error => raise song_mistake(error, specs, at~)
  }
}

///|
/// A song the author arranged inconsistently. A repeated part is reported
/// where it repeats; anything else at `at`.
fn song_mistake(
  error : @song.SongBuildError,
  specs : Array[SongPartSpec],
  at~ : Int32,
) -> SourceProblem {
  // The first part that repeats an earlier one.
  let repeated = (same : (SongPartSpec) -> Bool) => {
    let mut seen = false
    for spec in specs {
      if same(spec) {
        if seen {
          return spec.at
        }
        seen = true
      }
    }
    at
  }
  match error {
    EmptySong => Mistake(at, "song() requires at least one part")
    DuplicateOccurrence(name) =>
      Mistake(
        repeated(spec => spec.name == name),
        "duplicate song part '\{name}'",
      )
    DuplicateOccurrenceId(id) =>
      Mistake(
        repeated(spec => spec.id is Some(own) && own.value() == id),
        "duplicate song part id '\{id}'",
      )
    InvalidOccurrenceId(id) => Mistake(at, "invalid song part id '\{id}'")
  }
}
