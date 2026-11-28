///|
/// Private source-admission model, not a second parser or a runtime query wrapper.
/// Counts intermediate expansion, including full-cycle sequence queries and the
/// cross-product used by scalar control merging. Saturates before alias DAGs can
/// expand into an exponentially large traversal.
priv enum MiniQueryWork {
  Quiet
  Atom
  Overlay(Array[MiniQueryWork])
  Slots(Array[MiniQueryWork])
  Accelerate(MiniQueryWork, Double)
  Split(MiniQueryWork)
  MapEvents(MiniQueryWork)
  MergeScalar(MiniQueryWork)
  /// Merge a control pattern: every left event folds over the right events
  /// of the same query.
  MergeWith(MiniQueryWork, MiniQueryWork)
  Precision(MiniQueryWork, Double)
}

///|
const PLAYBACK_WORK_LIMIT : Double = 65536.0

///|
const PLAYBACK_EVENT_LIMIT : Double = 256.0

///|
priv struct MiniQueryBound {
  events : Double
  work : Double
}

///|
fn MiniQueryBound::MiniQueryBound(
  events : Double,
  work : Double,
) -> MiniQueryBound {
  { events, work, }
}

///|
fn MiniQueryBound::allowed(self : MiniQueryBound) -> Bool {
  self.events <= PLAYBACK_EVENT_LIMIT && self.work <= PLAYBACK_WORK_LIMIT
}

///|
fn MiniQueryWork::estimate(
  self : MiniQueryWork,
  width : Double,
  scale~ : Double = 1.0,
  aligned~ : Bool = false,
  depth~ : Int32 = 0,
) -> MiniQueryBound {
  guard depth <= 64 &&
    width >= 0.0 &&
    width <= PLAYBACK_EVENT_LIMIT &&
    scale <= 1000000000.0 else {
    return MiniQueryBound(PLAYBACK_EVENT_LIMIT + 1.0, PLAYBACK_WORK_LIMIT + 1.0)
  }
  let cycles = width.ceil() + (if aligned { 0.0 } else { 1.0 })
  match self {
    Quiet => MiniQueryBound(0.0, 1.0)
    Atom => MiniQueryBound(cycles, cycles)
    Overlay(children) => {
      let mut events = 0.0
      let mut work = 1.0
      for child in children {
        let bound = child.estimate(width, scale~, aligned~, depth=depth + 1)
        events += bound.events
        work += bound.work
        guard events <= PLAYBACK_EVENT_LIMIT && work <= PLAYBACK_WORK_LIMIT else {
          return MiniQueryBound(events, work)
        }
      }
      MiniQueryBound(events, work)
    }
    Slots(children) => {
      let n = children.length().to_double()
      let mut events = 0.0
      let mut work = 1.0
      for child in children {
        // sequence queries exactly [0,1), even for a tiny intersected slot.
        let bound = child.estimate(
          1.0,
          scale=scale * n,
          aligned=true,
          depth=depth + 1,
        )
        guard bound.allowed() else { return bound }
        events = events.max(bound.events)
        work = work.max(bound.work)
      }
      let slots = ((width * n).ceil() + 1.0).min(cycles * n)
      MiniQueryBound(slots * events, cycles * n + slots * (work + events))
    }
    Accelerate(child, factor) => {
      let bound = child.estimate(
        width * factor,
        scale~,
        aligned~,
        depth=depth + 1,
      )
      MiniQueryBound(bound.events, bound.work + bound.events + 1.0)
    }
    Split(child) => {
      let bound = child.estimate(width.min(1.0), scale~, depth=depth + 1)
      MiniQueryBound(
        cycles * bound.events,
        cycles * (bound.work + bound.events + 1.0),
      )
    }
    MapEvents(child) => {
      let bound = child.estimate(width, scale~, aligned~, depth=depth + 1)
      MiniQueryBound(bound.events, bound.work + bound.events + 1.0)
    }
    MergeScalar(child) => {
      let bound = child.estimate(width, scale~, aligned~, depth=depth + 1)
      MiniQueryBound(bound.events, bound.work + bound.events * cycles + cycles)
    }
    MergeWith(left, right) => {
      let left = left.estimate(width, scale~, aligned~, depth=depth + 1)
      let right = right.estimate(width, scale~, aligned~, depth=depth + 1)
      MiniQueryBound(
        left.events,
        left.work + right.work + left.events * right.events + 1.0,
      )
    }
    Precision(child, magnitude) =>
      child.estimate(width, scale=scale * magnitude, aligned~, depth=depth + 1)
  }
}

