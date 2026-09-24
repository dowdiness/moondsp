///|
/// Transport work is bounded separately from the 8192-code-unit source domain.
const PLAYBACK_WIRE_LIMIT : Int = 2097152

///|
priv suberror PlaybackWireError {
  InvalidWire(String)
}

///|
fn wire_integer(
  value : Json,
  minimum : Int64,
  maximum : Int64,
) -> Int64 raise PlaybackWireError {
  guard value is Number(number, ..) &&
    number >= minimum.to_double() &&
    number <= maximum.to_double() else {
    raise InvalidWire("invalid wire integer")
  }
  let integer = number.to_int64()
  guard integer.to_double() == number else {
    raise InvalidWire("wire integer must be exact")
  }
  integer
}

///|
fn draft_version_json(version : DraftVersion) -> Json {
  [
    version.epoch.serial().to_double().to_json(),
    version.revision.to_double().to_json(),
  ]
}

///|
/// Canonical transport value for correlating a draft submission with its receipt.
pub impl ToJson for DraftVersion with fn to_json(self) {
  draft_version_json(self)
}

///|
pub extend DraftVersion with ToJson::{to_json}

///|
fn decode_draft_version(value : Json) -> DraftVersion raise PlaybackWireError {
  guard value is Array([epoch, revision]) else {
    raise InvalidWire("invalid draft version")
  }
  let epoch = @identity.SourceEpoch::SourceEpoch(
    wire_integer(epoch, 1L, DRAFT_IDENTITY_MAX),
  ) catch {
    _ => raise InvalidWire("invalid source epoch")
  }
  DraftVersion(epoch, wire_integer(revision, 0L, DRAFT_IDENTITY_MAX))
}

///|
/// Encode frozen text and witnesses together; never serialize closures or history.
pub fn PlaybackInput::encode_wire(self : PlaybackInput) -> String {
  let fields : Map[String, Json] = { "schema": 1, "text": self.input.to_json() }
  match self.payload {
    Text => fields["kind"] = "text"
    Song(version) => {
      fields["kind"] = "song"
      fields["version"] = draft_version_json(version)
    }
    Pattern(version, sources) => {
      fields["kind"] = "pattern"
      fields["version"] = draft_version_json(version)
      let atoms : Array[Json] = sources.atoms.map(atom => {
        [
          atom.id.serial().to_double().to_json(),
          atom.kind.to_json(),
          atom.span.start.to_json(),
          atom.span.end.to_json(),
        ]
      })
      let definitions : Array[Json] = sources.definitions.map(definition => {
        [
          definition.id.serial().to_double().to_json(),
          definition.name.to_json(),
          definition.span.start.to_json(),
          definition.span.end.to_json(),
          definition.visible_after.to_json(),
        ]
      })
      let references : Array[Json] = sources.references.map(reference => {
        let (binding, target) : (Json, Json) = match reference.binding {
          Bound(binding, target) =>
            (
              binding.serial().to_double().to_json(),
              target.serial().to_double().to_json(),
            )
          Unresolved(_) => (Json::null(), Json::null())
        }
        [
          reference.id.serial().to_double().to_json(),
          reference.name.to_json(),
          reference.span.start.to_json(),
          reference.span.end.to_json(),
          binding,
          target,
        ]
      })
      fields["sourceMap"] = {
        "epoch": sources.epoch.serial().to_double().to_json(),
        "atoms": atoms.to_json(),
        "definitions": definitions.to_json(),
        "references": references.to_json(),
      }
    }
  }
  Json::object(fields).stringify()
}

///|
fn wire_unique_serial(
  value : Json,
  seen : Map[Int64, Unit],
) -> Int64 raise PlaybackWireError {
  let serial = wire_integer(value, 1L, DRAFT_IDENTITY_MAX)
  guard !seen.contains(serial) else {
    raise InvalidWire("duplicate source identity")
  }
  seen[serial] = ()
  serial
}

///|
fn wire_span(
  start : Json,
  end_ : Json,
  input : String,
) -> MiniSpan raise PlaybackWireError {
  let start = wire_integer(start, 0L, input.length().to_int64()).to_int()
  let end_ = wire_integer(end_, 0L, input.length().to_int64()).to_int()
  guard start < end_ &&
    draft_utf16_boundary(input, start) &&
    draft_utf16_boundary(input, end_) else {
    raise InvalidWire("invalid source range")
  }
  { start, end: end_, }
}

