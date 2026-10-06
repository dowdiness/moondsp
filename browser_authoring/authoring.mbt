///|
priv suberror EditWireError {
  InvalidEdit(String)
}

///|
fn main {
  ()
}

///|
/// This module is a main-thread adapter; the Mini owner retains all identities.
pub fn create_draft(
  text : String,
  on_created : (@mini.Draft) -> Unit,
  on_error : (String) -> Unit,
) -> Unit {
  let draft = @mini.Draft::new(text) catch {
    error => {
      on_error("\{Repr(error)}")
      return
    }
  }
  on_created(draft)
}

///|
fn state_json(state : @mini.DraftState) -> Json {
  let diagnostic : Json = match state.diagnostic() {
    Some(error) => error.message().to_json()
    None => Json::null()
  }
  {
    "text": state.text().to_json(),
    "version": state.version().to_json(),
    "diagnostic": diagnostic,
  }
}

///|
pub fn draft_state(draft : @mini.Draft) -> String {
  state_json(draft.state()).stringify()
}

///|
fn edit_offset(value : Json) -> Int raise EditWireError {
  guard value is Number(number, ..) && number >= 0.0 && number <= 2147483647.0 else {
    raise InvalidEdit("invalid UTF-16 edit offset")
  }
  let offset = number.to_int()
  guard offset.to_double() == number else {
    raise InvalidEdit("edit offsets must be integers")
  }
  offset
}

///|
fn decode_transaction(
  draft : @mini.Draft,
  wire : String,
) -> @mini.EditTransaction raise EditWireError {
  let json = @json.parse(wire) catch {
    _ => raise InvalidEdit("invalid edit transaction JSON")
  }
  guard json is Object(fields) &&
    fields.length() == 2 &&
    fields.get("base") is Some(base) &&
    fields.get("edits") is Some(Array(edits)) else {
    raise InvalidEdit("invalid edit transaction")
  }
  let version = draft.state().version()
  guard base == version.to_json() else {
    raise InvalidEdit("stale draft version")
  }
  let decoded = edits.map(edit => {
    guard edit is Object(fields) &&
      fields.length() == 3 &&
      fields.get("from") is Some(from) &&
      fields.get("to") is Some(to) &&
      fields.get("inserted") is Some(String(inserted)) else {
      raise InvalidEdit("invalid edit")
    }
    @mini.TextEdit::TextEdit(
      from=edit_offset(from),
      to=edit_offset(to),
      inserted~,
    )
  })
  @mini.EditTransaction::EditTransaction(base=version, edits=decoded)
}

///|
/// Reject before touching the owner on malformed or stale transactions.
pub fn edit_draft(draft : @mini.Draft, transaction : String) -> String {
  let result : Json = try {
    let transaction = decode_transaction(draft, transaction)
    match draft.edit(transaction) {
      Ok(state) => { "ok": true, "state": state_json(state) }
      Err(error) => { "ok": false, "message": "\{Repr(error)}".to_json() }
    }
  } catch {
    InvalidEdit(message) => { "ok": false, "message": message.to_json() }
  }
  result.stringify()
}

///|
pub fn prepare_playback(draft : @mini.Draft) -> String {
  let result : Json = match draft.prepare_playback() {
    Ok(input) => { "ok": true, "input": input.encode_wire().to_json() }
    Err(error) => { "ok": false, "message": error.message().to_json() }
  }
  result.stringify()
}

///|
pub fn dispose_draft(draft : @mini.Draft) -> Unit {
  draft.dispose()
}

///|
fn projection_atom_index(nodes : Array[Json], start : Int, end_ : Int) -> Int? {
  for index, node in nodes {
    if node is Object(fields) &&
      fields.get("kind") == Some("atom".to_json()) &&
      fields.get("from") == Some(start.to_json()) &&
      fields.get("baseTo") == Some(end_.to_json()) {
      return Some(index)
    }
  }
  None
}

///|
fn notation_projection_is_rest(nodes : Array[Json], index : Int) -> Bool {
  match nodes.get(index) {
    Some(Object(fields)) =>
      fields.get("kind") == Some("atom".to_json()) &&
      fields.get("value") == Some("~".to_json())
    _ => false
  }
}

///|
fn notation_projection_rest_source(
  content : String,
  nodes : Array[Json],
) -> String raise EditWireError {
  let output = StringBuilder()
  let mut cursor = 0
  for index, node in nodes {
    if notation_projection_is_rest(nodes, index) {
      guard node is Object(fields) &&
        fields.get("from") is Some(Number(from, ..)) &&
        fields.get("baseTo") is Some(Number(to, ..)) else {
        raise InvalidEdit("notation rest has an invalid source span")
      }
      let start = from.to_int()
      let end_ = to.to_int()
      guard start >= cursor && end_ == start + 1 && end_ <= content.length() else {
        raise InvalidEdit("notation rest does not have a one-unit source core")
      }
      output.write_view(content[cursor:start])
      output.write_string("0")
      cursor = end_
    }
  }
  output.write_view(content[cursor:])
  output.to_string()
}