///|
fn MiniQueryWork::check(
  self : MiniQueryWork,
  width : Double,
) -> Unit raise SourceProblem {
  guard self.estimate(width).allowed() else {
    raise OverLimit(PatternExpansion)
  }
}

///|
/// The pre-scan only bounds lexical size/depth; syntax still belongs to Parser.
fn check_playback_source_size(input : String) -> Unit raise SourceProblem {
  guard input.length() <= 8192 else { raise OverLimit(Length) }
  let mut depth = 0
  let mut quoted_depth = 0
  let mut quoted = false
  let mut index = 0
  while index < input.length() {
    let unit = input[index]
    if !quoted && unit == '/' {
      match mini_comment_end(input, index) {
        Some(end_) => {
          index = end_
          continue
        }
        None =>
          if index + 1 < input.length() && input[index + 1] == '*' {
            raise Mistake(index, "unterminated block comment")
          }
      }
    }
    if unit == '"' {
      quoted = !quoted
      quoted_depth = 0
    } else {
      match unit {
        '(' | '[' => if quoted { quoted_depth += 1 } else { depth += 1 }
        ')' | ']' =>
          if quoted {
            quoted_depth = (quoted_depth - 1).max(0)
          } else {
            depth = (depth - 1).max(0)
          }
        _ => ()
      }
    }
    guard depth + quoted_depth <= 32 else { raise OverLimit(Nesting(32)) }
    index += 1
  }
}

///|
priv struct PlaybackAdmission {
  width : Double
  /// The work of each definition assessed so far, by its name's position.
  definitions : Map[Int32, MiniQueryWork]
  sections : Map[String, MiniQueryWork]
  roots : Array[MiniQueryWork]
  mut nodes : Int32
}

///|
fn PlaybackAdmission::PlaybackAdmission(width : Double) -> PlaybackAdmission {
  { width, definitions: {}, sections: {}, roots: [], nodes: 0, }
}

///|
/// Merging this argument into `child`. A number or signal answers each query
/// with one event per cycle, like a scalar.
fn control_value_work(
  value : ControlValue,
  child : MiniQueryWork,
) -> MiniQueryWork raise SourceProblem {
  match value {
    Number(_) | Signal(_) => MergeScalar(child)
    Steps(notation) => MergeWith(child, notation.query_work())
  }
}

///|
/// The work of the definition named at `name_span`, assessed once however
/// often it is used.
fn PlaybackAdmission::definition(
  self : PlaybackAdmission,
  name_span : MiniSpan,
  body : ResolvedMiniExpr,
) -> MiniQueryWork raise SourceProblem {
  match self.definitions.get(name_span.start) {
    Some(work) => work
    None => {
      let work = self.expression(body)
      self.definitions[name_span.start] = work
      work
    }
  }
}

///|
fn MiniCallback::query_work(
  self : MiniCallback,
  child : MiniQueryWork,
) -> MiniQueryWork {
  match self {
    Fast(n) => Precision(Accelerate(child, n.to_double()), n.to_double())
    Slow(n) => Precision(Accelerate(child, 1.0 / n.to_double()), n.to_double())
    Rev => Split(child)
  }
}

///|
fn PlaybackAdmission::expression(
  self : PlaybackAdmission,
  expr : ResolvedMiniExpr,
  depth~ : Int32 = 0,
) -> MiniQueryWork raise SourceProblem {
  self.nodes += 1
  guard self.nodes <= 512 && depth <= 32 else { raise OverLimit(SyntaxNodes) }
  let work = match expr.node {
    Silence => Quiet
    Sounds(notation) => notation.query_work()
    Notes(notation) => notation.query_work()
    Chords(notation) => notation.query_work(word_work=ChordName::query_work)
    Reference(_, definition) =>
      self.definition(definition.name_span, definition.syntax)
    Instruments(child, notation, _) =>
      MergeWith(self.expression(child, depth=depth + 1), notation.query_work())
    Stack(children) =>
      Overlay(children.map(child => self.expression(child, depth=depth + 1)))
    Apply(child, transform) => {
      let child = self.expression(child, depth=depth + 1)
      match transform {
        Fast(n) =>
          Precision(
            Accelerate(child, n.to_double()),
            n.num.to_double().abs().max(n.den.to_double()),
          )
        Slow(n) =>
          Precision(
            Accelerate(child, 1.0 / n.to_double()),
            n.num.to_double().abs().max(n.den.to_double()),
          )
        Gate(_) | Degrade(_) => MapEvents(child)
        Rev => Split(child)
        Control(_, value) => control_value_work(value, child)
        Filter(_, frequency_hz, resonance) => {
          let filtered = control_value_work(frequency_hz, child)
          match resonance {
            Some(q) => control_value_work(q, filtered)
            None => filtered
          }
        }
        Every(_, callback) =>
          Split(Overlay([child, callback.query_work(child)]))
        Jux(callback) =>
          Overlay([MergeScalar(child), MergeScalar(callback.query_work(child))])
      }
    }
  }
  work.check(self.width)
  work
}

