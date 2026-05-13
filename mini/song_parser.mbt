///|
priv struct SongPartSpec {
  id : @identity.OccurrenceId?
  name : String
  section_name : String
  start : @pattern.Rational?
}

///|
priv struct SongFillSpec {
  prefix : String
  section_name : String
}

///|
/// Parse song mini-notation into the current song layout model.
///
/// Grammar:
/// - `song(item, ...)`
/// - `section("name", length, pattern_expr)`
/// - `part("occurrence", "section"[, start])`
/// - `part_id("id", "display name", "section"[, start])`
/// - `fill("prefix", "section")`
///
/// `pattern_expr` is the existing pattern mini-notation surface, such as
/// `s("bd sd")`, `note("60 64")`, `stack(...)`, and method chains.
pub fn parse_song(
  input : String,
) -> Result[@song.Song[@pattern.ControlMap], String] {
  guard input.length() > 0 else { return Err("empty input") }
  let p = Parser::new(input)
  let result = p.parse_song_expr() catch { ParseError(msg) => return Err(msg) }
  p.skip_whitespace()
  guard p.at_end() else {
    return Err(
      "position \{p.pos}: unexpected trailing input '\{input[p.pos:].to_owned()}'",
    )
  }
  Ok(result)
}

///|
fn Parser::parse_song_expr(
  self : Parser,
) -> @song.Song[@pattern.ControlMap] raise ParseError {
  self.skip_whitespace()
  let song_start = self.pos
  guard self.match_keyword("song(") else {
    raise ParseError("position \{song_start}: expected 'song('")
  }
  self.skip_whitespace()
  guard !self.at_end() && self.input[self.pos] != ')' else {
    raise ParseError(
      "position \{song_start}: song() requires at least one item",
    )
  }
  let sections : Map[String, @song.Section[@pattern.ControlMap]] = {}
  let part_specs : Array[SongPartSpec] = []
  let fill_specs : Array[SongFillSpec] = []
  self.parse_song_item(sections, part_specs, fill_specs)
  self.skip_whitespace()
  while !self.at_end() && self.input[self.pos] == ',' {
    self.pos += 1
    self.skip_whitespace()
    self.parse_song_item(sections, part_specs, fill_specs)
    self.skip_whitespace()
  }
  self.expect_char(')')
  let parts : Array[@song.SongPart[@pattern.ControlMap]] = []
  for spec in part_specs {
    parts.push(spec.to_part(sections))
  }
  let mut song = build_song(parts)
  for fill in fill_specs {
    let section = resolve_song_section(sections, fill.section_name)
    let result = try? song.fill_gaps(prefix=fill.prefix, section~)
    song = match result {
      Ok(filled) => filled
      Err(_) =>
        raise ParseError("song fill '\{fill.prefix}' could not be applied")
    }
  }
  song
}

///|
fn Parser::parse_song_item(
  self : Parser,
  sections : Map[String, @song.Section[@pattern.ControlMap]],
  part_specs : Array[SongPartSpec],
  fill_specs : Array[SongFillSpec],
) -> Unit raise ParseError {
  self.skip_whitespace()
  let item_start = self.pos
  if self.match_keyword("section(") {
    let section = self.parse_song_section(item_start)
    if sections.contains(section.name()) {
      raise ParseError(
        "position \{item_start}: duplicate section '\{section.name()}'",
      )
    }
    sections[section.name()] = section
  } else if self.match_keyword("part_id(") {
    part_specs.push(self.parse_song_part_with_id(item_start))
  } else if self.match_keyword("part(") {
    part_specs.push(self.parse_song_part(item_start))
  } else if self.match_keyword("fill(") {
    fill_specs.push(self.parse_song_fill())
  } else {
    raise ParseError(
      "position \{item_start}: expected section(...), part(...), part_id(...), or fill(...)",
    )
  }
}

///|
fn Parser::parse_song_section(
  self : Parser,
  item_start : Int,
) -> @song.Section[@pattern.ControlMap] raise ParseError {
  self.skip_whitespace()
  let name = self.read_quoted_string()
  self.expect_comma()
  let length_cycles = self.read_song_rational("section length")
  self.expect_comma()
  let body = self.parse_expr()
  self.skip_whitespace()
  self.expect_char(')')
  let result = try? @song.Section(
    name~,
    length_cycles~,
    scope=@song.TimeScope::identity(),
    body=@song.SectionBody::single(body),
  )
  match result {
    Ok(section) => section
    Err(_) =>
      raise ParseError(
        "position \{item_start}: section '\{name}' requires a positive length",
      )
  }
}

