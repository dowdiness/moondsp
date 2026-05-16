///|
fn song_doc_test_occurrence_id(value : String) -> @identity.OccurrenceId {
  let result = try? @identity.OccurrenceId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("occurrence id creation failed")
  }
}

///|
fn song_doc_test_section_id(value : String) -> @identity.SectionId {
  let result = try? @identity.SectionId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("section id creation failed")
  }
}

///|
fn song_doc_test_layer_id(value : String) -> @identity.SectionLayerId {
  let result = try? @identity.SectionLayerId::from_string(value)
  match result {
    Ok(id) => id
    Err(_) => abort("layer id creation failed")
  }
}

///|
fn song_doc_test_section(
  id : String,
  name : String,
  length : @pattern.Rational,
  midi : Double,
) -> @song.SectionDoc[@pattern.ControlMap] {
  let result = try? @song.SectionDoc::single(
    id=song_doc_test_section_id(id),
    name~,
    length_cycles=length,
    scope=@song.TimeScope::identity(),
    layer_id=song_doc_test_layer_id("\{id}:main"),
    body=@pattern.note(midi),
  )
  match result {
    Ok(section) => section
    Err(_) => abort("section doc creation failed")
  }
}

///|
fn song_doc_test_doc(
  occurrences : Array[@song.SongOccurrenceDoc[@pattern.ControlMap]],
) -> @song.SongDoc[@pattern.ControlMap] {
  let result = try? @song.SongDoc(parts=occurrences)
  match result {
    Ok(doc) => doc
    Err(_) => abort("song doc creation failed")
  }
}

///|
fn song_doc_test_song(
  doc : @song.SongDoc[@pattern.ControlMap],
) -> @song.Song[@pattern.ControlMap] {
  let result = try? doc.to_song()
  match result {
    Ok(song) => song
    Err(_) => abort("song lowering failed")
  }
}

///|
fn song_doc_test_snapshot(
  doc : @song.SongDoc[@pattern.ControlMap],
) -> @song.SongSnapshot[@pattern.ControlMap] {
  let result = try? doc.lower()
  match result {
    Ok(snapshot) => snapshot
    Err(_) => abort("song snapshot lowering failed")
  }
}

///|
test "SongSnapshot::query_sourced_events tags occurrence section and layer IDs" {
  let occurrence_id = song_doc_test_occurrence_id("occurrence:sourced-layer")
  let section_id = song_doc_test_section_id("section:sourced-layer")
  let lead_id = song_doc_test_layer_id("layer:sourced-lead")
  let pad_id = song_doc_test_layer_id("layer:sourced-pad")
  let section_result = try? @song.SectionDoc::SectionDoc(
    id=section_id,
    name="Sourced",
    length_cycles=@pattern.Rational::from_int(1),
    scope=@song.TimeScope::identity(),
    body=@song.SectionDocBody::layers([
      @song.SectionLayerDoc(id=lead_id, name="Lead", body=@pattern.note(60.0)),
      @song.SectionLayerDoc(id=pad_id, name="Pad", body=@pattern.note(67.0)),
    ]),
  )
  let section = match section_result {
    Ok(section) => section
    Err(_) => abort("section doc creation failed")
  }
  let doc = song_doc_test_doc([
    @song.SongOccurrenceDoc(id=occurrence_id, name="Sourced", section~),
  ])
  let snapshot = song_doc_test_snapshot(doc)
  let events = snapshot.query_sourced_events(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::new(1L, 100L),
    ),
  )
  @debug.assert_eq(events.length(), 2)
  assert_true(events[0].occurrence() == occurrence_id)
  assert_true(events[0].section() == Some(section_id))
  assert_true(events[0].layer() == Some(lead_id))
  assert_true(events[0].event().value.get("note") == Some(60.0))
  assert_true(events[1].occurrence() == occurrence_id)
  assert_true(events[1].section() == Some(section_id))
  assert_true(events[1].layer() == Some(pad_id))
  assert_true(events[1].event().value.get("note") == Some(67.0))
}