///|
fn[C] PlaybackAdmission::arrangement(
  self : PlaybackAdmission,
  song : @song.Song[C],
  repeating : Bool,
) -> Unit raise SourceProblem {
  let occurrences = song.occurrences()
  guard occurrences is [first, ..] else { return }
  let mut minimum_length = first.section().length_cycles().to_double()
  let mut maximum_overlap = 0
  let mut events = 0.0
  let mut work = 0.0
  for occurrence in occurrences {
    let bound = self.sections[occurrence.section().id().value()].estimate(
      self.width,
    )
    guard bound.allowed() else { raise OverLimit(PatternExpansion) }
    events = events.max(bound.events)
    work = work.max(bound.work)
    minimum_length = minimum_length.min(
      occurrence.section().length_cycles().to_double(),
    )
    let mut overlap = 0
    for other in occurrences {
      if other.start() <= occurrence.start() &&
        occurrence.start() < other.end_() {
        overlap += 1
      }
    }
    maximum_overlap = maximum_overlap.max(overlap)
  }
  // Interval graphs can be partitioned into maximum_overlap disjoint tracks.
  // Each track contributes at most ceil(width/min_length)+2 intersected parts.
  // The extra boundary allowance is conservative under Double rounding too.
  let parts = (maximum_overlap.to_double() *
  ((self.width / minimum_length).ceil() + 2.0)).min(
    occurrences.length().to_double(),
  )
  let queries = parts * (if repeating { 2.0 } else { 1.0 })
  guard MiniQueryBound(events * queries, work * queries).allowed() else {
    raise OverLimit(ArrangementExpansion)
  }
}

///|
const EUCLIDEAN_STEP_LIMIT : Int32 = 128

///|
/// The query work this notation costs playback, refusing a step whose own
/// work no query could afford. `word_work` is the work of one word.
fn[W] NotationSyntax::query_work(
  self : NotationSyntax[W],
  word_work~ : (W) -> MiniQueryWork = _ => Atom,
) -> MiniQueryWork raise SourceProblem {
  notation_layers_work(self.layers, word_work)
}

///|
fn[W] notation_layers_work(
  layers : Array[NotationLayer[W]],
  word_work : (W) -> MiniQueryWork,
) -> MiniQueryWork raise SourceProblem {
  let works = layers.map(layer => {
    let slots = []
    for step in layer.steps {
      slots.push(notation_step_work(step, word_work))
      for _ in 1..<step.slots() {
        slots.push(Quiet)
      }
    }
    if slots.length() == 1 {
      slots[0]
    } else {
      Slots(slots)
    }
  })
  if works.length() == 1 {
    works[0]
  } else {
    Overlay(works)
  }
}

///|
fn[W] notation_step_work(
  step : NotationStep[W],
  word_work : (W) -> MiniQueryWork,
) -> MiniQueryWork raise SourceProblem {
  let mut work : MiniQueryWork = match step.body {
    Rest(_) => Quiet
    Word(word, _) => word_work(word)
    Group(layers, _) => notation_layers_work(layers, word_work)
  }
  for modifier in step.modifiers {
    work = match modifier.kind {
      Euclid(Silent, ..) => Quiet
      Euclid(Pulses(steps~, ..), ..) => {
        guard steps <= EUCLIDEAN_STEP_LIMIT else {
          raise OverLimit(EuclideanSteps)
        }
        Slots(Array::make(steps, work))
      }
      Repeat(n) => Precision(Accelerate(work, n.to_double()), n.to_double())
      Slow(n) => Precision(Accelerate(work, 1.0 / n.to_double()), n.to_double())
      Degrade(..) => MapEvents(work)
    }
    work.check(0.0)
  }
  work.check(0.0)
  work
}

///|
/// A chord plays each of its notes.
fn ChordName::query_work(self : ChordName) -> MiniQueryWork {
  Overlay(Array::make(self.notes.length(), Atom))
}
