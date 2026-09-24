///|
priv enum ReferenceProblem {
  UndefinedName
  DuplicateName
  OpaqueScope
}

///|
priv struct RecognizedAtom {
  kind : String
  span : MiniSpan
}

///|
fn RecognizedAtom::RecognizedAtom(
  kind : String,
  span : MiniSpan,
) -> RecognizedAtom {
  { kind, span, }
}

///|
priv struct RecognizedDefinition {
  name : String
  span : MiniSpan
  visible_after : Int
}

///|
fn RecognizedDefinition::RecognizedDefinition(
  name : String,
  span : MiniSpan,
  visible_after : Int,
) -> RecognizedDefinition {
  { name, span, visible_after, }
}

///|
priv struct RecognizedReference {
  name : String
  span : MiniSpan
  opaque_scope : Bool
}

///|
fn RecognizedReference::RecognizedReference(
  name : String,
  span : MiniSpan,
  opaque_scope : Bool,
) -> RecognizedReference {
  { name, span, opaque_scope, }
}

///|
priv enum MiniSourceMode {
  Pattern
  Song
}

///|
priv struct SourceRecognition {
  atoms : Array[RecognizedAtom]
  definitions : Array[RecognizedDefinition]
  references : Array[RecognizedReference]
  mode : MiniSourceMode?
}

///|
fn SourceRecognition::SourceRecognition(
  atoms : Array[RecognizedAtom],
  definitions : Array[RecognizedDefinition],
  references : Array[RecognizedReference],
  mode : MiniSourceMode?,
) -> SourceRecognition {
  { atoms, definitions, references, mode, }
}

///|
fn[A] unique_definition(
  candidates : Iter[A],
  opaque_scope : Bool,
) -> Result[A, ReferenceProblem] {
  guard !opaque_scope else { return Err(OpaqueScope) }
  let mut found : A? = None
  for candidate in candidates {
    guard found is None else { return Err(DuplicateName) }
    found = Some(candidate)
  }
  match found {
    Some(value) => Ok(value)
    None => Err(UndefinedName)
  }
}

///|
/// The ordinary notation parser emits complete atom facts before a later
/// group/postfix error. It does not repair or accept an invalid expression.
fn Parser::record_literal_fact(
  self : Parser,
  kind : MiniLiteral,
  content : String,
  content_start : Int,
) -> Unit {
  guard !(kind is Silence) else { return }
  let parser = NotationParser::new(
    content,
    sound=kind is Sound,
    chord=kind is Chord,
    source_offset=content_start,
    assess=true,
    recognized_atoms=Some(self.recognized_atoms),
  )
  try parser.parse_notation() catch {
    ParseError(_) => ()
  } noraise {
    _ => ()
  }
}

///|
fn Parser::record_reference_fact(
  self : Parser,
  name : String,
  start : Int,
  end : Int,
) -> Unit {
  self.recognized_references.push(
    RecognizedReference(name, { start, end, }, false),
  )
}

///|
/// Expressions contain no semicolons or declaration keywords. Scan beyond parse
/// failures so a missing terminator cannot hide another declaration. Quotes,
/// comments and identifiers follow the parser's lexical rules.
fn mini_recognition_boundary(parser : Parser) -> (Int, Bool) {
  let start = parser.pos
  let input = parser.input
  let mut hides_declaration = false
  let mut member_name = false
  let mut can_end_primary = false
  while !parser.at_end() {
    if input[parser.pos] == '"' {
      member_name = false
      can_end_primary = false
      parser.pos += 1
      while !parser.at_end() && input[parser.pos] != '"' {
        parser.pos += 1
      }
      if !parser.at_end() {
        parser.pos += 1
      }
    } else if mini_comment_end(input, parser.pos) is Some(end_) {
      parser.pos = end_
    } else if parser.pos + 1 < input.length() &&
      input[parser.pos] == '/' &&
      input[parser.pos + 1] == '*' {
      parser.pos = input.length()
    } else if input[parser.pos] == ';' {
      break
    } else if mini_is_space(input[parser.pos]) {
      parser.pos += 1
    } else {
      let token_start = parser.pos
      if parser.read_ident() == "let" && !member_name {
        hides_declaration = true
      }
      // Whitespace/comments do not end a member-name position.
      member_name = can_end_primary &&
        parser.pos == token_start &&
        input[token_start] == '.'
      can_end_primary = parser.pos > token_start || input[token_start] == ')'
      if parser.pos == token_start {
        parser.pos += 1
      }
    }
  }
  let boundary = parser.pos
  parser.pos = start
  (boundary, hides_declaration)
}