///|
fn notation_projection_events(
  draft : @mini.Draft,
  compiled : @mini.PreparedPlayback,
  span : Int,
  content_start : Int,
  content_length : Int,
  nodes : Array[Json],
  kind : String,
  rests_only : Bool,
) -> Array[Json] raise EditWireError {
  match compiled {
    @mini.PreparedPlayback::Pattern(snapshot, _) => {
      let arc = @pattern.TimeSpan::new(
        @pattern.Rational::from_int(0),
        @pattern.Rational::from_int(span),
      )
      let queried = snapshot.query(arc)
      guard queried.length() <= 256 else {
        raise InvalidEdit("notation projection exceeds 256 emitted events")
      }
      let projected : Array[Json] = []
      let span_end = span.to_double()
      for source_event in queried {
        let event = source_event.event()
        guard event.whole is Some(whole) else {
          raise InvalidEdit("compiled event has no source time span")
        }
        let start = whole.begin.to_double()
        if start >= 0.0 && start < span_end {
          let atom_span = match draft.locate_origin(source_event.origin()) {
            @mini.OriginLocation::Located(range, _) => range
            @mini.OriginLocation::Unavailable(_) =>
              raise InvalidEdit("compiled event source origin is unavailable")
          }
          guard atom_span.start() >= content_start &&
            atom_span.end() <= content_start + content_length else {
            raise InvalidEdit(
              "compiled event origin is outside notation content",
            )
          }
          let node = match
            projection_atom_index(
              nodes,
              atom_span.start() - content_start,
              atom_span.end() - content_start,
            ) {
            Some(index) => index
            None =>
              raise InvalidEdit("compiled event does not map to a source atom")
          }
          if !rests_only || notation_projection_is_rest(nodes, node) {
            let pitch : Json = if rests_only || kind == "drum" {
              Json::null()
            } else {
              match event.value.get("note") {
                Some(value) => value.to_json()
                None => raise InvalidEdit("compiled note event has no pitch")
              }
            }
            projected.push({
              "node": node.to_json(),
              "start": start.to_json(),
              "end": whole.end_.to_double().to_json(),
              "pitch": pitch,
            })
          }
        }
      }
      projected
    }
    @mini.PreparedPlayback::Runtime(_) =>
      raise InvalidEdit("notation did not compile to an exact pattern")
  }
}

///|
fn notation_projection_compile_events(
  draft : @mini.Draft,
  span : Int,
  content_start : Int,
  content_length : Int,
  nodes : Array[Json],
  kind : String,
  rests_only : Bool,
) -> Array[Json] raise EditWireError {
  let input = match draft.prepare_playback() {
    Ok(input) => input
    Err(error) => raise InvalidEdit(error.message())
  }
  let compiled = match input.compile() {
    Ok(value) => value
    Err(message) => raise InvalidEdit(message)
  }
  notation_projection_events(
    draft, compiled, span, content_start, content_length, nodes, kind, rests_only,
  )
}

///|
fn notation_projection_temp_draft(
  source : String,
) -> @mini.Draft raise EditWireError {
  @mini.Draft::new(source) catch {
    error => raise InvalidEdit("\{Repr(error)}")
  }
}

