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
  Instrument
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
    Instrument,
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
    Instrument => "s"
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

///|
/// Where a call is written.
pub enum Position {
  Statement
  Pattern
  SongItem
  AfterSong
  AfterPattern
  Callback
  AfterSignal
}

///|
pub impl ToJson for Position with fn to_json(self) {
  let name = match self {
    Statement => "statement"
    Pattern => "pattern"
    SongItem => "song-item"
    AfterSong => "after-song"
    AfterPattern => "after-pattern"
    Callback => "callback"
    AfterSignal => "after-signal"
  }
  Json(name)
}

///|
/// What completion offers in an argument. `Number` and `Text` offer nothing:
/// a number or length, and a quoted name or notation.
pub enum ArgumentKind {
  Drums
  Instruments
  Callback
  Control
  Pattern
  SongItem
  Number
  Text
}

///|
pub impl ToJson for ArgumentKind with fn to_json(self) {
  let name = match self {
    Drums => "drums"
    Instruments => "instruments"
    Callback => "callback"
    Control => "control"
    Pattern => "pattern"
    SongItem => "song-item"
    Number => "number"
    Text => "text"
  }
  Json(name)
}

///|
pub struct Argument {
  name : String
  kind : ArgumentKind
}

///|
pub impl ToJson for Argument with fn to_json(self) {
  { "name": Json(self.name), "kind": ToJson::to_json(self.kind) }
}

///|
/// A name written with arguments: its required arguments, then its optional
/// ones, then any number of `repeated` ones.
pub struct Call {
  name : String
  position : Position
  description : String
  required : Array[Argument]
  optional : Array[Argument]
  repeated : Argument?
}

///|
pub impl ToJson for Call with fn to_json(self) {
  {
    "name": Json(self.name),
    "position": ToJson::to_json(self.position),
    "description": Json(self.description),
    "required": ToJson::to_json(self.required),
    "optional": ToJson::to_json(self.optional),
    "repeated": match self.repeated {
      Some(argument) => ToJson::to_json(argument)
      None => Json::null()
    },
  }
}

///|
/// A name written on its own.
pub struct Term {
  name : String
  description : String
}

///|
pub impl ToJson for Term with fn to_json(self) {
  { "name": Json(self.name), "description": Json(self.description) }
}

///|
/// The instruments; `default` is what a note plays without `.s`.
pub struct Instruments {
  default : Term
  others : Array[Term]
}

///|
pub impl ToJson for Instruments with fn to_json(self) {
  {
    "default": ToJson::to_json(self.default),
    "others": ToJson::to_json(self.others),
  }
}

///|
/// Every name a score writes outside the notation in strings (ADR-0023).
pub struct Vocabulary {
  drums : Array[Term]
  instruments : Instruments
  signals : Array[Term]
  calls : Array[Call]
}

///|
pub impl ToJson for Vocabulary with fn to_json(self) {
  {
    "drums": ToJson::to_json(self.drums),
    "instruments": ToJson::to_json(self.instruments),
    "signals": ToJson::to_json(self.signals),
    "calls": ToJson::to_json(self.calls),
  }
}

///|
pub fn vocabulary() -> Vocabulary {
  let default = @score.Instrument::default()
  let instrument = (instrument : @score.Instrument) => {
    name: instrument.name(),
    description: instrument.description(),
  }
  {
    drums: @score.Drum::all().map(drum => {
      name: drum.name(),
      description: drum.description(),
    }),
    instruments: {
      default: instrument(default),
      others: @score.Instrument::all()
      .filter(other => other != default)
      .map(instrument),
    },
    signals: MiniShape::all().map(shape => {
      name: shape.name(),
      description: shape.description(),
    }),
    calls: [
      ..StatementCall::all().map(StatementCall::call),
      ..PatternCall::all().map(PatternCall::call),
      ..SongItem::all().map(SongItem::call),
      ..ArrangementMethod::all().map(ArrangementMethod::call),
      ..Method::all().map(Method::call),
      ..Callback::all().map(Callback::call),
      ..SignalMethod::all().map(SignalMethod::call),
    ],
  }
}

///|
fn argument(name : String, kind : ArgumentKind) -> Argument {
  { name, kind, }
}

///|
/// What a call does and the arguments it takes.
priv struct Signature {
  description : String
  required : Array[Argument]
  optional : Array[Argument]
  repeated : Argument?
}

///|
fn signature(
  description : String,
  required~ : Array[Argument] = [],
  optional~ : Array[Argument] = [],
  repeated? : Argument,
) -> Signature {
  { description, required, optional, repeated, }
}

///|
fn Signature::call(
  self : Signature,
  name : String,
  position : Position,
) -> Call {
  {
    name,
    position,
    description: self.description,
    required: self.required,
    optional: self.optional,
    repeated: self.repeated,
  }
}