///|
fn recognize_expression(
  parser : Parser,
  scope_opaque : Bool,
  references : Array[RecognizedReference],
) -> Unit {
  let first_reference = parser.recognized_references.length()
  try parser.parse_syntax_expr() catch {
    ParseError(_) => ()
  } noraise {
    _ => ()
  }
  for reference in parser.recognized_references[first_reference:] {
    references.push(
      RecognizedReference(reference.name, reference.span, scope_opaque),
    )
  }
}

///|
fn recognize_mini_source(input : String) -> SourceRecognition {
  let parser = Parser::new(input, syntax_depth_limit=Some(32))
  parser.recognition = true
  let definitions : Array[RecognizedDefinition] = []
  let references : Array[RecognizedReference] = []
  let mut scope_opaque = false
  let mut mode : MiniSourceMode? = None
  while true {
    parser.limit = input.length()
    parser.skip_whitespace()
    guard !parser.at_end() else { break }
    let start = parser.pos
    let header = try parser.read_binding_name() catch {
      ParseError(_) => Err(())
    } noraise {
      name => Ok(name)
    }
    let body_start = parser.pos
    match header {
      Ok(Some(_)) => ()
      _ => parser.pos = start
    }
    let (boundary, hides_declaration) = mini_recognition_boundary(parser)
    parser.pos = body_start
    match header {
      Ok(Some(name)) => {
        // A complete declaration name remains itself while its body is invalid.
        // Without a certain terminator it cannot be a preceding visible target.
        definitions.push(
          RecognizedDefinition(
            name,
            parser.last_binding_span,
            if boundary < input.length() {
              boundary + 1
            } else {
              input.length() + 1
            },
          ),
        )
        parser.limit = boundary
        recognize_expression(parser, scope_opaque, references)
        scope_opaque = scope_opaque || hides_declaration
        guard boundary < input.length() else { break }
        parser.pos = boundary + 1
      }
      Err(_) => {
        scope_opaque = true
        guard boundary < input.length() else { break }
        parser.pos = boundary + 1
      }
      Ok(None) => {
        parser.pos = start
        // Tempo is a declaration, not an expression reference.
        if parser.match_keyword("bpm(") {
          parser.pos = start
          try parse_play_bpm_declaration(parser) catch {
            ParseError(_) => ()
          } noraise {
            _ => ()
          }
          scope_opaque = scope_opaque || hides_declaration
          guard boundary < input.length() else { break }
          parser.pos = boundary + 1
          continue
        }
        parser.pos = start
        if parser.match_keyword("song(") {
          mode = Some(Song)
          break
        }
        parser.pos = start
        parser.recognized_pattern = false
        match mini_collect_dollar_stack_lines(input, start~, partial=true) {
          Ok(Some(lines)) => {
            mode = Some(Pattern)
            for line in lines {
              parser.pos = line.start
              parser.limit = line.end
              recognize_expression(parser, scope_opaque, references)
            }
            break
          }
          _ => {
            parser.limit = boundary
            recognize_expression(parser, scope_opaque, references)
            if parser.recognized_pattern {
              mode = Some(Pattern)
            }
            guard boundary < input.length() else { break }
            // An unknown preceding statement may hide a declaration. Never
            // clear this uncertainty just because a later header is certain.
            scope_opaque = true
            parser.pos = boundary + 1
          }
        }
      }
    }
  }
  SourceRecognition(parser.recognized_atoms, definitions, references, mode)
}
