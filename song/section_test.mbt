///|
using @song {
  type Section,
  type SectionBody,
  type SectionBuildError,
  type SectionDoc,
  type SectionDocBody,
  type SectionDocEditError,
  type SectionPatch,
  type SectionPatchError,
  type TimeScope,
  type TimeScopeBuildError,
}

///|
fn section_test_section_id(value : String) -> @identity.SectionId {
  let result = try? @identity.SectionId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("section id creation failed")
  }
}

///|
fn section_test_layer_id(value : String) -> @identity.SectionLayerId {
  let result = try? @identity.SectionLayerId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("layer id creation failed")
  }
}

///|
fn section_test_occurrence_id(value : String) -> @identity.OccurrenceId {
  let result = try? @identity.OccurrenceId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("occurrence id creation failed")
  }
}

///|
fn section_test_section_doc(
  section_id : @identity.SectionId,
  layer_id : @identity.SectionLayerId,
  name : String,
  length : @pattern.Rational,
  midi : Double,
) -> SectionDoc[@pattern.ControlMap] {
  let result = try? SectionDoc::single(
    id=section_id,
    name~,
    length_cycles=length,
    scope=TimeScope::identity(),
    layer_id~,
    body=@pattern.note(midi),
  )
  match result {
    Ok(doc) => doc
    Err(_) => abort("section doc creation failed")
  }
}

///|
test "Section::from_pattern wraps a pattern with identity scope" {
  let pat = @pattern.note(60.0)
  let section = Section::from_pattern(name="main", body=pat)
  @debug.assert_eq(section.name(), "main")
  assert_true(section.length_cycles() == @pattern.Rational::from_int(1))
  assert_true(section.scope().is_identity())
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  @debug.assert_eq(events.length(), 1)
  assert_true(events[0].value.get("note") == Some(60.0))
}

///|
test "Section constructor rejects non-positive lengths" {
  let pat = @pattern.note(60.0)
  let result = try? Section(
    name="bad",
    length_cycles=@pattern.Rational::from_int(0),
    scope=TimeScope::identity(),
    body=SectionBody::single(pat),
  )
  match result {
    Err(SectionBuildError::NonPositiveLength) => ()
    _ => assert_true(false)
  }
}

///|
test "TimeScope constructor creates identity scope" {
  assert_true(TimeScope().is_identity())
}

///|
test "TimeScope fast and slow constructors expose exact rates" {
  let fast_result = try? TimeScope::fast(factor=@pattern.Rational::from_int(2))
  let fast = match fast_result {
    Ok(scope) => scope
    Err(_) => abort("fast scope creation failed")
  }
  assert_true(!fast.is_identity())
  assert_true(fast.rate() == @pattern.Rational::from_int(2))
  let slow_result = try? TimeScope::slow(factor=@pattern.Rational::from_int(2))
  let slow = match slow_result {
    Ok(scope) => scope
    Err(_) => abort("slow scope creation failed")
  }
  assert_true(!slow.is_identity())
  assert_true(slow.rate() == @pattern.Rational::new(1L, 2L))
}

///|
test "TimeScope rejects non-positive rates" {
  let result = try? TimeScope::fast(factor=@pattern.Rational::from_int(0))
  match result {
    Err(TimeScopeBuildError::NonPositiveRate) => ()
    _ => assert_true(false)
  }
}

///|
test "Section::query applies non-identity TimeScope" {
  let scope_result = try? TimeScope::fast(factor=@pattern.Rational::from_int(2))
  let scope = match scope_result {
    Ok(scope) => scope
    Err(_) => abort("scope creation failed")
  }
  let result = try? Section(
    name="fast",
    length_cycles=@pattern.Rational::from_int(1),
    scope~,
    body=SectionBody::single(@pattern.note(60.0)),
  )
  let section = match result {
    Ok(section) => section
    Err(_) => abort("section creation failed")
  }
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let scoped_events = section.query(arc)
  let raw_events = section.body().query(arc)
  @debug.assert_eq(raw_events.length(), 1)
  @debug.assert_eq(scoped_events.length(), 2)
  assert_true(scoped_events[0].part.begin == @pattern.Rational::from_int(0))
  assert_true(scoped_events[1].part.begin == @pattern.Rational::new(1L, 2L))
  assert_true(
    scoped_events[1].whole.unwrap().begin == @pattern.Rational::new(1L, 2L),
  )
}