///|
fn decode_source_map(
  value : Json,
  input : String,
) -> SourceMap raise PlaybackWireError {
  guard value is Object(fields) &&
    fields.length() == 4 &&
    fields.get("epoch") is Some(epoch) &&
    fields.get("atoms") is Some(Array(atom_rows)) &&
    fields.get("definitions") is Some(Array(definition_rows)) &&
    fields.get("references") is Some(Array(reference_rows)) else {
    raise InvalidWire("invalid source map")
  }
  let epoch = @identity.SourceEpoch::SourceEpoch(
    wire_integer(epoch, 1L, DRAFT_IDENTITY_MAX),
  ) catch {
    _ => raise InvalidWire("invalid source epoch")
  }
  guard atom_rows.length() <= input.length() &&
    definition_rows.length() <= input.length() &&
    reference_rows.length() <= input.length() else {
    raise InvalidWire("source map exceeds source bounds")
  }
  let facts = recognize_mini_source(input)
  guard facts.mode is Some(Pattern) &&
    atom_rows.length() == facts.atoms.length() &&
    definition_rows.length() == facts.definitions.length() &&
    reference_rows.length() == facts.references.length() else {
    raise InvalidWire("source map does not cover the submitted program")
  }
  let seen : Map[Int64, Unit] = Map([])
  let atoms : Array[LiveAtom] = []
  for index, row in atom_rows {
    guard row is Array([serial, String(kind), start, end_]) else {
      raise InvalidWire("invalid atom witness")
    }
    let serial = wire_unique_serial(serial, seen)
    let span = wire_span(start, end_, input)
    let fact = facts.atoms[index]
    guard kind == fact.kind &&
      span.start == fact.span.start &&
      span.end == fact.span.end else {
      raise InvalidWire("atom witness does not match parsed source")
    }
    let id = @identity.SourceAtomId::SourceAtomId(epoch, serial) catch {
      _ => raise InvalidWire("invalid atom identity")
    }
    atoms.push(LiveAtom(id, kind, span))
  }
  let definitions : Array[LiveDefinition] = []
  for index, row in definition_rows {
    guard row is Array([serial, String(name), start, end_, visible_after]) else {
      raise InvalidWire("invalid definition witness")
    }
    let serial = wire_unique_serial(serial, seen)
    let span = wire_span(start, end_, input)
    let visible_after = wire_integer(
      visible_after,
      0L,
      input.length().to_int64(),
    ).to_int()
    let fact = facts.definitions[index]
    guard name == fact.name &&
      span.start == fact.span.start &&
      span.end == fact.span.end &&
      visible_after == fact.visible_after else {
      raise InvalidWire("definition witness does not match parsed source")
    }
    let id = @identity.DefinitionId::DefinitionId(epoch, serial) catch {
      _ => raise InvalidWire("invalid definition identity")
    }
    definitions.push(LiveDefinition(id, fact))
  }
  let references : Array[LiveReference] = []
  for index, row in reference_rows {
    guard row is Array([serial, String(name), start, end_, binding, target]) else {
      raise InvalidWire("invalid reference witness")
    }
    let serial = wire_unique_serial(serial, seen)
    let binding = wire_unique_serial(binding, seen)
    let target = wire_integer(target, 1L, DRAFT_IDENTITY_MAX)
    let span = wire_span(start, end_, input)
    let fact = facts.references[index]
    guard name == fact.name &&
      span.start == fact.span.start &&
      span.end == fact.span.end else {
      raise InvalidWire("reference witness does not match parsed source")
    }
    let definition = match
      unique_definition(
        definitions
        .iter()
        .filter(definition => {
          definition.name == name && definition.visible_after <= span.start
        }),
        fact.opaque_scope,
      ) {
      Ok(definition) => definition
      Err(_) => raise InvalidWire("reference target is not uniquely resolved")
    }
    guard definition.id.serial() == target else {
      raise InvalidWire("reference binding has the wrong target")
    }
    let id = @identity.ReferenceId::ReferenceId(epoch, serial) catch {
      _ => raise InvalidWire("invalid reference identity")
    }
    let binding = @identity.ReferenceBindingId::ReferenceBindingId(
      epoch, binding,
    ) catch {
      _ => raise InvalidWire("invalid reference binding identity")
    }
    references.push(LiveReference(id, fact, Bound(binding, definition.id)))
  }
  // Received maps are immutable capabilities, never authoring-counter owners.
  SourceMap(epoch, 0L, atoms, definitions, references)
}

///|
fn decode_playback_wire(wire : String) -> PlaybackInput raise PlaybackWireError {
  guard wire.length() <= PLAYBACK_WIRE_LIMIT else {
    raise InvalidWire("playback input exceeds wire limit")
  }
  let json = @json.parse(wire) catch {
    _ => raise InvalidWire("invalid playback input JSON")
  }
  guard json is Object(fields) &&
    fields.get("schema") is Some(Number(1, ..)) &&
    fields.get("kind") is Some(String(kind)) &&
    fields.get("text") is Some(String(input)) else {
    raise InvalidWire("invalid playback input envelope")
  }
  guard input.length() <= DRAFT_SOURCE_LIMIT else {
    raise InvalidWire("playback source exceeds 8192 characters")
  }
  let payload = match kind {
    "text" => {
      guard fields.length() == 3 else {
        raise InvalidWire("unexpected text input metadata")
      }
      PlaybackPayload::Text
    }
    "song" | "pattern" => {
      guard fields.get("version") is Some(version) else {
        raise InvalidWire("missing draft version")
      }
      let version = decode_draft_version(version)
      if kind == "song" {
        guard fields.length() == 4 else {
          raise InvalidWire("unexpected song input metadata")
        }
        PlaybackPayload::Song(version)
      } else {
        guard fields.length() == 5 && fields.get("sourceMap") is Some(sources) else {
          raise InvalidWire("missing pattern source map")
        }
        PlaybackPayload::Pattern(version, decode_source_map(sources, input))
      }
    }
    _ => raise InvalidWire("unknown playback input capability")
  }
  PlaybackInput(input, payload)
}

///|
/// Restore a transported capability without minting or inferring source identities.
/// Compilation still performs strict grammar and runtime admission checks.
pub fn PlaybackInput::decode_wire(
  wire : String,
) -> Result[PlaybackInput, String] {
  try decode_playback_wire(wire) catch {
    InvalidWire(message) => Err(message)
  } noraise {
    input => Ok(input)
  }
}