///|
test "SongDoc occurrence renames preserve identity and layout revision" {
  let verse_id = song_doc_test_occurrence_id("verse:layout")
  let chorus_id = song_doc_test_occurrence_id("chorus:layout")
  let verse = song_doc_test_section(
    "section:verse-layout",
    "Verse",
    @pattern.Rational::from_int(1),
    60.0,
  )
  let chorus = song_doc_test_section(
    "section:chorus-layout",
    "Chorus",
    @pattern.Rational::from_int(1),
    67.0,
  )
  let doc = song_doc_test_doc([
    @song.SongOccurrenceDoc(id=verse_id, name="Verse A", section=verse),
    @song.SongOccurrenceDoc(id=chorus_id, name="Chorus A", section=chorus),
  ])
  let before_song = song_doc_test_song(doc)
  let before_occurrence = match doc.get_occurrence(verse_id) {
    Some(occurrence) => occurrence
    None => abort("expected verse occurrence doc")
  }
  let renamed_result = try? doc.rename_occurrence(verse_id, name="Verse Intro")
  let renamed = match renamed_result {
    Ok(doc) => doc
    Err(_) => abort("rename failed")
  }
  let renamed_occurrence = match renamed.get_occurrence(verse_id) {
    Some(occurrence) => occurrence
    None => abort("expected renamed occurrence doc")
  }
  @debug.assert_eq(renamed_occurrence.id().value(), "verse:layout")
  @debug.assert_eq(renamed_occurrence.name(), "Verse Intro")
  assert_true(renamed.revision() != doc.revision())
  assert_true(renamed.layout_revision() == doc.layout_revision())
  assert_true(renamed_occurrence.revision() != before_occurrence.revision())
  let after_song = song_doc_test_song(renamed)
  match
    (
      before_song.get_occurrence_by_id(verse_id),
      after_song.get_occurrence_by_id(verse_id),
    ) {
    (Some(before), Some(after)) => {
      @debug.assert_eq(before.id().value(), after.id().value())
      @debug.assert_eq(after.name(), "Verse Intro")
      assert_true(before.start() == after.start())
      assert_true(before.end_() == after.end_())
    }
    _ => abort("expected verse occurrence by id")
  }
}

///|
test "SongDoc insertion and removal preserve surviving occurrence identities" {
  let intro_id = song_doc_test_occurrence_id("intro:insert")
  let verse_id = song_doc_test_occurrence_id("verse:insert")
  let chorus_id = song_doc_test_occurrence_id("chorus:insert")
  let intro = song_doc_test_section(
    "section:intro-insert",
    "Intro",
    @pattern.Rational::from_int(1),
    50.0,
  )
  let verse = song_doc_test_section(
    "section:verse-insert",
    "Verse",
    @pattern.Rational::from_int(1),
    60.0,
  )
  let chorus = song_doc_test_section(
    "section:chorus-insert",
    "Chorus",
    @pattern.Rational::from_int(1),
    67.0,
  )
  let doc = song_doc_test_doc([
    @song.SongOccurrenceDoc(id=intro_id, name="Intro", section=intro),
    @song.SongOccurrenceDoc(id=chorus_id, name="Chorus", section=chorus),
  ])
  let inserted_result = try? doc.insert_occurrence(
    index=1,
    occurrence=@song.SongOccurrenceDoc(id=verse_id, name="Verse", section=verse),
  )
  let inserted = match inserted_result {
    Ok(doc) => doc
    Err(_) => abort("insert failed")
  }
  assert_true(inserted.layout_revision() != doc.layout_revision())
  let inserted_song = song_doc_test_song(inserted)
  @debug.assert_eq(inserted_song.occurrence_count(), 3)
  match inserted_song.get_occurrence_by_id(chorus_id) {
    Some(chorus_occurrence) => {
      @debug.assert_eq(chorus_occurrence.id().value(), "chorus:insert")
      assert_true(chorus_occurrence.start() == @pattern.Rational::from_int(2))
    }
    None => abort("expected chorus after insertion")
  }
  let removed_result = try? inserted.remove_occurrence(intro_id)
  let removed = match removed_result {
    Ok(doc) => doc
    Err(_) => abort("remove failed")
  }
  assert_true(removed.layout_revision() != inserted.layout_revision())
  assert_true(removed.get_occurrence(verse_id) is Some(_))
  assert_true(removed.get_occurrence(chorus_id) is Some(_))
  assert_true(removed.get_occurrence(intro_id) is None)
  let removed_song = song_doc_test_song(removed)
  match removed_song.get_occurrence_by_id(verse_id) {
    Some(verse_occurrence) =>
      assert_true(verse_occurrence.start() == @pattern.Rational::from_int(0))
    None => abort("expected verse after removal")
  }
}