///|
test "SectionDoc display renames preserve section and layer IDs and revisions" {
  let section_id = section_test_section_id("section:verse")
  let lead_id = section_test_layer_id("layer:lead")
  let pad_id = section_test_layer_id("layer:pad")
  let doc_result = try? SectionDoc(
    id=section_id,
    name="Verse",
    length_cycles=@pattern.Rational::from_int(1),
    scope=TimeScope::identity(),
    body=SectionDocBody::layers([
      @song.SectionLayerDoc(id=lead_id, name="Lead", body=@pattern.note(60.0)),
      @song.SectionLayerDoc(id=pad_id, name="Pad", body=@pattern.note(67.0)),
    ]),
  )
  let doc = match doc_result {
    Ok(doc) => doc
    Err(_) => abort("section doc creation failed")
  }
  let original_lead = match doc.get_layer(lead_id) {
    Some(layer) => layer
    None => abort("expected lead layer")
  }
  let renamed_result = try? doc
    .rename(name="Verse Display")
    .rename_layer(lead_id, name="Lead Display")
  let renamed = match renamed_result {
    Ok(doc) => doc
    Err(_) => abort("rename failed")
  }
  @debug.assert_eq(renamed.id().value(), "section:verse")
  @debug.assert_eq(renamed.name(), "Verse Display")
  assert_true(renamed.revision() == doc.revision())
  let renamed_lead = match renamed.get_layer(lead_id) {
    Some(layer) => layer
    None => abort("expected renamed lead layer")
  }
  @debug.assert_eq(renamed_lead.id().value(), "layer:lead")
  @debug.assert_eq(renamed_lead.name(), "Lead Display")
  assert_true(renamed_lead.revision() == original_lead.revision())
  let section = renamed.to_section()
  @debug.assert_eq(section.name(), "Verse Display")
  assert_true(section.get_layer("Lead Display") is Some(_))
  assert_true(section.get_layer("Lead") is None)
}

///|
test "SectionDoc rejects duplicate renamed layer display names" {
  let lead_id = section_test_layer_id("layer:lead")
  let pad_id = section_test_layer_id("layer:pad")
  let doc_result = try? SectionDoc(
    id=section_test_section_id("section:dup"),
    name="Dup",
    length_cycles=@pattern.Rational::from_int(1),
    scope=TimeScope::identity(),
    body=SectionDocBody::layers([
      @song.SectionLayerDoc(id=lead_id, name="Lead", body=@pattern.note(60.0)),
      @song.SectionLayerDoc(id=pad_id, name="Pad", body=@pattern.note(67.0)),
    ]),
  )
  let doc = match doc_result {
    Ok(doc) => doc
    Err(_) => abort("section doc creation failed")
  }
  let result = try? doc.rename_layer(lead_id, name="Pad")
  match result {
    Err(SectionDocEditError::DuplicateLayerName("Pad")) => ()
    _ => assert_true(false)
  }
}

///|
test "SectionDoc rename reports missing layer before duplicate display name" {
  let lead_id = section_test_layer_id("layer:lead")
  let missing_id = section_test_layer_id("layer:missing")
  let doc_result = try? SectionDoc(
    id=section_test_section_id("section:missing"),
    name="Missing",
    length_cycles=@pattern.Rational::from_int(1),
    scope=TimeScope::identity(),
    body=SectionDocBody::layers([
      @song.SectionLayerDoc(id=lead_id, name="Lead", body=@pattern.note(60.0)),
    ]),
  )
  let doc = match doc_result {
    Ok(doc) => doc
    Err(_) => abort("section doc creation failed")
  }
  let result = try? doc.rename_layer(missing_id, name="Lead")
  match result {
    Err(SectionDocEditError::MissingLayerId("layer:missing")) => ()
    _ => assert_true(false)
  }
}

