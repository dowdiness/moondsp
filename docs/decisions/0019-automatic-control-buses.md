# ADR-0019: Parameter automation through automatic control buses

- **Status:** Accepted 2026-10-26. Pattern lowering derives buses, and `PatternScheduler` makes sounding voices follow them. Mini control arguments accept quoted steps and signals (`sine`, `saw`, … with `.range`, `.slow`, `.fast`), so browser scores produce time-varying buses. The CLAP prototype plays host MIDI notes and applies host parameter changes to sounding voices directly; it plays no score, so no buses reach it.
- **Date:** 2026-10-26
- **Source:** "moondsp パラメータ・オートメーション設計" (Koji Ishimoto, 2026-10-23; not in the repository) and its review in [Amp thread T-01a1714e](https://ampcode.com/threads/T-01a1714e-2aed-7167-9b7d-63c73f2b4396)
- **Related:** [ADR-0007 ControlMap accessor surface](0007-control-map-accessor-surface.md), [ADR-0018 playback visualization](0018-playback-visualization-origin-truth.md), [Domain glossary](../../CONTEXT.md), [technical reference](../technical-reference.md)
- **Evidence:** Prototype commits on top of `6703c7f`: `b10b26d` (the `part.begin` rule), `8f5caeb` (the `Continuous` node), `73f08cb` (bus lowering, signals, derivation tests, benchmark), and `9f4949f` (held-voice playback test). See [Evidence](#evidence). The prototype covers the pattern layer and a test-local playback driver, not `PatternScheduler`, the browser host, or CLAP.

## Context

A score must be able to change parameters over musical time: per-onset values
(`s("hh*8").gain("0.3 0.6")`), continuous changes on a held note (a filter
sweep on a pad), and fades of a whole passage, written the same way for every
instrument.

Today a control is applied once, at note-on. The scheduler builds a fresh
`Map` per event, `ControlMapper` turns `pan` and `room` into special voice
actions, and only the synth graph binds `gain`, so `.gain` has no effect on
drums. Nothing reaches a voice while it sounds.

The source design proposed delivering values to sounding voices through the
scheduler's per-block query: each block returns fragments of already-sounding
events, and the scheduler matches each fragment back to its voice by
`(origin, whole.begin)` and sends changed values. Checking that design against
the code found three problems that come from the fragment model itself:

1. **Values depended on the query length.** `merge_control_kernel` merged
   every right-hand event that overlapped the queried part, keeping the last.
   One onset received `gain` 0.3 from a 1/8-cycle query and 0.6 from a
   1-cycle query.
2. **Fragments cannot be matched to voices.** `MergeControl`, `Jux`, and
   `Every` give all their events one shared path (the reachable-descendant set
   from `pattern_source_path_for_opaque_children`). `chord("Dm9").gain(0.5)`
   yields five events with the same `(path, whole.begin)`;
   `note("60").jux(rev)` yields two that differ only in `pan`. Song origins
   carry only occurrence, section, and layer. Order inside a collision group
   was stable, but the scheduler sorts with the unstable `Array::sort_by`.
3. **Release tails receive nothing.** A query stops returning an event once
   its span ends, so a voice in release cannot follow a fade.

Each sounding voice needs only two things: which time function it follows,
which is fixed by the expression structure at note-on, and the current time.
Tidal control busses and SuperCollider's `Synth.map` / `Bus.asMap` solve the
same problem this way, but with buses numbered by hand.

## Decision

### 1. Voice contract: each parameter reads a constant or one bus

A voice parameter is either a constant set at note-on or bound to exactly one
bus. The voice never sees patterns, fragments, or event identity. This is the
durable extension point: other bus writers (graph-internal modulators, MIDI
CC, CLAP host automation) can be added later without changing voices.

### 2. Lowering derives buses automatically

Lowering a `PatternDoc` creates one bus per `MergeControl` occurrence and
control key, expressed in root time. Each emitted event records which bus
each bound key reads; the outermost `MergeControl` for a key wins, matching
`ControlMap::merge`. Voices that share a bus, such as the five tones of a
chord, receive the same value, so the scheduler never needs to tell them
apart. The time mapping from a node to the root follows one rule per
combinator kind:

| Combinator kind | Bus derivation |
| --- | --- |
| Time maps: `fast`, `slow`, `rev`, `euclid`, `every`, nesting | Apply the same transform to the bus |
| Time partition: `sequence`, weighted sequence | The child's slot carries the bus; other slots are silent |
| Simultaneous branches: `stack` | Unchanged |
| Branches with different transforms: `jux` | One bus per branch |
| Event selection: `degradeBy`, `gate`, `filter_map`, routing `select_control` | Unchanged; only voices are dropped. A `filter_map` that replaces an event's value unbinds that event |

Routing must select voices, not buses: the bus table is built once from the
unfiltered score and shared by every instrument pool.

### 3. The signal form defines control semantics

A bus is compiled to a signal: a tree of time maps evaluated at one exact
time. Time stays an `Int64` fraction, so no floating-point rounding decides a
slot. Evaluation at `t` stands for `[t, t + ε)`; `rev` mirrors this into a
limit from the left, so a sample on a slot boundary belongs to the slot
before it.

The query form (`Pat[ControlMap]` over an arc) is not the definition. For
continuous values it is not well defined: under `rev` it depends on the block
length, and inside `sequence` each child is read at its slot start.

### 4. Onset values are sampled at `part.begin`

`merge_control_kernel` merges only right-hand events whose part contains the
left fragment's `part.begin`, so an onset's values no longer depend on the
query length. This rule agrees with the signal at onsets.

### 5. Signals come from a closed set of control nodes

A control provider compiles to a signal only from: constants, `Continuous`
nodes, the time maps and partitions in the table above, `stack`, and nested
`MergeControl`. Continuous controls (ramps, LFOs) are a `PatternDoc` node that
carries both its query form and an allocation-free `(Double) -> Double`. An
opaque `Runtime`/`Atom` pattern is accepted only when it folds to the same
pure value in every cycle. Event selection inside a control provider
(`degradeBy`, `gate`, `filter_map`, `jux` on the right-hand side) is a
compile error; Mini rejects `?` inside a quoted control pattern while parsing.
A nested `MergeControl` overrides wherever its left side has an event, even
one that does not set the key.

### 6. The voice pool follows buses once per block

At note-on the scheduler starts the voice with the event's values and, in the
same call, hands the pool a reader for each time-varying bound key
(`note_on_controls(controls, follow=...)`). The follower belongs to the voice
slot: reusing the slot (including a steal) clears it, and an idle slot is
skipped. Once per block the scheduler calls `update_follows` at the block's
start time; each follower reads its bus and applies a value only when it
changed. A shared bus is evaluated once per follower rather than once per
table, because each placement is its own function and one evaluation costs
about 41 ns. Reading and applying allocate nothing on the audio thread.

Each event carries its buses already placed on the clock the event is on
(`EventBuses`): Song placement and song repetition move a bus exactly as they
move the event's spans. A voice that starts inside a block begins from its own
onset value. A constant bus gets no follower.

### 7. Smoothing belongs to DSP nodes

Values arrive once per block, so the scheduler cannot smooth them per sample.
Each DSP node defines how it responds to a changed value, for example a
filter smoothing its cutoff and an envelope reading a stage time when that
stage starts. Smoothing applies only to updates while sounding; a note-on
starts from its own value so accents stay sharp.

### 8. Common voice surface, nesting rules, and time units

`gain`, `pan`, and `send` live in the voice frame for every instrument and are
bus-capable parameters; the mix order is gain → pan → (dry, send), so a fade
also lowers the reverb send. Graph-specific parameters (cutoff and so on) use
graph bindings. `ControlMapper`'s special cases for `pan` and `room`, and the
synth-only `gain` binding at graph node 5, are removed.

Nested occurrences of one key combine by one rule per key: `gain`
multiplies; every other key takes the outermost value, as `ControlMap::merge`
does today. Pattern values are in cycles; envelope times are in seconds.

### 9. Voice lifetime, edits, and note-relative modulation

- **Release tails.** A voice keeps reading its bus until it becomes idle, so
  a note released during a fade keeps fading.
- **Score edits.** When a new snapshot replaces a material, sounding voices
  keep reading the bus table of the snapshot that started them; new onsets
  use the new table. An edit that releases voices does not stop their
  followers: a released voice keeps following until it is idle, like any
  release. A killed voice is idle at once.
- **Note-relative modulation.** A modulation that restarts at each onset
  cannot be one shared root-time bus. It is reserved as a later extension in
  which a voice reads its bus at `t − onset`, and is not built now.

## Evidence

All numbers are from the prototype in this orb (moon 0.1.20261023, Node
26.12.1). The cached `moonbitlang/quickcheck` 0.14.0 was patched locally
because this toolchain rejects it; the repository was not changed for that.

- **Derivation.** Sixteen scores, each played in blocks of 1/64, 1/7, and
  3/5 cycles. At every onset of a bound voice, the pattern's own value, the
  queried bus, and the compiled signal were compared. The scores cover
  `slow`, `fast`, `rev`, `euclid`, `every`, `degradeBy`, `jux`, `sequence`,
  weighted sequence, `stack`, nesting, `chord(...).slow(2).jux(rev)`, and mini
  `.gain(0.5)`. With discrete controls, all three values agreed in every case.
  With a continuous ramp, the queried bus always matched the pattern, and the
  signal differed only under `rev` and `sequence`, where the query form is
  undefined (Decision 3). Exact-value tests pin the signal there.
- **Mutation checks.** Removing `slow` from the derivation broke 27/28
  checks, using one bus for `jux` broke 27/56, and dropping the `sequence`
  slot broke 15/16. Removing the left-limit flip in `rev` broke 2 boundary
  checks in the discrete `every`/`rev`/`jux` score. Reverting the `part.begin`
  rule fails its regression test (`Some(0.6) != Some(0.3)`).
- **Playback.** A real `BoundVoicePool` (saw → lowpass → ADSR, 48 kHz,
  128-frame blocks) held one note for two cycles under `slow(2)` while `lpf`
  swept from 200 Hz to 2100 Hz. There was one note-on and 749 parameter
  sends, with no silent block. Brightness tracked a voice fixed at the current
  cutoff to within 1–5% (for example 27.27 against 27.47 at 1.99 s, compared
  with 5.53 without the bus). The largest block-boundary step (0.192) was
  below the largest step inside a block (0.325).
- **Allocation.** Using the counting method of
  [the 2026-10-23 browser record](../performance/2026-10-23-browser-updates.md),
  a release wasm-gc build ran 1,000 blocks after 200 warmup blocks. The
  export package and Node driver were temporary and are not committed; the
  score was `chord("Dm9")` under a stacked `lpf` sweep and `every`/`rev`
  steps, `slow(4)`, with five held voices:

  | Path | Executed GC constructions |
  | --- | ---: |
  | Compiled bus signals (`evaluate_all`) | 0 |
  | Whole playback step: evaluate, send to 5 voices, render | 0 |
  | Query-form bus evaluation (positive control) | 165,051 |

  Instrumented and uninstrumented outputs matched.
- **Cost.** Compiled evaluation took about 41 ns per block, compared with
  about 1.1 µs for the query form and about 13 µs for the existing block
  query of the same score. These are native benchmark numbers, not
  AudioWorklet timings.

- **Scheduler.** The same held note played through `PatternScheduler`
  produced the same brightness numbers as the prototype driver; disabling the
  per-block update made it match the unswept voice. A Song test pins bus
  placement under an occurrence start and a `TimeScope` rate, and fails
  (`lpf 25 40` against `lpf 50 80`) when the rate is dropped. Browser output
  for five scores with constant controls (drums, `jux`, envelopes and `room`,
  a Song, a `Dm9` chord) was bit-identical to the previous commit over 400
  blocks each. In a release wasm-gc build holding a five-voice chord under an
  `lpf` sweep, the sweep and an unchanging control executed the same number of
  GC constructions (520,990 per 1,000 blocks, all in the existing event query),
  and running the bus update ten times per block did not change it. After
  followers moved into voice slots, the same audit with a stacked `lpf` sweep
  and `gain` fade was again unchanged by running `update_follows` ten times
  per block, and browser output stayed bit-identical for six scores. A voice
  test pins that a releasing voice keeps following and that a voice stealing
  its slot starts without the old follower; each check fails when its rule is
  removed.

Not covered: score playback in CLAP, which would need the event query off
the audio thread or allocation-free, since CLAP's audio callback must not
allocate; weighted sequences in the allocation audit; onset-path allocation, which still
runs the event query and builds each follower closure (an existing problem outside this
ADR); user `Continuous` functions, which must themselves be allocation-free.

## Alternatives considered

| Alternative | Why not chosen |
| --- | --- |
| Match query fragments to voices (source design) | Has the three problems in Context |
| Give each event its own identity path | Fixes matching, but query-length dependence and release tails remain |
| Let each voice query the score | Query count grows with voice count; buses share one evaluation by structure |
| Apply automation on part buses only | Works for linear gain and pan, but not for per-voice parameters such as cutoff |
| Graph-internal modulators compiled from patterns | Sample-accurate, but needs a pattern-to-DSP compiler; remains possible later as another bus writer |
| A new signal value type in `ControlMap` | Adds a payload type; buses keep `ControlMap` numeric and move time dependence into lowering |

## Consequences

- Removed: `ControlMapper`'s `pan`/`room` cases, the drum/synth `gain`
  asymmetry, fragment-to-voice matching, and the admission assumption that
  control right-hand sides are scalars. Admission must bound the bus count
  instead.
- New constraint: controls outside the closed set fail at compile time
  with `PatternDocError::UnsupportedControl` instead of silently freezing.
  An opaque `Runtime` provider is outside the set, so control atoms carry
  their value, including Mini controls without a source atom.
- New constraint: every new combinator must state its bus rule; the
  derivation test fails until it does.
- `PatternDocNode` gains a `Continuous` variant.
- Lowering is single. `compile_pattern_node` keeps each subtree's buses in
  that subtree's local time beside its pattern, and each enclosing node wraps
  them with its own transform, so the lowering cache shares them unchanged.
  Events hold subtree-local bus indices that a parent renumbers. The table
  and its indices stay private: each event exposes only `buses()`
  (`EventBuses`), whose `reader(key)` reads one bus on the event's clock.
- Unifying the per-instrument schedulers was close to a prerequisite,
  because the bus table must come from the unfiltered score. Done: one
  `PatternScheduler` now plays every instrument pool and routes each event by
  `InstrumentSelector`, so the score reaches it unfiltered.
- A pool's bindings are the single place that interprets a key: each binding
  targets a graph parameter or a voice-frame parameter (`bind_voice`) and
  carries the unit that converts score values (`MidiToHz`, `SecondsToMs`).
  `ControlMapper` and the scheduler's `gain`/`pan`/`room` switch are removed;
  a host binds the voice-frame keys it uses on every instrument.
- Control keys stay strings (ADR-0007). A typed key enum would make the
  per-key nesting rule explicit and is a separate decision.

## Non-goals

- Sample-accurate automation.
- Part buses and nonlinear part effects such as compressors.
- Song structure as expressions: `fadeIn`/`fadeOut`, finite-length
  expressions, and the edit-switching unit. These need their own ADR; this
  ADR provides only the `gain` automation they would build on.
- Backward compatibility: replaced paths are removed, with no fallback.

## Revisit when

- A required modulation cannot be expressed in the closed signal set.
- A real host or AudioWorklet measurement shows bus evaluation is not
  negligible.
- Note-relative modulation (Decision 9) is needed.