///|
fn notation_projection_json(
  kind : String,
  content : String,
) -> Json raise EditWireError {
  let source_prefix = if kind == "note" {
    "note(\""
  } else if kind == "drum" {
    "s(\""
  } else {
    "chord(\""
  }
  let content_start = source_prefix.length()
  let source = source_prefix + content + "\")"
  let source_projection = match @mini.project_notation_nodes(kind, content) {
    Ok(value) => value
    Err(message) => raise InvalidEdit(message)
  }
  guard source_projection is Object(projection_fields) &&
    projection_fields.get("roots") is Some(roots) &&
    projection_fields.get("nodes") is Some(Array(nodes)) &&
    projection_fields.get("span") is Some(Number(span_value, ..)) else {
    raise InvalidEdit("notation parser returned an invalid source projection")
  }
  guard span_value >= 1.0 && span_value <= 16.0 else {
    raise InvalidEdit("notation entry period exceeds 16 cycles")
  }
  let span = span_value.to_int()
  let draft = @mini.Draft::new(source) catch {
    error => raise InvalidEdit("\{Repr(error)}")
  }
  let result : Json = try {
    let events = notation_projection_compile_events(
      draft,
      span,
      content_start,
      content.length(),
      nodes,
      kind,
      false,
    )
    let mut has_rests = false
    for index, _ in nodes {
      if notation_projection_is_rest(nodes, index) {
        has_rests = true
      }
      if has_rests {
        break
      }
    }
    let rests = if kind == "note" && has_rests {
      let rest_content = notation_projection_rest_source(content, nodes)
      // Sounding a rest changes the admission model's event/work bound.
      match @mini.project_notation_nodes("note", rest_content) {
        Err(message) => raise InvalidEdit(message)
        Ok(_) => ()
      }
      let rest_source = source_prefix + rest_content + "\")"
      let rest_draft = notation_projection_temp_draft(rest_source)
      let rest_result = notation_projection_compile_events(
        rest_draft,
        span,
        content_start,
        content.length(),
        nodes,
        kind,
        true,
      ) catch {
        InvalidEdit(message) => {
          rest_draft.dispose()
          raise InvalidEdit(message)
        }
      }
      rest_draft.dispose()
      guard events.length() + rest_result.length() <= 256 else {
        raise InvalidEdit("notation projection exceeds 256 emitted events")
      }
      rest_result
    } else {
      []
    }
    {
      "error": Json::null(),
      "roots": roots,
      "nodes": Json::array(nodes),
      "events": Json::array(events),
      "rests": Json::array(rests),
      "span": span_value.to_json(),
    }
  } catch {
    InvalidEdit(message) => {
      draft.dispose()
      raise InvalidEdit(message)
    }
  }
  draft.dispose()
  result
}

///|
/// Return a parser-backed source tree and events from exact compiled origins.
pub fn project_notation(kind : String, content : String) -> String {
  let result : Json = notation_projection_json(kind, content) catch {
    InvalidEdit(message) =>
      {
        "error": message.to_json(),
        "roots": Json::array([]),
        "nodes": Json::array([]),
        "events": Json::array([]),
        "rests": Json::array([]),
        "span": Json::number(1.0),
      }
  }
  result.stringify()
}

///|
fn onset_wire_integer(value : Json) -> Int64? {
  guard value is Number(number, ..) &&
    number >= 0.0 &&
    number <= 9007199254740991.0 else {
    return None
  }
  let integer = number.to_int64()
  if integer.to_double() == number {
    Some(integer)
  } else {
    None
  }
}

///|
fn source_range_json(range : @mini.SourceRange) -> Json {
  { "from": range.start().to_json(), "to": range.end().to_json() }
}

///|
/// Resolve dispatched onset wire rows against the draft's exact identities.
/// Invalid or retired rows remain null and preserve their input position.
pub fn locate_onsets(draft : @mini.Draft, wire : String) -> String {
  let decoded = @json.parse(wire) catch { _ => return "[]" }
  guard decoded is Array(rows) else { return "[]" }
  let resolved : Array[Json] = []
  for row in rows {
    guard row is Array(fields) &&
      fields.length() >= 7 &&
      onset_wire_integer(fields[1]) is Some(epoch) &&
      onset_wire_integer(fields[2]) is Some(serial) &&
      onset_wire_integer(fields[3]) is Some(frame_serial) &&
      fields[4] is Number(local_start, ..) &&
      onset_wire_integer(fields[6]) is Some(binding_count) &&
      binding_count <= 32L &&
      fields.length() == 7 + binding_count.to_int() * 3 &&
      !local_start.is_nan() &&
      !local_start.is_inf() &&
      local_start >= -1.0 else {
      resolved.push(Json::null())
      continue
    }
    let path : Array[Int64] = []
    let mut valid = match fields[5] {
      Null => true
      Number(pitch, ..) => !pitch.is_nan() && !pitch.is_inf()
      _ => false
    }
    for index in 0..<(binding_count.to_int() * 3) {
      match onset_wire_integer(fields[7 + index]) {
        Some(value) => path.push(value)
        None => valid = false
      }
    }
    if !valid {
      resolved.push(Json::null())
      continue
    }
    match draft.locate_origin_fields(epoch, serial, path) {
      @mini.OriginLocation::Unavailable(_) => resolved.push(Json::null())
      @mini.OriginLocation::Located(atom, references) => {
        let notation : Json = if frame_serial == 0L || local_start < 0.0 {
          Json::null()
        } else {
          match draft.locate_frame_fields(epoch, frame_serial) {
            Some(range) =>
              {
                "from": range.start().to_json(),
                "to": range.end().to_json(),
                "start": local_start.to_json(),
                "pitch": fields[5],
              }
            None => Json::null()
          }
        }
        resolved.push({
          "from": atom.start().to_json(),
          "to": atom.end().to_json(),
          "references": Json::array(references.map(source_range_json)),
          "notation": notation,
        })
      }
    }
  }
  Json::array(resolved).stringify()
}
