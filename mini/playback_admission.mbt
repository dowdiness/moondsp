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
  scale? : Double = 1.0,
  aligned? : Bool = false,
  depth? : Int = 0,
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
    Precision(child, magnitude) =>
      child.estimate(width, scale=scale * magnitude, aligned~, depth=depth + 1)
  }
}

///|
fn MiniQueryWork::check(
  self : MiniQueryWork,
  width : Double,
) -> Unit raise ParseError {
  guard self.estimate(width).allowed() else {
    raise ParseError("playback source exceeds the query expansion limit")
  }
}

///|
/// The pre-scan only bounds lexical size/depth; syntax still belongs to Parser.
fn check_playback_source_size(input : String) -> Unit raise ParseError {
  guard input.length() <= 8192 else {
    raise ParseError("playback source exceeds 8192 characters")
  }
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
            raise ParseError("position \{index}: unterminated block comment")
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
    guard depth + quoted_depth <= 32 else {
      raise ParseError("playback source exceeds nesting depth 32")
    }
    index += 1
  }
}

///|
priv struct PlaybackAdmission {
  width : Double
  definitions : Map[String, MiniQueryWork]
  sections : Map[String, MiniQueryWork]
  roots : Array[MiniQueryWork]
  mut last : MiniQueryWork
  mut nodes : Int
}

///|
fn PlaybackAdmission::PlaybackAdmission(width : Double) -> PlaybackAdmission {
  { width, definitions: {}, sections: {}, roots: [], last: Quiet, nodes: 0, }
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
  expr : MiniExpr,
  depth? : Int = 0,
) -> MiniQueryWork raise ParseError {
  self.nodes += 1
  guard self.nodes <= 512 && depth <= 32 else {
    raise ParseError("playback source exceeds 512 syntax nodes or depth 32")
  }
  let work = match expr.node {
    Literal(Silence, _, _) => Quiet
    Literal(kind, content, _) => {
      let notation = NotationParser(
        content,
        sound=kind is Sound,
        chord=kind is Chord,
        assess=true,
      )
      ignore(notation.parse_notation())
      notation.query_work.unwrap()
    }
    Reference(name) =>
      match self.definitions.get(name) {
        Some(work) => work
        None => raise ParseError("undefined pattern '\{name}'")
      }
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
        Gate(_)
        | Degrade(_, _)
        | Transpose(_)
        | Steps(_, _)
        | Lowest
        | Voicing(_, _, _)
        | Mask(_)
        | PhaseTranspose(_, _, _) => MapEvents(child)
        Tail(tail, kind, content, _) => {
          let replacement = if kind is Silence {
            Quiet
          } else {
            let notation = NotationParser(
              content,
              sound=kind is Sound,
              chord=kind is Chord,
              assess=true,
            )
            ignore(notation.parse_notation())
            notation.query_work.unwrap()
          }
          Overlay([
            MapEvents(child),
            Precision(
              Accelerate(replacement, 1.0 / tail.to_double()),
              tail.den.to_double(),
            ),
          ])
        }
        Rev => Split(child)
        Control(_, _) => MergeScalar(child)
        Filter(_, _, resonance) =>
          if resonance is Some(_) {
            MergeScalar(MergeScalar(child))
          } else {
            MergeScalar(child)
          }
        Every(_, callback) =>
          Split(Overlay([child, callback.query_work(child)]))
        Jux(callback) =>
          Overlay([MergeScalar(child), MergeScalar(callback.query_work(child))])
      }
    }
  }
  work.check(self.width)
  self.last = work
  work
}

///|
fn PlaybackAdmission::arrangement(
  self : PlaybackAdmission,
  song : @song.Song[@pattern.ControlMap],
  repeating : Bool,
) -> Unit raise ParseError {
  let occurrences = song.occurrences()
  guard occurrences is [first, ..] else { return }
  let mut minimum_length = first.section().length_cycles().to_double()
  let mut maximum_overlap = 0
  let mut events = 0.0
  let mut work = 0.0
  for occurrence in occurrences {
    let bound = self.sections[occurrence.section().name()].estimate(self.width)
    guard bound.allowed() else {
      raise ParseError("playback source exceeds the query expansion limit")
    }
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
    raise ParseError("playback arrangement exceeds the query expansion limit")
  }
}
