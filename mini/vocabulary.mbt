// The names a score writes, one closed enum per position (ADR-0023). Each
// `all()` is the only expression that constructs its enum's cases, so a case
// missing from it fails `moon check --deny-warn` as an unused constructor;
// `parse` reads a name only through `all()`.

///|
/// A call at the start of a statement.
priv enum StatementCall {
  Bpm
  Song
}

///|
fn StatementCall::all() -> Array[StatementCall] {
  [Bpm, Song]
}

///|
fn StatementCall::name(self : StatementCall) -> String {
  match self {
    Bpm => "bpm"
    Song => "song"
  }
}

///|
fn StatementCall::parse(name : String) -> StatementCall? {
  StatementCall::all().iter().find_first(call => call.name() == name)
}

///|
/// A call that writes a pattern: a quoted literal, silence, or a stack.
priv enum PatternCall {
  Literal(MiniLiteral)
  Silence
  Stack
}

///|
fn PatternCall::all() -> Array[PatternCall] {
  [Literal(Sound), Literal(Note), Literal(Chord), Silence, Stack]
}

///|
fn PatternCall::name(self : PatternCall) -> String {
  match self {
    Literal(Sound) => "s"
    Literal(Note) => "note"
    Literal(Chord) => "chord"
    Silence => "silence"
    Stack => "stack"
  }
}

///|
/// How the call opens, for messages that list the calls.
fn PatternCall::opening(self : PatternCall) -> String {
  match self {
    Silence => "silence()"
    Literal(_) | Stack => "\{self.name()}("
  }
}

///|
fn PatternCall::parse(name : String) -> PatternCall? {
  PatternCall::all().iter().find_first(call => call.name() == name)
}

///|
/// An item inside `song(…)`.
priv enum SongItem {
  Bpm
  Section
  Part
  PartId
  Fill
}

///|
fn SongItem::all() -> Array[SongItem] {
  [Bpm, Section, Part, PartId, Fill]
}

///|
fn SongItem::name(self : SongItem) -> String {
  match self {
    Bpm => "bpm"
    Section => "section"
    Part => "part"
    PartId => "part_id"
    Fill => "fill"
  }
}

///|
fn SongItem::parse(name : String) -> SongItem? {
  SongItem::all().iter().find_first(item => item.name() == name)
}

///|
/// A method after `song(…)`.
priv enum ArrangementMethod {
  Repeat
}

///|
fn ArrangementMethod::all() -> Array[ArrangementMethod] {
  [Repeat]
}

///|
fn ArrangementMethod::name(self : ArrangementMethod) -> String {
  match self {
    Repeat => "repeat"
  }
}

///|
fn ArrangementMethod::parse(name : String) -> ArrangementMethod? {
  ArrangementMethod::all()
  .iter()
  .find_first(candidate => candidate.name() == name)
}

///|
/// A method after a pattern.
priv enum Method {
  Fast
  Slow
  Gate
  Rev
  DegradeBy
  Lpf
  Hpf
  Attack
  Hold
  Release
  Gain
  Pan
  Room
  Every
  Jux
  /// `.s("…")`, which chooses the instrument of notes.
  Instruments
}

///|
fn Method::all() -> Array[Method] {
  [
    Fast,
    Slow,
    Gate,
    Rev,
    DegradeBy,
    Lpf,
    Hpf,
    Attack,
    Hold,
    Release,
    Gain,
    Pan,
    Room,
    Every,
    Jux,
    Instruments,
  ]
}

///|
fn Method::name(self : Method) -> String {
  match self {
    Fast => "fast"
    Slow => "slow"
    Gate => "gate"
    Rev => "rev"
    DegradeBy => "degradeBy"
    Lpf => "lpf"
    Hpf => "hpf"
    Attack => "attack"
    Hold => "hold"
    Release => "release"
    Gain => "gain"
    Pan => "pan"
    Room => "room"
    Every => "every"
    Jux => "jux"
    Instruments => "s"
  }
}

///|
fn Method::parse(name : String) -> Method? {
  Method::all().iter().find_first(candidate => candidate.name() == name)
}

///|
/// A callback inside `jux(…)` and `every(n, …)`.
priv enum Callback {
  Fast
  Slow
  Rev
}

///|
fn Callback::all() -> Array[Callback] {
  [Fast, Slow, Rev]
}

///|
fn Callback::name(self : Callback) -> String {
  match self {
    Fast => "fast"
    Slow => "slow"
    Rev => "rev"
  }
}

///|
/// How the callback is written, for messages that list the callbacks.
fn Callback::written(self : Callback) -> String {
  match self {
    Fast | Slow => "\{self.name()}(N)"
    Rev => "rev"
  }
}

///|
fn Callback::parse(name : String) -> Callback? {
  Callback::all().iter().find_first(callback => callback.name() == name)
}

///|
/// A method after a signal.
priv enum SignalMethod {
  Range
  Fast
  Slow
}

///|
fn SignalMethod::all() -> Array[SignalMethod] {
  [Range, Fast, Slow]
}

///|
fn SignalMethod::name(self : SignalMethod) -> String {
  match self {
    Range => "range"
    Fast => "fast"
    Slow => "slow"
  }
}

///|
fn SignalMethod::parse(name : String) -> SignalMethod? {
  SignalMethod::all().iter().find_first(candidate => candidate.name() == name)
}

///|
/// Whether a `let` binding may not take `name`: `let` and every call that can
/// stand where a binding's name is read.
fn is_reserved_name(name : String) -> Bool {
  name == "let" ||
  StatementCall::parse(name) is Some(_) ||
  PatternCall::parse(name) is Some(_)
}

///|
/// `items` as an English list: `a, b, or c`.
fn or_list(items : Array[String]) -> String {
  match items.length() {
    0 => ""
    1 => items[0]
    2 => "\{items[0]} or \{items[1]}"
    n => items[:n - 1].join(", ") + ", or " + items[n - 1]
  }
}

///|
/// The call at the cursor in the position whose calls `parse` names: an
/// identifier naming one, directly followed by `(`. Consumes the name and
/// the `(` only when it returns a call.
fn[C] Parser::read_call(self : Parser, parse : (String) -> C?) -> C? {
  let start = self.pos
  let name = self.read_ident()
  if parse(name) is Some(call) && !self.at_end() && self.input[self.pos] == '(' {
    self.pos += 1
    Some(call)
  } else {
    self.pos = start
    None
  }
}