///|
fn Parser::parse_song_part(
  self : Parser,
  item_start : Int,
) -> SongPartSpec raise ParseError {
  ignore(item_start)
  self.skip_whitespace()
  let name = self.read_quoted_string()
  self.expect_comma()
  let section_name = self.read_quoted_string()
  let start = self.read_optional_song_start()
  { id: None, name, section_name, start }
}

///|
fn Parser::parse_song_part_with_id(
  self : Parser,
  item_start : Int,
) -> SongPartSpec raise ParseError {
  self.skip_whitespace()
  let id_value = self.read_quoted_string()
  let id = parse_occurrence_id(id_value, item_start)
  self.expect_comma()
  let name = self.read_quoted_string()
  self.expect_comma()
  let section_name = self.read_quoted_string()
  let start = self.read_optional_song_start()
  { id: Some(id), name, section_name, start }
}

///|
fn Parser::parse_song_fill(self : Parser) -> SongFillSpec raise ParseError {
  self.skip_whitespace()
  let prefix = self.read_quoted_string()
  self.expect_comma()
  let section_name = self.read_quoted_string()
  self.skip_whitespace()
  self.expect_char(')')
  { prefix, section_name }
}

///|
fn Parser::read_optional_song_start(
  self : Parser,
) -> @pattern.Rational? raise ParseError {
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
fn Parser::expect_comma(self : Parser) -> Unit raise ParseError {
  self.skip_whitespace()
  self.expect_char(',')
  self.skip_whitespace()
}

///|
fn Parser::read_song_rational(
  self : Parser,
  label : String,
) -> @pattern.Rational raise ParseError {
  self.skip_whitespace()
  let value_start = self.pos
  let num = self.read_song_int(value_start, label)
  let mut den = 1
  if !self.at_end() && self.input[self.pos] == '/' {
    self.pos += 1
    den = self.read_song_int(value_start, label)
  }
  guard den != 0 else {
    raise ParseError(
      "position \{value_start}: \{label} denominator cannot be zero",
    )
  }
  @pattern.Rational::new(Int64::from_int(num), Int64::from_int(den))
}

///|
fn Parser::read_song_int(
  self : Parser,
  err_pos : Int,
  label : String,
) -> Int raise ParseError {
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
    raise ParseError("position \{err_pos}: \{label} requires an integer")
  }
  let s = self.input[start:self.pos].to_owned()
  let mut value = 0
  let mut index = 0
  let negative = s.length() > 0 && s[0] == '-'
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
  pos : Int,
) -> @identity.OccurrenceId raise ParseError {
  let result = try? @identity.OccurrenceId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) =>
      raise ParseError("position \{pos}: invalid occurrence id '\{value}'")
  }
}

///|
fn resolve_song_section(
  sections : Map[String, @song.Section[@pattern.ControlMap]],
  name : String,
) -> @song.Section[@pattern.ControlMap] raise ParseError {
  match sections.get(name) {
    Some(section) => section
    None => raise ParseError("unknown song section '\{name}'")
  }
}

///|
fn SongPartSpec::to_part(
  self : SongPartSpec,
  sections : Map[String, @song.Section[@pattern.ControlMap]],
) -> @song.SongPart[@pattern.ControlMap] raise ParseError {
  let section = resolve_song_section(sections, self.section_name)
  match (self.id, self.start) {
    (Some(id), Some(start)) =>
      @song.SongPart::with_id_at(id~, start~, name=self.name, section~)
    (Some(id), None) => @song.SongPart::with_id(id~, name=self.name, section~)
    (None, Some(start)) => @song.SongPart::at(start~, name=self.name, section~)
    (None, None) => @song.SongPart(name=self.name, section~)
  }
}

///|
fn build_song(
  parts : Array[@song.SongPart[@pattern.ControlMap]],
) -> @song.Song[@pattern.ControlMap] raise ParseError {
  let result = try? @song.Song(parts~)
  match result {
    Ok(song) => song
    Err(_) => raise ParseError("song construction failed")
  }
}
