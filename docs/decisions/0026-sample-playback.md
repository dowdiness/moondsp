# ADR-0026: Scores play recorded samples

- **Status:** Accepted 2026-11-24. Stages 3 and 4 are implemented.
- **Date:** 2026-11-24
- **Source:** [Amp thread T-01a20be3](https://ampcode.com/threads/T-01a20be3-8157-751b-b637-37a8a4bda36b)
- **Related:** [ADR-0019 automatic control buses](0019-automatic-control-buses.md),
  [ADR-0022 score events carry the sound they play](0022-score-events-carry-their-sound.md),
  [ADR-0023 the parser owns the score vocabulary](0023-the-parser-owns-the-score-vocabulary.md),
  [copy measurement](../performance/2026-11-24-sample-copy.md)

## Context

A score can play only synthesized sound. We want it to play recorded audio
such as piano, field recordings, and voice, in three ways:

- one-shot, as in `s("rain")`;
- pitched, as in `note("C4 E4").s("piano")`;
- sliced or re-triggered, with slice points from numbers, patterns, or signals.

The musical target is chopped, re-triggered material, so slicing from
patterned and signal values matters as much as plain playback. Sample voices
should reuse the existing filters, envelope, gain, pan, room, and control
automation.

The engine at commit 3405321:

- `Sound` is `Hit(Drum) | Note(Instrument, pitch~)`. `Drum` and `Instrument`
  are closed enums, and only their `all()` constructs them (`score/sound.mbt`).
  `s("…")` names drums and `.s("…")` names instruments. `.s` applies to notes
  only (ADR-0022 Decision 4). The parser parses from the text alone
  (ADR-0022 Decision 7) and owns the vocabulary (ADR-0023).
- `init_scheduler_graph_with_sounds` builds one voice pool per drum and per
  instrument, and `route` maps a `Sound` to its pool
  (`browser/internal/playback_host/playback_host.mbt:177-205`).
- No graph node reads recorded audio. `DspNodeKind` has 18 kinds
  (`graph/graph_node.mbt:11-30`). Node state is private to `CompiledGraph`
  (`graph/internal/runtime/graph_compile.mbt:8`). `Dsp::compile` takes only the
  template and a `DspContext`.
- A note-on applies an `Array[GraphControl]`: gate changes and
  `set_param(node, slot, Double)` (`voice/voice.mbt:996-1030`). The pitch
  reaches the voice as the `Note` control, which `NoteOnControls` reads from
  the `Sound` and not from the event's controls (`scheduler/scheduler.mbt:9-22`).
- A voice follows every varying bound control once per block while it sounds,
  release included (`voice/voice.mbt:185-222`, `scheduler/scheduler.mbt:339-343`).
  No control is read at onset only. The per-control rules are
  `Control::nesting` and `Control::admits` (`control/control.mbt:123-160`).
- A reused voice slot is cleared by `reset_runtime_state` or by a fresh compile
  (`voice/voice.mbt:996-1030`).
- The browser target is wasm-gc. `AudioBuffer` wraps `FixedArray[Double]`
  (`dsp/buffer.mbt`), and JS cannot write a wasm-gc array, so data crosses
  one value per export call. Score text already crosses that way
  (`push_playback_char`).
- `SourceProblem` (`mini/source_problem.mbt`) is the parser's verdict on a
  text: `Mistake`, `OverLimit(SourceLimit)`, or `Internal`.

## Decision

### 1. A voice learns its sample from a numeric control set at note-on

A new `@control.Control` case, provisionally `SampleNumber`, carries the
store index as a `Double`. The case works like `Note`: `NoteOnControls` reads
it from the `Sound` and never from the event's controls, so a score cannot
set it. Like `Note`, it has no `Method` case (ADR-0023 Decision 2), so no
method such as `.sample_number(…)` exists, and the vocabulary does not offer
it. It is fixed at onset (Decision 4): changing it while a voice sounds
would jump to another waveform. The sampler template binds it to a
`SamplePlayer` slot. Note-on keeps its current shape.

Setting the slot looks the sample up in the store, which is an index into a
fixed table and allocates nothing. The node keeps the waveform reference and
its read position as voice state.

Rejected: widening note-on to carry a buffer. Every pool, binding, and the
CLAP fixed-argument note-on would change for one kind of voice.

### 2. `DspContext` carries the sample store

`DspContext` gains a store reference that defaults to an empty store, so the
roughly 30 compile call sites and every test stay unchanged. A
`SamplePlayer` takes the reference at compile. The store type lives in `dsp`,
next to `DspContext`, and does not depend on any host.

Seven non-test library sites construct a `DspContext`. Three of them rebuild
a context from a sample rate and block size, and those rebuilds would silently
drop the store:

- `scheduler/scheduler.mbt:72` builds the per-frame-count render contexts;
- `clap_engine/clap_engine.mbt:341` does the same;
- `graph/internal/staging/graph_topology_controller.mbt:195` builds the
  context for a recompile.

Render contexts do not matter, because the node reads the store at compile.
The topology controller recompiles, so it must keep its original context,
for example through `DspContext::with_block_size`, instead of rebuilding one.

Rejected:

- An extra compile argument, which changes about 30 sites.
- A global store, which shares state between tests and between engines.

### 3. `Sound` gains `Play(Sample, pitch~ : Double)`

`@score.Sample` is a closed enum like `Drum` and `Instrument`, and its `all()`
is the only expression that constructs it. Sample names join both sound
strings, and each keeps what it already accepts (ADR-0022 Decision 4):

- `s("…")` accepts drums and samples. `s("rain")` plays
  `Play(Rain, pitch=root)`, which is playback at the sample's root pitch.
- `.s("…")` accepts instruments and samples. `note("C4").s("piano")` plays
  `Play(Piano, pitch=60)`.

`.s` still applies to notes only, so the rule of ADR-0023 Decision 4 that
decides where `.s` may follow does not change: it is still rejected after a
receiver that plays drums or samples from `s("…")`. A drum or sample name and
an instrument name never share a string, so each name in the vocabulary
belongs to exactly one sound kind, and the three name sets stay disjoint.

`Sound` is `pub(all)`, so every exhaustive match on it gains the case:
`Sound::content`, the hosts' `route`, and `NoteOnControls`.

### 4. A per-control rule says whether a control follows while sounding

`Control::follows(self) -> Bool` sits next to `nesting` and `admits`. The
voice consults it when it attaches followers, so a control that does not
follow gets no follower and costs nothing per block.

| Fixed at onset (`follows` is false) | Followed while sounding (`follows` is true) |
|---|---|
| `begin`, `end`, the sample number (Decision 1) | `speed` and every existing control |

The sample number is set from the `Sound`, not from the event's controls, so
it never varies and would get no follower anyway. The rule still states it,
so a later change that lets it vary cannot make a sounding voice switch
waveforms.

Rejected: letting the node ignore changes. The follow work would still run
every block for every sounding voice.

### 5. An unregistered sample renders silence; "loading" is not a `SourceProblem`

This decision differs from the brief's proposal. A `SourceProblem` is decided
from the text alone (ADR-0022 Decision 7). Whether a sample has loaded is
runtime state that changes while the same text plays. If it were a source
problem, compiling would depend on the store, and the score would turn invalid
and then valid with no edit.

A note on a sample that is not registered yet starts a voice that renders
silence. That voice reads only an empty store entry. The host reports
pending samples on its own status channel, next to the source problem and
not inside it. The editor can show "loading" from that status. Phase 2 can
check what the text decides, such as an unknown sample name, as a
`Mistake`.

### 6. The store has fixed limits and allocates once

When the host creates the engine, the store allocates its sample memory
(32-bit floats) and its entry table once. Registering a sample copies into
free memory and allocates nothing. Allocating 480,000 floats took
0.5–0.75 ms in the AudioWorklet, which costs a quarter of a block, so
allocation stays off the render path.

The host chooses three limits when it creates the store:

| Limit | Browser default | Memory |
|---|---:|---:|
| Entries (samples in the store) | 64 | negligible (one small record each) |
| Samples per waveform | 1,440,000 (30 s at 48 kHz) | at most 5.76 MB per waveform |
| Total samples | 8,388,608 (about 175 s at 48 kHz) | 32 MiB |

The trade-off is that this memory is always in use. The browser engine
holds 32 MiB from start-up even for a score that plays no sample, and the
store cannot grow without allocating on the audio thread. A score that needs
more sample memory than the host chose fails with `over-limit` until the host
recreates the engine with a larger store. 32 MiB holds the built-in bank and
a handful of user samples. That is enough for chopped material, which uses
short samples, and a quarter of the 128 MB first proposed. Hosts that play
no samples, such as the CLAP prototype today, create an empty store and pay
nothing. That empty store is the `DspContext` default (Decision 2).

Making the 32 MiB store took 15–20 ms in the AudioWorklet at start-up
([measured](../performance/2026-11-24-sample-copy.md#making-the-browser-default-store);
the 9–13 ms first extrapolated was low). That is 6–8 render quanta, so the
host makes the store before playback starts, never while the context
renders.

A registration that exceeds a limit fails, and the host reports
`over-limit` on the same status channel as Decision 5. Phase 2 adds a
`SourceLimit` case for what the text decides, which is how many samples a score
declares.

### 7. Mono only

A waveform is one channel. A stereo file is mixed down when it is decoded.
Voices are panned as they are today.

### Replacing a sounding sample

Re-registering a slot copies the new waveform into free memory and then
switches the entry between two blocks. Voices that already sound keep the
old waveform and play it to its end. The old memory returns to the free list
once no voice of the sampler pool reads it, which is a scan of at most
`max_voices` voices. A registration that needs that memory before then fails
as over-limit. It never takes memory away from a sounding voice.

## Design this rests on

- **Store:** a fixed-capacity, engine-owned table from sample number to a
  waveform: memory range, length, and root pitch. Waveforms are stored at the
  engine's sample rate, and the host resamples them before registering. It is read-only
  while rendering. The registration API is host-neutral, so the browser and
  CLAP both use it.
- **Browser loading:** `decodeAudioData` and resampling run on the main
  thread. The `Float32Array` is transferred to the AudioWorklet. The worklet
  queues it and copies **16,384 samples per `process()` call** before
  rendering. It does not copy in the message handler, because a 10 s sample
  copied there in one go takes about 3 ms and makes the next block late.
  The measurement found about 6 ns per sample warm and 8–17 ns cold. At that
  chunk size a 10 s sample loads in 30 blocks (80 ms), and the copy takes at
  most about 10% of a block.
- **`SamplePlayer`:** a source node in the instrument template shape
  (source → ADSR → filters → level). Its rate is
  `2^((pitch − root) / 12) × speed`, and it reads with linear
  interpolation. `reset_runtime_state` clears its waveform reference and
  position.
- **One sampler pool** for all samples, routed by `Play(..)`. It is not one
  pool per sample.
- **Slicing controls:** `begin` (0–1), `end` (0–1), and `speed` (a multiplier;
  a negative value plays backwards). Each takes numbers, patterns, or signals.
  `admits` gives `begin` and `end` the domain 0–1 and rejects `NaN` for
  `speed`. When `begin ≥ end`, the voice plays nothing.
- **Vocabulary:** phase 1 is a small built-in bank whose material has a
  redistributable licence. Phase 2 adds samples declared in the score, such as
  `sample("piano", "…");`. The parser still parses from the text alone: a
  declaration names a sample, and its data is runtime state (Decision 5).

All names are proposals. `begin`, `end`, `speed`, `sample`, and `Play` are not
used as names in `mini`, `control`, or `score` today.

## Alternatives considered

- **Write samples from JS into linear memory.** That needs a linear-memory
  target or a second module. The measured per-call copy is cheap enough.
- **Send samples through the score text.** The text would grow by orders of
  magnitude, and source limits such as 8,192 code units exist to keep parsing
  bounded.
- **One pool per sample.** A user bank of 64 samples would mean 64 pools of
  idle voices.
- **Report loading as a `SourceProblem`.** See Decision 5.

## Consequences

- Decisions 1–3 change public types: `Control`, `DspContext`, `Sound`, and a
  new `Sample`. Decision 4 adds a `Control` rule. They need Koji's approval
  before implementation.
- Every exhaustive match on `Sound` and `Control` gains a case.
- A score that plays a sample before it loads stays silent for that sample,
  and the status shows why.
- Sample memory is a fixed allocation, sized at start-up.

## Order of work

1. This ADR. Accepted.
2. Measure the copy cost into wasm-gc in an AudioWorklet. Done
   ([record](../performance/2026-11-24-sample-copy.md)).
3. The store and `SamplePlayer`, with offline tests: rate, interpolation,
   reset, empty entry, and replacement while sounding. Done. A replaced
   waveform's memory is not reused yet.
4. The built-in bank, the sampler pool, routing, and browser loading in
   16,384-sample chunks. The pool reclaims a replaced waveform's memory once
   no voice reads it. Done: the bank as `@score.Sample` with generated
   material, `Sound::Play`, sample names in `s("…")` and `.s("…")`, routing to
   the sampler pool, the store made before the first render, chunked loading,
   the status channel, and the real-browser loading and playback checks
   ([record](../performance/2026-11-24-sample-copy.md#stage-4-loading-while-a-realtime-context-plays)).
   The editor's vocabulary lists the samples, so completion offers them in
   both strings. Not done: reclaiming a replaced waveform's memory.
5. `begin`, `end`, and `speed`, and the `follows` rule.
6. Samples declared in the score.

## Not covered

Time-stretching, granular synthesis, multi-sampled instruments, and stereo
samples.

## Verification

- A `SamplePlayer` at its root pitch reproduces its waveform exactly. An
  octave up reads every second sample. A negative `speed` reads backwards.
- A note on an empty entry renders silence and allocates nothing.
- A voice reused through `reset_runtime_state` starts at its new `begin`.
- Changing `begin` while a voice sounds does not move it, and changing `speed`
  does.
- Replacing a sounding sample leaves the sounding voice on the old waveform.
- A registration over each limit fails and leaves the store unchanged.
- Stage 4, in a real browser: loading a 10 s sample during playback causes
  no dropouts. The copy measurement used `Date.now()` (1 ms), which cannot see
  GC pauses or late blocks, so this check must use evidence that can see them:
  - a realtime `AudioContext` playing a known score while samples load;
  - the rendered output checked for discontinuities, as the crackle probe
    (`web/crackle-probe-processor.js`) does;
  - the browser's underrun or glitch count where it exposes one.

  The check runs in Chromium at least, and repeats in Firefox and Safari
  before the browser path is called done.
