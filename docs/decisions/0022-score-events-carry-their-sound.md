# ADR-0022: Score events carry the sound they play

- **Status:** Proposed 2026-11-23.
- **Date:** 2026-11-23
- **Source:** [Amp thread T-01a1f1e8](https://ampcode.com/threads/T-01a1f1e8-a809-7228-bb5b-ef3c2fd0b344)
- **Amends:** [ADR-0020](0020-controls-as-signals.md) Decision 1: `Sound` is
  no longer a control, and `Note` is a voice parameter the scheduler sets.
  Reverses the specialization of the pattern document layer to `ControlMap`
  recorded in [ADR-0021](0021-song-structure-generic-over-content.md) and
  made by commit `855cc50`.
- **Related:** [ADR-0018 playback visualization follows event origins](0018-playback-visualization-origin-truth.md),
  [ADR-0019 automatic control buses](0019-automatic-control-buses.md),
  [mini notation](../mini-notation.md)

## Context

A score names two kinds of sound:

- **drums**, hits without a pitch: `s("bd sd")`;
- **instruments**, which play pitches: `note("C2 G2").s("bass")`. A note
  without `.s` plays the default instrument.

Both are closed sets fixed by the score language, and the host plays each
drum and each instrument with its own voice pool.

Every event also carries **controls** such as `gain`, `lpf`, and `pan`:
numbers that may change while a note sounds and reach the voice through
buses (ADR-0019, ADR-0020).

Which sound an event plays is a different kind of information. It is one
choice from a closed set, every event has exactly one, and it is fixed when
the event starts. Today it is stored among the controls: `Control::Sound`
holds a drum's MIDI number, `Control::Note` a pitch, and the host routes
with `ControlEquals(Sound, 36.0)`. The `ControlMap` type therefore allows
states no score means: both keys or neither, a sound of `37.5`, a sound
that follows a bus. Choosing an instrument would add a third numeric key,
and "no instrument key" would have to mean the default. ADR-0020 lists
`Note` and `Sound` because Mini emitted them; it gives no reason for them to
be controls, and nothing reads `Sound` except routing.

A score's document holds three kinds of pattern, which are combined:

- **events**, built by `s(…)`, `note(…)`, and `chord(…)`;
- **controls**, the right side of `.gain("0.3 0.6")` or `.lpf(sine…)`, which
  set values but sound nothing;
- **instruments**, the right side of `.s("bass pad")`.

While all three were `ControlMap`, one payload type served them, and commit
`855cc50` removed the document layer's type parameter because "lowering,
buses, and origins only ever worked for ControlMap events". Once the sound
is not a control, that premise no longer holds: a document of events cannot
also be a document of controls without an event type that may lack a sound.

## Decision

### 1. The event says which sound it plays

```moonbit
pub(all) enum Sound {
  Hit(Drum)
  Note(Instrument, pitch~ : Double)
}

pub(all) struct ScoreEvent {
  sound : Sound
  controls : ControlMap
}
```

`Drum` and `Instrument` are closed enums. Each constructor is built only in
its `all()`, so one missing from the list fails `moon check --deny-warn`
with `unused_constructor`. They live in a `score` package below `pattern`'s
users (`mini`, `song`, `scheduler`), which name events without depending on
the parser.

`Control::Sound` is removed. `Control::Note` stays as a parameter the engine
applies, like `Decay` and `Sustain`: Mini never writes it, and the scheduler
gives a note's pitch to its voice as `Note` at note-on, so voice bindings
(`key=Note, unit=MidiToHz`) are unchanged.

### 2. The document layer is generic over its payload again

`PatternDoc[A]`, its snapshots, `EventWithOrigin[A]`, and the lowering cache
take the payload type again; `Pat[A]` never lost it. Controls stay
`ControlMap` documents. Operations that touch an event's controls require
`A : WithControls`, a trait that reads and replaces the `ControlMap` inside
the payload; `ControlMap` and `ScoreEvent` implement it. Lowering itself has
no bound, so a document whose payload has no controls, such as instruments,
lowers as it is.

- `merge_control(left : PatternDoc[A], right : PatternDoc[ControlMap])`
  merges controls into events of any `A : WithControls`. The right side stays
  a nested document, so its structure gives the buses (ADR-0019).
- `merge_values(left : PatternDoc[A], right : PatternDoc[B], apply)` lowers
  the right side once and gives each left event the value at its onset. It
  derives no bus: an instrument cannot change during a note.
- `jux` and `filter_map` see a payload's controls through `WithControls`.
  They are the only nodes whose lowering reads or writes controls, so each
  keeps the trait's two methods, captured when it is built.

Events of a merge record the merge, its left side, and the right side's
nodes in their source path (ADR-0018), so an edit to a provider reaches the
voices it reached.

### 3. A note has its instrument from the start

`note("C4")` builds `Note(Instrument::default(), pitch=60.0)` in its atom;
`.s("bass pad")` is a `merge_values` that replaces each note's instrument
with the one at its step. The default is not added by a merge, which would
give the tones of `chord("C")` one shared source path.

### 4. `.s` applies to notes only

Compiling a score expression gives `Silent`, `Hits`, `Notes`, or `Mixed`.
Only `Notes` holds a `NoteDoc`, and only a `NoteDoc` takes instruments, so
`s("bd").s("bass")` and `stack(s("bd"), note("C4")).s("bass")` are errors at
`.s`'s argument. `s("…")` accepts drum names and `.s("…")` instrument names.

### 5. The scheduler routes by the sound's type

The host gives the scheduler one pool per drum and per instrument; the
scheduler finds an event's pool by matching its `Sound`, with no selector
list. `InstrumentSelector` is removed.

### 6. Songs hold score events

`SongContent` gives `Pat[ScoreEvent]`, and every song type that names the
payload names `ScoreEvent`.

### 7. Mini parses from the text alone

`parse_doc`, `parse_play_source`, `PlaybackInput::compile`, and
`MiniDocBuilder` take no previous document. Reusing a subtree of the last
document needs it at its own type, and a control provider is a
`PatternDoc[ControlMap]` nested inside a `PatternDoc[ScoreEvent]`, so it
cannot be taken out of the previous document as one. Reuse also never ran
while the parser records source positions, which is how the editor parses.
Node IDs stay deterministic, so a reparse gives unchanged subtrees the same
IDs.

## Why reverse `855cc50`

`855cc50` was right for the model it served: every pattern was a
`ControlMap`, so the parameter had one instance and its merge closures were
cost without use. This ADR changes that model, and the alternatives that
keep a single payload type are worse:

- **A document of `ScoreEvent` only.** Control and instrument patterns have
  no sound, so they need `Sound?`, which puts a soundless event in the type
  and a default or an error path at every reader.
- **A payload that is a sum of event, controls, or instrument.** Merging an
  event pattern into a control pattern type-checks, and every operation
  needs a branch for the mixes no score writes.
- **Separate non-generic types (`ScoreDoc`, `ControlDoc`, `InstrumentDoc`).**
  The same generic machinery under three names, and `pattern` would have to
  know about sounds.

`855cc50` also replaced merge closures stored in nodes with fixed `ControlMap`
operations. That part is kept: a node holds no merge of its own. The two
nodes that touch controls keep the methods of the payload's `WithControls`,
which every node of that payload shares.

## Alternatives considered

- **Keep the sound as controls** and add an instrument key. Smallest change;
  keeps the meaningless states above, makes the default instrument the
  absence of a key, and makes routing depend on selector order. Rejected.
- **Decode a `Sound` from `ControlMap` once at the host.** The decoder needs
  an error path for maps the parser never produces, and the type guarantees
  stop at that boundary. Rejected.
- **One pattern per pool**, so events need not name their sound. Repeats the
  score's structure and its query once per pool, and random transforms such
  as `degradeBy` must agree across the copies. Rejected.
- **Give notes a payload of their own** (`NoteEvent`), so a document that
  `.s` applies to cannot hold a hit. `played_on`, the `apply` of `.s`'s
  `merge_values`, would then have no case for a hit; today it leaves one as
  it is, a case the compiler never reaches because only a `NoteDoc` takes
  instruments, and it cannot abort, because pattern queries run on the
  audio thread. Notes would have to become `ScoreEvent` wherever they join
  drums and at the root of a body or section, through a document node that
  holds a `PatternDoc[NoteEvent]` inside a `PatternDoc[ScoreEvent]`. MoonBit
  has no existential types and no trait methods with type parameters, so
  that node cannot lower its nested document generically over the origin
  type: it would need one closure per origin type and a selector passed
  through every lowering call. The nested document would also fall outside
  the lowering cache, which is typed by payload, so a score of only notes
  would be lowered from scratch on every edit unless a second cache were
  added. The guarantee belongs to the score language, which already gives
  it as the type `NoteDoc`; carrying it into the generic document layer
  would cost more than the one unreachable case it removes. Rejected while
  the language lacks existential types.
- **Remove `Note` from `Control` too.** Then voice bindings need a second key
  type for parameters the engine applies, which also covers `Decay` and
  `Sustain`. Deferred; `Note` in a `ControlMap` is unreachable from Mini.

## Consequences

- Breaking for `pattern`, `song`, `scheduler`, `mini`, and the browser host's
  MoonBit APIs. The browser's JS ABI is unaffected. No compatibility layer.
- `Pat::jux`, `PatternDoc::jux`, and `select_control` work on any
  `A : WithControls`.
- Controls and buses (ADR-0019, ADR-0020) are unchanged.
- An atom's content signature names its sound (`hit:bd`,
  `note:triangle:60`) instead of a control (`control:sound:36`). Random drops
  are seeded by content, so `degradeBy` over a document whose content changed
  drops different events; nothing else in the output changes.
- The render path stays free of allocation: routing is a `match`.

## Order of work

1. `score` package; `pattern` generic over `A : WithControls` where controls
   are touched; `song` and `scheduler` over `ScoreEvent`; Mini emits
   `ScoreEvent` and parses from the text alone; the host routes by `Sound`.
   Browser output stays identical except the random drops above.
2. `.s`: `merge_values`, `NoteDoc`, and instrument pools in the host.

## Verification

- `merge_control` into a `ScoreEvent` document, with its bus following the
  provider; `merge_values` taking the value at each onset.
- `note("C4")` plays the default instrument; `.s("bass pad")` chooses per
  step; `s("bass")` and `s("bd").s("bass")` are errors with positions; the
  tones of `chord("C")` keep separate paths. Under `.s`, as under `.gain`,
  they share the merge's path.
- Browser output of the example scores is sample-identical after step 1,
  except where `degradeBy` draws from a changed content signature.
- The CLAP allocation audit stays at zero.
