# ADR-0023: The parser owns the score vocabulary

- **Status:** Proposed 2026-11-24.
- **Date:** 2026-11-24
- **Source:** [Amp thread T-01a1f1e8](https://ampcode.com/threads/T-01a1f1e8-a809-7228-bb5b-ef3c2fd0b344)
- **Related:** [ADR-0022 score events carry the sound they play](0022-score-events-carry-their-sound.md)

## Context

A score is written in the mini language. Its names fall into positions, and
each name is valid in one position:

| Position | Names |
|---|---|
| Statement | `bpm(n);`, `song(…)` |
| Pattern | `s(…)`, `note(…)`, `chord(…)`, `stack(…)`, `silence()` |
| Song item | `section(…)`, `part(…)`, `part_id(…)`, `fill(…)`, `bpm(…)` |
| After `song(…)` | `.repeat()` |
| After a pattern | methods such as `.fast(2)`, `.lpf(800, 2)`, `.jux(rev)`, `.s("bass")` |
| Callback | `fast(k)`, `slow(k)`, `rev` inside `jux(…)` and `every(n, …)` |
| Control argument | signals such as `sine`, and their methods `.range`, `.fast`, `.slow` |
| Sound string | drums inside `s("…")`, instruments inside `.s("…")` |

A score also uses syntax that is not a name: `let name = …;`, `$:`, `+`,
parentheses, and commas.

Two programs read a score:

- **The mini parser** (MoonBit, `mini/`) compiles a finished score. It is the
  definition of the language: a name it rejects is not part of it.
- **The editor completion** (TypeScript, `web/live/src/lang/`) suggests what
  to type next. It works on unfinished text, so it reads a Lezer syntax tree
  that recovers from errors, and it answers on every keystroke.

Completion needs two kinds of knowledge about the language: which names
exist in each position, with what they do and the arguments they take, and
which methods may follow a receiver: signals and songs take their own
methods, and `.s` chooses the instrument of notes, so the parser rejects it
on a receiver that plays drums.

The parser matches each name as literal text, in the source, song,
expression, and recognition parsers separately. The names a `let` binding
may not take are another hand-written list, which leaves out `silence` and
`bpm`. The editor lists the methods, callbacks, signals, and top-level forms
by hand, and the lists differ from the parser: `.pan(…)` parses but is not
offered.

## Decision

### 1. Syntax belongs to the grammars; every name belongs to the vocabulary

`let`, `=`, `;`, `$:`, `+`, parentheses, and commas are syntax. The mini
parser and the Lezer grammar each need them to parse at all, so they stay in
both grammars and in the editor's keyword completion. Every other name is in
the vocabulary.

### 2. One closed enum per position, which every parser parses into

`StatementCall`, `PatternCall`, `SongItem`, `ArrangementMethod`, `Method`,
`Callback`, and `SignalMethod` are enums in `mini`; signals are the existing
`MiniShape`, and sounds are `@score.Drum` and `@score.Instrument`. Each enum
has `all()`, the only expression that constructs its cases, so a case missing
from it fails `moon check --deny-warn` as an unused constructor. Its
`name()`, `description()`, and `call()` are exhaustive matches, so a new case
cannot compile without them.

Each parser reads an identifier, parses it into the enum of its position, and
branches over the cases; an unknown name is an error at that point, and the
message that lists the expected names is built from `all()`. Recognition
parses with the same enums and keeps its own recovery. A control method
such as `.gain` or `.pan` is the `Method` case that names its
`@control.Control`.

The names a binding may not take are `let` and the names of the calls that
can stand where a reference is read, the `StatementCall` and `PatternCall`
cases, derived from their `all()`. Song items and methods follow `song(` or
`.`, so a reference never stands where they are read. `bpm` is a case of both `StatementCall` and `SongItem`:
one name in two positions, ending in `;` only as a statement.

### 3. `mini` publishes the vocabulary as data

`@mini.vocabulary()` returns two kinds of entry:

- a **term**, written on its own: a drum, an instrument, or a signal, with a
  description. The instruments give the default, which a note plays without
  `.s`, as its own entry beside the others, so there is exactly one.
- a **call**, written with arguments: a name of any position above, with its
  position, a description, its required arguments, its optional ones, and an
  optional repeated last argument (`stack(pattern, …)`, `song(item, …)`).
  Keeping these apart makes an optional argument before a required one
  unrepresentable.

Each argument has a name and a kind. A kind is what completion offers in
that argument: drum names, instrument names, callbacks, control values
(signals), pattern expressions, or song items. Every other argument offers
nothing, and is a number, such as a tempo or a length, or text, such as a
quoted name or note notation. A snippet needs only to know which arguments
are written in quotes: drums, instruments, and text.

`browser_authoring` sends the vocabulary to the editor as JSON, and the
editor parses it once, when the score tools load.

### 4. `mini` decides which methods may follow a receiver

`@mini.methods_after(receiver)` compiles the receiver, after the `let`
bindings before it, and returns the calls of the methods that may follow
it: for a pattern, every `Method` the compiler accepts after it, so `.s`
only when it is a score of only notes or silence; for an arrangement
(`song(…)`), every `ArrangementMethod`, and none once it repeats. Code that
does not compile has none. The receiver before a `.` is finished syntax even
while the rest of the score is not, so the editor cuts it, and the
bindings, out of the Lezer tree and asks.

A signal is not a receiver here. It is written only in a control argument,
where the parser reads it whatever the bindings are, and its methods do not
depend on it, so they are the calls of their position. The receiver's text
alone could not say which one it is: a binding may be named `sine`.

The compiler is the only place that knows what a receiver is, through
references, `stack`, `+`, and groups, so neither the vocabulary nor the
editor records what a call produces.

### 5. The editor decides by position and kind

The Lezer grammar, highlighting, and the analysis of where the cursor is stay
in TypeScript. Completion maps the cursor's place to the vocabulary and
never names a call itself:

- at the top of the score: earlier bindings, `let`, `$:`, and the statement
  and pattern calls;
- at a pattern elsewhere, such as in a binding, a group, or an argument of
  the pattern kind: earlier bindings and the pattern calls;
- in an argument of any call: the options of the argument's kind, such as
  drum names inside `s("…")` and song items inside `song(…)`. The call that
  owns the argument is found by its name in the position it stands in, and
  the argument by the commas before the cursor;
- after `.` on a signal in a control argument: the calls after a signal;
- after any other `.`: the calls `methods_after` returns.

Snippets fill in the required arguments only, in quotes when they are
written as strings.

## Alternatives considered

- **Keep the vocabulary in TypeScript.** It is copied by hand from the
  parser, and the copies drift, as `.pan` and the reserved names show.
  Rejected.
- **Decide the receiver in TypeScript**, from the syntax tree or from what
  the vocabulary says each call produces. Either restates the compiler's
  rules for references, `stack`, `+`, groups, and drums, needs a guess for
  syntax it does not know, and can disagree with the compiler. Rejected.
- **One enum for every name.** Positions differ: `section` is not a pattern,
  and `bpm` ends with `;` only as a statement. Rejected.
- **Put `let` and `$:` in the vocabulary.** Both grammars must know them to
  parse, so data would only repeat the grammars. Rejected.
- **Parse each call's arguments generically from its argument list.** One
  description would drive both parsing and completion, but a generic reader
  returns a list of argument values of any kind, and each call would then
  destructure that list with cases for the shapes its own list rules out.
  Each call keeps its own parsing branch, which reads its arguments into
  their types, and a test parses every call written as `call()` describes
  it. Rejected.
- **Keep matching literal text, with a test that every vocabulary name
  parses.** A test shows that a listed name parses, not that no unlisted
  name does. Rejected.
- **Complete from the MoonBit parser on unfinished text.** It does not
  recover from errors, and a recovering MoonBit parser would duplicate the
  Lezer grammar. Rejected.
- **Generate the vocabulary into the editor bundle at build time.**
  Completion would start before the score tools load, but `methods_after`
  needs them anyway, so there would be two ways to reach the language.
  Rejected.

## Consequences

- Adding a call, signal, or sound adds its parsing branch, its completion,
  its reserved name, and its recognition; the editor changes only for a new
  kind of argument.
- `let silence = …` and `let bpm = …` become errors.
- Before the score tools load, or if they fail, completion offers only
  earlier bindings, `let`, and `$:`, at the top of the score.
- A snippet leaves out what the grammar adds around a call, such as the `;`
  after a `bpm(…)` statement.
- Each `.` completion compiles the receiver and the bindings before it; they
  are a small part of a score.
- While an earlier binding does not compile, no method is offered after any
  later receiver, even one that does not use it. Skipping unused bindings
  would need the editor to resolve references itself, which Decision 4
  leaves to the compiler.

## Order of work

1. Sounds and `.s`: `@score.Drum::description` and
   `Instrument::description`, `browser_authoring.sound_vocabulary()`, and
   `@mini.takes_instruments`, the instrument rule of Decision 4; the editor
   completes sound names and offers `.s` from them. Done.
2. Parse every position through its enum and derive the reserved names. No
   other behaviour changes, except the two new reserved names. Done.
3. Publish `@mini.vocabulary()` and `@mini.methods_after`, replacing
   `sound_vocabulary()` and `takes_instruments`; the editor completes every
   method after `.` from them. Done.
4. Complete the other positions from the vocabulary in the editor and
   remove its remaining hand-written lists. Done.

## Not covered

The notation inside strings other than sound names: note atoms, chord names
such as `Am` and `G7`, and operators such as `*`, `?`, and `@`.

## Verification

- `moon check --deny-warn` fails when a case is missing from `all()`.
- Every call in the vocabulary parses in its position, with its required
  arguments alone and with its optional ones.
- Every reserved name is rejected after `let`.
- `methods_after` names every method the parser accepts after a pattern of
  notes, the same without `.s` after one with drums, through bindings,
  `stack`, `+`, and groups, `.repeat()` after `song(…)` until it repeats,
  and nothing after a signal or code that does not compile.
- The editor offers each position's calls, drum names inside `s("…")`, song
  items inside `song(…)`, and the methods `methods_after` names.
- The editor starts and edits without the score tools.