///|
test "SongDoc reorder preserves IDs while recomputing implicit spans" {
  let a_id = song_doc_test_occurrence_id("a:reorder")
  let b_id = song_doc_test_occurrence_id("b:reorder")
  let c_id = song_doc_test_occurrence_id("c:reorder")
  let a = song_doc_test_section(
    "section:a-reorder",
    "A",
    @pattern.Rational::from_int(1),
    60.0,
  )
  let b = song_doc_test_section(
    "section:b-reorder",
    "B",
    @pattern.Rational::from_int(2),
    62.0,
  )
  let c = song_doc_test_section(
    "section:c-reorder",
    "C",
    @pattern.Rational::from_int(1),
    64.0,
  )
  let doc = song_doc_test_doc([
    @song.SongOccurrenceDoc(id=a_id, name="A", section=a),
    @song.SongOccurrenceDoc(id=b_id, name="B", section=b),
    @song.SongOccurrenceDoc(id=c_id, name="C", section=c),
  ])
  let moved_result = try? doc.move_occurrence(c_id, index=0)
  let moved = match moved_result {
    Ok(doc) => doc
    Err(_) => abort("move failed")
  }
  assert_true(moved.layout_revision() != doc.layout_revision())
  let moved_song = song_doc_test_song(moved)
  match
    (
      moved_song.get_occurrence_by_id(c_id),
      moved_song.get_occurrence_by_id(a_id),
      moved_song.get_occurrence_by_id(b_id),
    ) {
    (Some(c_occurrence), Some(a_occurrence), Some(b_occurrence)) => {
      assert_true(c_occurrence.start() == @pattern.Rational::from_int(0))
      assert_true(a_occurrence.start() == @pattern.Rational::from_int(1))
      assert_true(b_occurrence.start() == @pattern.Rational::from_int(2))
      @debug.assert_eq(c_occurrence.id().value(), "c:reorder")
      @debug.assert_eq(a_occurrence.id().value(), "a:reorder")
      @debug.assert_eq(b_occurrence.id().value(), "b:reorder")
    }
    _ => abort("expected moved occurrences by id")
  }
}

///|
test "SongDoc section length edits shift downstream spans and preserve IDs" {
  let verse_id = song_doc_test_occurrence_id("verse:length-doc")
  let chorus_id = song_doc_test_occurrence_id("chorus:length-doc")
  let verse = song_doc_test_section(
    "section:verse-length-doc",
    "Verse",
    @pattern.Rational::from_int(1),
    60.0,
  )
  let longer_result = try? verse.with_length(
    length_cycles=@pattern.Rational::from_int(2),
  )
  let longer_verse = match longer_result {
    Ok(section) => section
    Err(_) => abort("length edit failed")
  }
  let chorus = song_doc_test_section(
    "section:chorus-length-doc",
    "Chorus",
    @pattern.Rational::from_int(1),
    67.0,
  )
  let doc = song_doc_test_doc([
    @song.SongOccurrenceDoc(id=verse_id, name="Verse", section=verse),
    @song.SongOccurrenceDoc(id=chorus_id, name="Chorus", section=chorus),
  ])
  let edited_result = try? doc.replace_occurrence_section(
    verse_id,
    section=longer_verse,
  )
  let edited = match edited_result {
    Ok(doc) => doc
    Err(_) => abort("replace section failed")
  }
  assert_true(edited.layout_revision() != doc.layout_revision())
  let edited_song = song_doc_test_song(edited)
  match edited_song.get_occurrence_by_id(chorus_id) {
    Some(chorus_occurrence) => {
      @debug.assert_eq(chorus_occurrence.id().value(), "chorus:length-doc")
      assert_true(chorus_occurrence.start() == @pattern.Rational::from_int(2))
    }
    None => abort("expected chorus after length edit")
  }
}

