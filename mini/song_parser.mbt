///|
priv struct SongPartSpec {
  at : Int32
  /// The id written with `part_id`, if any.
  id : String?
  name : String
  section_name : String
  section_at : Int32
  /// The written start and where it was written.
  start : (@pattern.Rational, Int32)?
}

///|
priv struct SongFillSpec {
  at : Int32
  prefix : String
  section_name : String
  section_at : Int32
}

///|
/// Song parse result with optional playback metadata: the song laid out
/// with the identities its source declares (see `song_section_id`).
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
  check_part_identities(part_specs)
  let parts = [ for spec in part_specs => spec.to_part(sections) ]
  let mut song = song_of(parts, at=song_start)
  // Names by identity, so a fill that repeats a part says which.
  let taken : Map[String, String] = Map([])
  for spec in part_specs {
    taken[spec.identity()] = spec.name
  }
  for fill in fill_specs {
    let section = resolve_song_section(
      sections,
      fill.section_name,
      at=fill.section_at,
    )
    let gaps = song.gap_spans()
    if self.admission is Some(_) && parts.length() + gaps.length() > 128 {
      raise OverLimit(Occurrences)
    }
    for index, gap in gaps {
      let name = "\{fill.prefix}:\{index}"
      let identity = identity_text(name)
      if taken.get(identity) is Some(existing) {
        raise Mistake(
          fill.at,
          if existing == name {
            "duplicate song part '\{name}'"
          } else {
            "duplicate song part id '\{name}'"
          },
        )
      }
      taken[identity] = name
      let section = resized_section(section, gap.duration())
      // A gap lies inside the song, so it starts at or after 0.
      let part = @song.SongPart::at(
        id=occurrence_id(identity),
        start=gap.begin,
        section~,
      ) catch {
        NegativeStart => raise Internal("fill '\{name}' starts before zero")
      }
      parts.push(part)
    }
    song = song_of(parts, at=fill.at)
  }
  { song, bpm: bpm_values.get(0), }
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
      let (name, section) = self.parse_song_section(
        item_start,
        builder~,
        lower~,
      )
      if sections.contains(name) {
        raise Mistake(item_start, "duplicate section '\{name}'")
      }
      sections[name] = section
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
) -> (String, @song.Section[C]) raise SourceProblem {
  self.skip_whitespace()
  let name = self.read_quoted_string()
  self.expect_comma()
  let length_cycles = self.read_song_rational("section length")
  self.expect_comma()
  // A section plays only within its occurrences, which `arrangement` bounds,
  // so it is not overlaid with the other sections.
  let syntax = resolve_mini_expr(self.parse_syntax_expr(), self.bindings)
  if self.admission is Some(admission) {
    admission.sections[song_section_id(name).value()] = admission.expression(
      syntax,
    )
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
  let section = @song.Section(id=song_section_id(name), length_cycles~, layers=[
    @song.SectionLayer(id=main_layer(), content~),
  ]) catch {
    NonPositiveLength => raise length_error
    _ => raise compile_error
  }
  (name, section)
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
  let id = self.read_quoted_string()
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
) -> (@pattern.Rational, Int32)? raise SourceProblem {
  self.skip_whitespace()
  let start = if !self.at_end() && self.input[self.pos] == ',' {
    self.pos += 1
    self.skip_whitespace()
    let at = self.pos
    Some((self.read_song_rational("part start"), at))
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
/// `identity`, already in the identity alphabet and checked non-empty.
fn occurrence_id(identity : String) -> @identity.OccurrenceId {
  @identity.OccurrenceId::from_string(identity) catch {
    _ => abort("encoded part names are valid identities")
  }
}

///|
/// The identity a part declares: its `part_id`, otherwise its name.
fn SongPartSpec::identity(self : SongPartSpec) -> String {
  identity_text(self.id.unwrap_or(self.name))
}

///|
/// Every part has an identity, and no two parts share one. A repeat is
/// reported where it repeats: as a repeated name when neither part wrote a
/// `part_id`, otherwise as a repeated id.
fn check_part_identities(
  specs : Array[SongPartSpec],
) -> Unit raise SourceProblem {
  let seen : Map[String, SongPartSpec] = Map([])
  for spec in specs {
    let identity = spec.identity()
    guard !identity.is_empty() else {
      raise Mistake(
        spec.at,
        if spec.id is Some(_) {
          "song part id cannot be empty"
        } else {
          "song part requires a name"
        },
      )
    }
    if seen.get(identity) is Some(first) {
      raise Mistake(
        spec.at,
        if first.id is None && spec.id is None {
          "duplicate song part '\{spec.name}'"
        } else {
          "duplicate song part id '\{spec.id.unwrap_or(spec.name)}'"
        },
      )
    }
    seen[identity] = spec
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
  let id = occurrence_id(self.identity())
  match self.start {
    Some((start, at)) =>
      @song.SongPart::at(id~, start~, section~) catch {
        NegativeStart => raise Mistake(at, "part start cannot be negative")
      }
    None => @song.SongPart(id~, section~)
  }
}

///|
/// The song `parts` lay out. `check_part_identities` already reported a
/// repeated part where it repeats.
fn[C] song_of(
  parts : Array[@song.SongPart[C]],
  at~ : Int32,
) -> @song.Song[C] raise SourceProblem {
  @song.Song(parts~) catch {
    EmptySong => raise Mistake(at, "song() requires at least one part")
    DuplicateOccurrence(id) =>
      raise Internal("song part '\{id}' was not checked for repeats")
  }
}

///|
/// `section` lasting `length` cycles, as a fill occurrence plays it.
fn[C] resized_section(
  section : @song.Section[C],
  length : @pattern.Rational,
) -> @song.Section[C] raise SourceProblem {
  @song.Section(
    id=section.id(),
    length_cycles=length,
    rate=section.rate(),
    layers=section.layers().to_owned(),
  ) catch {
    _ => raise Internal("fill of section '\{section.id().value()}'")
  }
}

///|
/// The one layer of a Mini section.
fn main_layer() -> @identity.SectionLayerId {
  @identity.SectionLayerId::from_string("main") catch {
    _ => abort("valid layer id")
  }
}

///|
/// A section's identity is its name.
fn song_section_id(name : String) -> @identity.SectionId {
  @identity.SectionId::from_string("section:" + identity_text(name)) catch {
    _ => abort("encoded section names are valid identities")
  }
}

///|
/// `name` in the identity alphabet: code units outside it, and `.` itself,
/// are written as unpadded lowercase hex between dots (`.e9.`), so distinct names stay distinct and a name
/// already in the alphabet without `.` is unchanged.
fn identity_text(name : String) -> String {
  let encoded = StringBuilder()
  for index in 0..<name.length() {
    let code = name[index].to_int()
    let plain = (code >= 'a'.to_int() && code <= 'z'.to_int()) ||
      (code >= 'A'.to_int() && code <= 'Z'.to_int()) ||
      (code >= '0'.to_int() && code <= '9'.to_int()) ||
      code == '_'.to_int() ||
      code == '-'.to_int() ||
      code == ':'.to_int()
    if plain {
      encoded.write_char(name[index].unsafe_to_char())
    } else {
      encoded.write_string(".\{code.to_string(radix=16)}.")
    }
  }
  encoded.to_string()
}
