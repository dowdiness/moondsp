///|
/// A document that plays only notes, so `.s` can choose their instrument.
priv struct NoteDoc(ScoreDoc)

///|
/// A compiled score expression, by what it plays: nothing, only drum hits,
/// only notes, or both (ADR-0022).
priv enum Score {
  Silent(ScoreDoc)
  Hits(ScoreDoc)
  Notes(NoteDoc)
  Mixed(ScoreDoc)
}

///|
fn Score::doc(self : Score) -> ScoreDoc {
  match self {
    Silent(doc) | Hits(doc) | Mixed(doc) | Notes(NoteDoc(doc)) => doc
  }
}

///|
/// The score of `doc`, which plays drums when `hits` and notes when `notes`.
fn Score::of(doc : ScoreDoc, hits~ : Bool, notes~ : Bool) -> Score {
  match (hits, notes) {
    (false, false) => Silent(doc)
    (true, false) => Hits(doc)
    (false, true) => Notes(NoteDoc(doc))
    (true, true) => Mixed(doc)
  }
}

///|
fn Score::plays_hits(self : Score) -> Bool {
  self is (Hits(_) | Mixed(_))
}

///|
fn Score::plays_notes(self : Score) -> Bool {
  self is (Notes(_) | Mixed(_))
}

///|
/// The same sounds, with `change` applied to the document.
fn Score::map(
  self : Score,
  change : (ScoreDoc) -> ScoreDoc raise SourceProblem,
) -> Score raise SourceProblem {
  Score::of(
    change(self.doc()),
    hits=self.plays_hits(),
    notes=self.plays_notes(),
  )
}

///|
/// `scores` played together.
fn Score::stack(
  builder : MiniDocBuilder,
  scores : Array[Score],
) -> Score raise SourceProblem {
  Score::of(
    builder.stack_doc(scores.map(Score::doc)),
    hits=scores.iter().any(Score::plays_hits),
    notes=scores.iter().any(Score::plays_notes),
  )
}

///|
/// Play each note on the instrument `instruments` has at its onset.
fn NoteDoc::on(
  self : NoteDoc,
  builder : MiniDocBuilder,
  instruments : @pattern.PatternDoc[@score.Instrument],
) -> NoteDoc raise SourceProblem {
  let NoteDoc(doc) = self
  let id = builder.node_id("instruments", [doc.root(), instruments.root()], "")
  NoteDoc(
    @pattern.PatternDoc::merge_values(
      id~,
      left=doc,
      right=instruments,
      apply=played_on,
    ) catch {
      _ => raise Internal("internal mini PatternDoc construction failed")
    },
  )
}

///|
/// `event` played on `instrument`.
fn played_on(
  event : @score.ScoreEvent,
  instrument : @score.Instrument,
) -> @score.ScoreEvent {
  match event.sound {
    Note(_, pitch~) => { ..event, sound: Note(instrument, pitch~), }
    // Unreachable: a `NoteDoc` holds no hits. Pattern queries run on the
    // audio thread, so the event stays as it is instead of aborting.
    Hit(_) => event
  }
}
