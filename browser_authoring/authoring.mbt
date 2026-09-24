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