///|
fn StatementCall::call(self : StatementCall) -> Call {
  self.signature().call(self.name(), Statement)
}

///|
fn StatementCall::signature(self : StatementCall) -> Signature {
  match self {
    Bpm =>
      signature("beats per minute, 4 beats per cycle; default 120", required=[
        argument("tempo", Number),
      ])
    Song =>
      signature(
        "finite arrangement",
        required=[argument("item", SongItem)],
        repeated=argument("item", SongItem),
      )
  }
}

///|
fn PatternCall::call(self : PatternCall) -> Call {
  self.signature().call(self.name(), Pattern)
}

///|
fn PatternCall::signature(self : PatternCall) -> Signature {
  match self {
    Literal(Sound) =>
      signature("drum sounds", required=[argument("drums", Drums)])
    Literal(Note) =>
      signature("MIDI numbers or note names", required=[argument("notes", Text)])
    Literal(Chord) =>
      signature("chord names", required=[argument("chords", Text)])
    Silence => signature("silent pattern")
    Stack =>
      signature(
        "combine layers",
        required=[argument("pattern", Pattern)],
        repeated=argument("pattern", Pattern),
      )
  }
}

///|
fn SongItem::call(self : SongItem) -> Call {
  self.signature().call(self.name(), SongItem)
}

///|
fn SongItem::signature(self : SongItem) -> Signature {
  match self {
    Bpm =>
      signature("the song's beats per minute", required=[
        argument("tempo", Number),
      ])
    Section =>
      signature("a named pattern that plays for a length in cycles", required=[
        argument("name", Text),
        argument("length", Number),
        argument("pattern", Pattern),
      ])
    Part =>
      signature(
        "play a section, after the previous part or from a start",
        required=[argument("name", Text), argument("section", Text)],
        optional=[argument("start", Number)],
      )
    PartId =>
      signature(
        "a part with a stable occurrence id",
        required=[
          argument("id", Text),
          argument("name", Text),
          argument("section", Text),
        ],
        optional=[argument("start", Number)],
      )
    Fill =>
      signature("play a section in the gaps between parts", required=[
        argument("prefix", Text),
        argument("section", Text),
      ])
  }
}

///|
fn ArrangementMethod::call(self : ArrangementMethod) -> Call {
  self.signature().call(self.name(), AfterSong)
}

///|
fn ArrangementMethod::signature(self : ArrangementMethod) -> Signature {
  match self {
    Repeat => signature("repeat an arranged song")
  }
}

///|
fn Method::call(self : Method) -> Call {
  self.signature().call(self.name(), AfterPattern)
}

///|
fn Method::signature(self : Method) -> Signature {
  let control = (description : String) => {
    signature(description, required=[argument("value", Control)])
  }
  let filter = (description : String) => {
    signature(description, required=[argument("cutoff", Control)], optional=[
      argument("resonance", Control),
    ])
  }
  match self {
    Fast => signature("n× faster", required=[argument("factor", Number)])
    Slow => signature("n× slower", required=[argument("factor", Number)])
    Gate =>
      signature("audible fraction of each step (0–1)", required=[
        argument("fraction", Number),
      ])
    Rev => signature("reverse")
    DegradeBy =>
      signature("drop with probability p (0–1)", required=[
        argument("p", Number),
      ])
    Lpf => filter("low-pass cutoff and optional resonance (Q)")
    Hpf => filter("high-pass cutoff and optional resonance (Q)")
    Attack => control("note fade-in, seconds")
    Hold => control("hold after attack, seconds")
    Release => control("note fade-out, seconds")
    Gain => control("voice level")
    Pan => control("stereo position (0 left, 1 right)")
    Room => control("send to shared room (0–1)")
    Every =>
      signature("apply f every nth cycle", required=[
        argument("n", Number),
        argument("f", Callback),
      ])
    Jux =>
      signature("split stereo, apply f to right", required=[
        argument("f", Callback),
      ])
    Instrument =>
      signature("play notes on an instrument", required=[
        argument("instruments", Instruments),
      ])
  }
}

///|
fn Callback::call(self : Callback) -> Call {
  self.signature().call(self.name(), Callback)
}

///|
fn Callback::signature(self : Callback) -> Signature {
  match self {
    Fast => signature("k× faster", required=[argument("k", Number)])
    Slow => signature("k× slower", required=[argument("k", Number)])
    Rev => signature("reverse")
  }
}

///|
fn SignalMethod::call(self : SignalMethod) -> Call {
  self.signature().call(self.name(), AfterSignal)
}

///|
fn SignalMethod::signature(self : SignalMethod) -> Signature {
  match self {
    Range =>
      signature("map 0–1 onto low–high", required=[
        argument("low", Number),
        argument("high", Number),
      ])
    Fast => signature("n× faster", required=[argument("factor", Number)])
    Slow => signature("n× slower", required=[argument("factor", Number)])
  }
}