///|
test "SectionDoc layer body edits advance layer and section revisions without layout changes" {
  let section_id = section_test_section_id("section:body")
  let layer_id = section_test_layer_id("layer:main")
  let occurrence_id = section_test_occurrence_id("body:1")
  let doc = section_test_section_doc(
    section_id,
    layer_id,
    "Body",
    @pattern.Rational::from_int(2),
    60.0,
  )
  let edited_result = try? doc.replace_layer_body(
    layer_id,
    body=@pattern.note(64.0),
  )
  let edited = match edited_result {
    Ok(doc) => doc
    Err(_) => abort("replace layer body failed")
  }
  @debug.assert_eq(edited.id().value(), doc.id().value())
  assert_true(edited.length_cycles() == doc.length_cycles())
  assert_true(edited.revision().value() > doc.revision().value())
  let original_layer = match doc.get_layer(layer_id) {
    Some(layer) => layer
    None => abort("expected original layer")
  }
  let edited_layer = match edited.get_layer(layer_id) {
    Some(layer) => layer
    None => abort("expected edited layer")
  }
  @debug.assert_eq(edited_layer.id().value(), original_layer.id().value())
  assert_true(
    edited_layer.revision().value() > original_layer.revision().value(),
  )
  let before_song_result = try? @song.Song(parts=[
    @song.SongPart::with_id(
      id=occurrence_id,
      name="Body 1",
      section=doc.to_section(),
    ),
  ])
  let after_song_result = try? @song.Song(parts=[
    @song.SongPart::with_id(
      id=occurrence_id,
      name="Body 1",
      section=edited.to_section(),
    ),
  ])
  let before_song = match before_song_result {
    Ok(song) => song
    Err(_) => abort("before song creation failed")
  }
  let after_song = match after_song_result {
    Ok(song) => song
    Err(_) => abort("after song creation failed")
  }
  match
    (
      before_song.get_occurrence_by_id(occurrence_id),
      after_song.get_occurrence_by_id(occurrence_id),
    ) {
    (Some(before), Some(after)) => {
      @debug.assert_eq(before.id().value(), after.id().value())
      assert_true(before.start() == after.start())
      assert_true(before.end_() == after.end_())
    }
    _ => abort("expected matching occurrences")
  }
  let events = after_song.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  @debug.assert_eq(events.length(), 1)
  assert_true(events[0].value.get("note") == Some(64.0))
}

///|
test "SectionDoc length edits advance section revision and shift layout while preserving IDs" {
  let verse_id = section_test_occurrence_id("verse:doc")
  let chorus_id = section_test_occurrence_id("chorus:doc")
  let doc = section_test_section_doc(
    section_test_section_id("section:length"),
    section_test_layer_id("layer:length"),
    "Length",
    @pattern.Rational::from_int(1),
    60.0,
  )
  let longer_result = try? doc.with_length(
    length_cycles=@pattern.Rational::from_int(2),
  )
  let longer = match longer_result {
    Ok(doc) => doc
    Err(_) => abort("length edit failed")
  }
  @debug.assert_eq(longer.id().value(), doc.id().value())
  assert_true(longer.revision().value() > doc.revision().value())
  let chorus = Section::from_pattern(name="chorus", body=@pattern.note(67.0))
  let before_result = try? @song.Song(parts=[
    @song.SongPart::with_id(id=verse_id, name="Verse", section=doc.to_section()),
    @song.SongPart::with_id(id=chorus_id, name="Chorus", section=chorus),
  ])
  let after_result = try? @song.Song(parts=[
    @song.SongPart::with_id(
      id=verse_id,
      name="Verse",
      section=longer.to_section(),
    ),
    @song.SongPart::with_id(id=chorus_id, name="Chorus", section=chorus),
  ])
  let before = match before_result {
    Ok(song) => song
    Err(_) => abort("before song creation failed")
  }
  let after = match after_result {
    Ok(song) => song
    Err(_) => abort("after song creation failed")
  }
  match
    (
      before.get_occurrence_by_id(chorus_id),
      after.get_occurrence_by_id(chorus_id),
    ) {
    (Some(before_chorus), Some(after_chorus)) => {
      @debug.assert_eq(before_chorus.id().value(), after_chorus.id().value())
      assert_true(before_chorus.start() == @pattern.Rational::from_int(1))
      assert_true(after_chorus.start() == @pattern.Rational::from_int(2))
    }
    _ => abort("expected chorus occurrences")
  }
}