///|
test "SongDoc same-length section edits reuse layout and unchanged sections" {
  let verse_id = song_doc_test_occurrence_id("verse:reuse")
  let chorus_id = song_doc_test_occurrence_id("chorus:reuse")
  let layer_id = song_doc_test_layer_id("section:verse-reuse:main")
  let verse = song_doc_test_section(
    "section:verse-reuse",
    "Verse",
    @pattern.Rational::from_int(1),
    60.0,
  )
  let edited_verse_result = try? verse.replace_layer_body(
    layer_id,
    body=@pattern.note(61.0),
  )
  let edited_verse = match edited_verse_result {
    Ok(section) => section
    Err(_) => abort("body edit failed")
  }
  let chorus = song_doc_test_section(
    "section:chorus-reuse",
    "Chorus",
    @pattern.Rational::from_int(1),
    67.0,
  )
  let doc = song_doc_test_doc([
    @song.SongOccurrenceDoc(id=verse_id, name="Verse", section=verse),
    @song.SongOccurrenceDoc(id=chorus_id, name="Chorus", section=chorus),
  ])
  let original_chorus = match doc.get_occurrence(chorus_id) {
    Some(occurrence) => occurrence.section()
    None => abort("expected original chorus")
  }
  let edited_result = try? doc.replace_occurrence_section(
    verse_id,
    section=edited_verse,
  )
  let edited = match edited_result {
    Ok(doc) => doc
    Err(_) => abort("replace section failed")
  }
  assert_true(edited.revision() != doc.revision())
  assert_true(edited.layout_revision() == doc.layout_revision())
  let edited_chorus = match edited.get_occurrence(chorus_id) {
    Some(occurrence) => occurrence.section()
    None => abort("expected edited chorus")
  }
  assert_true(edited_chorus.id() == original_chorus.id())
  assert_true(edited_chorus.revision() == original_chorus.revision())
  let edited_song = song_doc_test_song(edited)
  match edited_song.get_occurrence_by_id(chorus_id) {
    Some(chorus_occurrence) =>
      assert_true(chorus_occurrence.start() == @pattern.Rational::from_int(1))
    None => abort("expected chorus span after body edit")
  }
  let events = edited_song.query(
    @pattern.TimeSpan::new(
      @pattern.Rational::from_int(0),
      @pattern.Rational::from_int(1),
    ),
  )
  @debug.assert_eq(events.length(), 1)
  assert_true(events[0].value.get("note") == Some(61.0))
}

///|
test "SongDoc rename reports missing occurrence before duplicate display name" {
  let verse_id = song_doc_test_occurrence_id("verse:missing")
  let chorus_id = song_doc_test_occurrence_id("chorus:missing")
  let missing_id = song_doc_test_occurrence_id("missing:missing")
  let verse = song_doc_test_section(
    "section:verse-missing",
    "Verse",
    @pattern.Rational::from_int(1),
    60.0,
  )
  let chorus = song_doc_test_section(
    "section:chorus-missing",
    "Chorus",
    @pattern.Rational::from_int(1),
    67.0,
  )
  let doc = song_doc_test_doc([
    @song.SongOccurrenceDoc(id=verse_id, name="Verse", section=verse),
    @song.SongOccurrenceDoc(id=chorus_id, name="Chorus", section=chorus),
  ])
  let result = try? doc.rename_occurrence(missing_id, name="Chorus")
  match result {
    Err(@song.SongDocEditError::MissingSongDocOccurrenceId("missing:missing")) =>
      ()
    _ => assert_true(false)
  }
}
