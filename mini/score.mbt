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
/// The score as notes, unless it plays drums. Silence plays no drums, so its
/// document plays only notes.
fn Score::notes(self : Score) -> NoteDoc? {
  match self {
    Notes(notes) => Some(notes)
    Silent(doc) => Some(NoteDoc(doc))
    Hits(_) | Mixed(_) => None
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
  instruments : @pattern.PatternDoc[VoiceName],
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
/// `event` played on `voice`: an instrument, or a sample at the note's pitch.
fn played_on(event : @score.ScoreEvent, voice : VoiceName) -> @score.ScoreEvent {
  match event.sound {
    Note(_, pitch~) | Play(_, pitch~) =>
      match voice {
        Instrument(instrument) => { ..event, sound: Note(instrument, pitch~), }
        Sample(sample) => { ..event, sound: Play(sample, pitch~), }
      }
    // Unreachable: a `NoteDoc` holds no hits. Pattern queries run on the
    // audio thread, so the event stays as it is instead of aborting. A
    // payload that rules out hits is rejected in ADR-0022.
    Hit(_) => event
  }
}

///|
/// The methods that may follow `receiver`, a pattern or `song(…)` after the
/// `let` bindings it uses. Code that does not compile takes none. A signal's
/// methods do not depend on the signal, so they are its position's calls.
pub fn methods_after(receiver : String) -> Array[Call] {
  let parser = Parser(receiver)
  let builder = MiniDocBuilder()
  (fn() raise SourceProblem {
    parser.parse_bindings(builder)
    parser.skip_whitespace()
    let at = parser.pos
    match parser.read_call(Arrangement::parse) {
      Some(Song) => {
        let (_, repeating, _) = parser.parse_play_song(
          at,
          builder,
          None,
          None,
          lower=doc => doc.lower().pat(),
        )
        if repeating {
          []
        } else {
          ArrangementMethod::all().map(ArrangementMethod::call)
        }
      }
      None => {
        let score = compile_score(
          resolve_mini_expr(parser.parse_syntax_expr(), parser.bindings),
          builder,
        )
        parser.expect_end()
        Method::all()
        .filter(candidate => candidate.follows(score))
        .map(Method::call)
      }
    }
  })() catch {
    _ => []
  }
}

///|
/// Whether the method may follow `score`, by the rules the compiler applies.
fn Method::follows(self : Method, score : Score) -> Bool {
  match self {
    Instrument => score.notes() is Some(_)
    Fast
    | Slow
    | FadeIn
    | FadeOut
    | Gate
    | Rev
    | DegradeBy
    | Lpf
    | Hpf
    | Attack
    | Hold
    | Release
    | Gain
    | Pan
    | Room
    | Every
    | Jux => true
  }
}