///|
test "SectionBody::layers stacks ordered named layers" {
  let result = try? Section(
    name="chorus",
    length_cycles=@pattern.Rational::from_int(1),
    scope=TimeScope::identity(),
    body=SectionBody::layers([
      @song.SectionLayer(name="bass", body=@pattern.note(36.0)),
      @song.SectionLayer(name="lead", body=@pattern.note(64.0)),
    ]),
  )
  let section = match result {
    Ok(section) => section
    Err(_) => abort("section creation failed")
  }
  @debug.assert_eq(section.layer_count(), 2)
  assert_true(section.get_layer("bass") is Some(_))
  assert_true(section.get_layer("lead") is Some(_))
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  @debug.assert_eq(events.length(), 2)
  assert_true(events[0].value.get("note") == Some(36.0))
  assert_true(events[1].value.get("note") == Some(64.0))
}

///|
test "Section constructor accepts pattern body wrapper" {
  let pat = @pattern.note(60.0)
  let result = try? Section(
    name="main",
    length_cycles=@pattern.Rational::from_int(1),
    scope=TimeScope::identity(),
    body=SectionBody::single(pat),
  )
  let section = match result {
    Ok(section) => section
    Err(_) => abort("section creation failed")
  }
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  @debug.assert_eq(events.length(), 1)
  assert_true(events[0].value.get("note") == Some(60.0))
}

///|
test "Section::layer converts single body to named layers" {
  let base = Section::from_pattern(name="verse", body=@pattern.note(48.0))
  let section = base.layer(name="counter", body=@pattern.note(55.0))
  @debug.assert_eq(section.layer_count(), 2)
  assert_true(section.get_layer("main") is Some(_))
  assert_true(section.get_layer("counter") is Some(_))
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  @debug.assert_eq(events.length(), 2)
  assert_true(events[0].value.get("note") == Some(48.0))
  assert_true(events[1].value.get("note") == Some(55.0))
}

///|
test "Section::layer replaces existing layer by name" {
  let base = Section::from_pattern(name="verse", body=@pattern.note(48.0))
  let section = base.layer(name="main", body=@pattern.note(60.0))
  @debug.assert_eq(section.layer_count(), 1)
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  @debug.assert_eq(events.length(), 1)
  assert_true(events[0].value.get("note") == Some(60.0))
}

///|
test "Section::apply_patch add layer appends named layer" {
  let base = Section::from_pattern(name="verse", body=@pattern.note(48.0))
  let result = try? base.apply_patch(
    SectionPatch::add_layer("counter", @pattern.note(55.0)),
  )
  let section = match result {
    Ok(section) => section
    Err(_) => abort("patch failed")
  }
  @debug.assert_eq(section.layer_count(), 2)
  assert_true(section.get_layer("counter") is Some(_))
}

///|
test "Section::apply_patch set layer replaces existing layer" {
  let single = Section::from_pattern(name="verse", body=@pattern.note(48.0))
  let base = single.layer(name="counter", body=@pattern.note(55.0))
  let result = try? base.apply_patch(
    SectionPatch::set_layer("counter", @pattern.note(67.0)),
  )
  let section = match result {
    Ok(section) => section
    Err(_) => abort("patch failed")
  }
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::from_int(1),
  )
  let events = section.body().query(arc)
  @debug.assert_eq(events.length(), 2)
  assert_true(events[0].value.get("note") == Some(48.0))
  assert_true(events[1].value.get("note") == Some(67.0))
}

///|
test "Section::apply_patch add layer rejects duplicate layer" {
  let base = Section::from_pattern(name="verse", body=@pattern.note(48.0))
  let result = try? base.apply_patch(
    SectionPatch::add_layer("main", @pattern.note(55.0)),
  )
  match result {
    Err(SectionPatchError::DuplicateLayer("main")) => ()
    _ => assert_true(false)
  }
}

///|
test "Section::apply_patch set layer rejects missing layer" {
  let base = Section::from_pattern(name="verse", body=@pattern.note(48.0))
  let result = try? base.apply_patch(
    SectionPatch::set_layer("counter", @pattern.note(55.0)),
  )
  match result {
    Err(SectionPatchError::MissingLayer("counter")) => ()
    _ => assert_true(false)
  }
}
