# Scheduler

The scheduler bridges identity-bearing pattern/song snapshots to a bound voice
pool. Edit orchestration helpers let UI or authoring code stage a replacement
snapshot, choose how already-sounding voices should be reconciled, and
optionally apply live graph-control changes to matching active voices before the
replacement is accepted at the next block boundary. Normal browser edits keep
sounding voices and defer changed material until its next entry. The explicit
voice-control helpers below are separate operations.

## Architecture context

In moondsp's layered design, `scheduler` translates musical events into
sample-accurate audio voice triggers across block boundaries:

```text
[ mini ] (text notation)
   ↓
[ pattern / song ] (musical time & event streams)
   ↓
[ scheduler ] ← (event-to-voice scheduling & block quantization)
   ↓
[ voice ] (polyphonic voice allocation & mixing)
   ↓
[ graph ] (topology validation & compilation)
   ↓
[ dsp ] (primitive state & buffer processing)
```

- **Upstream consumers**: `browser/internal/playback_host` drives live browser
  playback through staged snapshots; custom hosts feed `Pat[ControlMap]` or
  `Song[ControlMap]` instances into the scheduler.
- **Downstream dependencies**: [`voice/`](../voice/) receives dispatched note
  events, gates, and controls; [`pattern/`](../pattern/) and [`song/`](../song/)
  supply time intervals and queryable event streams; [`dsp/`](../dsp/) defines
  the sample rate and block capacity.

## API quick reference

| Category | Types | Key operations |
|---|---|---|
| **Scheduler Engine** | `PatternScheduler` | `PatternScheduler::new`, `PatternScheduler::process_block`, `PatternScheduler::process_song_block`, `PatternScheduler::process_playback_snapshot_block` |
| **Playback & Snapshots** | `PatternScheduler`, `PlaybackSnapshot` | `PatternScheduler::queue_playback_snapshot`, `PatternScheduler::queue_pattern_snapshot`, `PatternScheduler::queue_song_snapshot`, `PlaybackSnapshot::pattern`, `PlaybackSnapshot::song`, `PlaybackSnapshot::query` |
| **Snapshot Observation** | `PatternScheduler`, `PlaybackSnapshot` | `PatternScheduler::accepted_snapshot`, `PatternScheduler::queued_snapshot`, `PatternScheduler::pending_material_change_count`, `PatternScheduler::skipped_material_change_count` |
| **Timing & Transport** | `PatternScheduler`, `BlockFrame`, `PerformanceTime` | `PatternScheduler::set_bpm`, `PatternScheduler::bpm`, `PatternScheduler::current_block`, `PatternScheduler::sample_at`, `PatternScheduler::sample_counter`, `PatternScheduler::reset_transport` |
| **Voice Scopes & Reconciliation** | `PatternVoiceScope`, `SongVoiceScope`, `ActiveVoiceEffect` | `PatternVoiceScope::node`, `SongVoiceScope::section`, `SongVoiceScope::occurrence`, `PatternScheduler::apply_pattern_voice_effect_result`, `PatternScheduler::apply_song_voice_effect_result` |
| **Controls & Notes** | `ControlMapper`, `VoiceControlBatch` | `default_control_mapper`, `ControlMapper::new`, `PatternScheduler::push_active_note`, `PatternScheduler::expire_notes`, `PatternScheduler::active_note_count` |

## Transport

`PatternScheduler::new` validates the tempo and DSP context and returns a
`Result`. Use `current_block()` to read the next block's sample range and
rational musical span. Use `sample_at(position)` for conversion against the
current clock; an absolute sample count and a BPM alone cannot describe an
edited transport.

A tempo edit takes effect at the next unrendered sample. It preserves the
musical position already reached. Only the remaining distance to musical
onsets and note endings uses the new tempo. A physical deadline registered
with `push_active_note_until` stays at its original sample. Tempo edits neither
retrigger voices nor change their pitch, timbre, or release envelope.

Block rendering splits DSP processing at each onset and gate-off. Boundaries
round upward to the first sample at or after the musical time. A fractional
onset just before a block ends is retained for the next block, including when
a tempo edit occurs there. Scratch buffers and segment contexts are allocated
at scheduler construction. Pattern queries and voice dispatch still allocate;
this change does not establish an allocation-free audio callback.

The clock accepts 0.001–1000 BPM and rounds to the nearest 0.001 BPM (ties
upward). Sample rates must be integral, from 1 through 384000 Hz; block sizes
must be 1–65536. These are numeric implementation bounds, not musical units.
One source cycle advances at BPM cycles per minute under the existing API;
a cycle has no intrinsic meter or quarter-note meaning.

Conversions use checked Int64 arithmetic and can return `TimeOutOfRange`,
including when an intermediate rational conversion cannot be represented.
An invalid tempo edit leaves the clock and active deadlines unchanged. Render
conversion errors are available from `last_transport_error()` until transport
reset. An unrepresentable event is skipped; exhaustion of the clock range
silences the block and kills its voices without advancing the clock.

Song tempo edits can continue on the browser's existing playback path. A song
layout change still requires Stop then Play. Independent clocks are a separate implementation stage.

## Note envelopes

Browser `note()` and `chord()` support `.attack(s)`, `.hold(s)`, and
`.release(s)`. Values are seconds, from 0 to 86400. Omitted attack and release
use the instrument defaults. Without hold, the event end closes the gate,
including during attack. Release starts from the current level.

With hold, the note reaches its peak during attack, stays there for hold,
and fades out during release. Its lifetime is attack + hold + release,
independent of `.slow()` and subsequent tempo changes. Notes overlap within
the voice pool's capacity. Live edits preserve settings on sounding notes;
Stop still stops playback. Drum envelopes are unchanged.

`.gate(n)` shortens each event to a musical fraction from 0 through 1 without
moving its onset or changing the pattern period. Factors finer than one
billionth are rounded before event arithmetic to keep later-cycle endpoints
representable. The shortened endpoint follows tempo edits. An explicit
`.hold(s)` keeps its physical-seconds behavior and overrides the event-derived
endpoint.

## Pattern edits

An edit is accepted at the next render block. Each material finishes its current
source cycle, including notes that have not started yet. The edited material
starts at its next entry. A 3-cycle melody and a 4-cycle melody switch at their
own boundaries; neither waits for a common multiple. DSP rendering splits at
the exact boundary, rounded up to a sample, even inside an audio block.

Later content edits keep their reserved boundary while it remains eligible for
the replacement placement. Moving a waiting finite occurrence behind the
transport invalidates that reservation and classifies the occurrence as skipped.
If current material still has to reach its reserved exit, it finishes there
without installing the skipped incoming occurrence. Invalid input leaves the
last accepted reservation intact. Reverting to active content cancels that
material's reservation. Deletion stops future events at the reserved entry.
Already sounding voices retain their deadlines and release tails.

Changing a material's period starts its new cycle at the reserved old entry.
Content-only edits preserve its origin and cycle count. Tempo changes preserve
the musical reservation; its physical sample position follows the transport.
A changed finite occurrence with no later entry keeps its current phrase. A
newly added finite occurrence whose authored start has already passed is skipped
for the rest of that Play; an internal material-grid entry must not make it join
mid-occurrence. The latest accepted score becomes eligible from the beginning
after Stop then Play. New unbounded Pattern materials still wait for the next
entry of their own source grid, without backfilling earlier notes.

### Material periods and addresses

The runtime mini compiler records authored periods rather than trying to infer
repetition from generated events. Literals have a one-cycle entry period;
`slow` and `fast` scale it. Ordinary stacks keep independent members, including
when gain or filtering wraps the stack. `every` and `jux` form one material with
the input's entry period: their changing values need not repeat every entry.

Named references keep addresses when uniquely named siblings are reordered
inside the same stack. Anonymous members use positions; repeated uses of the
same name use occurrence order. Restructuring a stack can therefore create new
addresses. This is not semantic identity inference from text similarity.

### Content comparison

Library callers can use `named_entry` to name a material and `material()` to
make an expression indivisible. Names address edits; content comparison does
not depend on those names. Scalar notes, sounds, controls, silence, and their
combinations track content automatically. `same_content` answers whether two
patterns have known equal content without exposing the representation.
Control values do not expose mutable storage: `set` and `merge` return new
values, and `entries` returns an owned copy. Editing an event's exported controls
cannot change its source pattern or invalidate content comparison.

`TimeTransform` describes a known Fast, Slow, or Reverse operation. It can apply
the operation, repeat it with `every`, or create a stereo `jux` expression.
Its execution and identity are owned together. `select_control` selects events
by control presence or exact value; routing adapters need no identity strings.

Arbitrary queries from `Pat::from_query` and ordinary callback-based `filter_map`,
`every`, and `jux` remain supported. Their content is unknown, so edits are
conservatively replaced. Grouping or applying a known transform cannot turn
unknown content into known content. Callers cannot attach a content identifier
to arbitrary code. Generic `Pat::pure` also remains unknown; use the scalar
control constructors for automatically tracked control sources.

These changes require no additional authoring syntax or UI settings. Content
comparison, entry addressing, and event generation remain separate concerns.

### Acceptance and receipts

The browser Player prepares a complete source and all route tempo/deadline plans
before changing Current song. Rejection preserves the previous song, transport,
and material reservations. Accepted plans are installed once; the owner does
not expose preparation tokens to its clients. See the
[Player contract](../docs/technical-reference.md#browser-player-ownership-and-source-updates).

`accepted_snapshot()` returns the Pattern or Song selected by an explicit
`accept_playback_snapshot()` call or a render-block commit. Independent scheduler
clients may use `queue_playback_snapshot()` instead; `queued_snapshot()` exposes
that snapshot until commitment. Player operations accept immediately, including
while Paused. In the lower-level queued API both observations can be present at once.
An accepted snapshot's revision does not imply that all changed materials are audible:
`pending_material_change_count()` reports changes waiting for a reserved entry,
and `skipped_material_change_count()` reports finite changes that cannot enter
during this Play. These queries do not describe transport activity or whether
audio is audible.

Worklet receipts report command acceptance and an owner projection immediately,
not after a rendered block. The UI shows Play/Pause, a separate Restart command,
and nonzero Pending/Skipped material counts. Owner acceptance is distinct from
audible material replacement.

Reconciliation and event selection are deterministic functions. The playback
owner installs their returned states; the scheduler owns clocks and voice
lifetimes. Parsing, metadata construction, and event queries still allocate.

Lowering constructs prepared snapshots whose timing, identity, and source
metadata are already valid. Reconciliation parses each prepared entry and the
transport position into one exclusive runtime state. Rendering consumes that
state directly: it does not repeat validation, interpret a missing boundary, or
turn a rejected combination into a no-op.

## Explicit voice control

```mbt check
///|
test "edit orchestration stages a replacement and reconciles active voices" {
  let ctx = @moondsp.DspContext::new(sample_rate=48000.0, block_size=128)
  let pool = @moondsp.BoundVoicePool::new(
    @moondsp.CompiledTemplate::analyze([
      @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 440.0),
      @moondsp.DspNode::adsr(
        attack_ms=0.01,
        decay_ms=0.1,
        sustain=0.7,
        release_ms=0.3,
      ),
      @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
      @moondsp.DspNode::output(2),
    ]),
    ctx,
    @moondsp.ControlBindingBuilder::new().bind(
      key="note",
      node_index=0,
      slot=@moondsp.GraphParamSlot::Value0,
    ),
    max_voices=4,
  ).unwrap()
  let sched = @scheduler.PatternScheduler::new(bpm=120.0, ctx~).unwrap()
  let edited = try! @identity.PatternNodeId::from_string("docs:lead")
  let replacement_root = try! @identity.PatternNodeId::from_string(
    "docs:replacement",
  )
  let active_doc = @pattern.PatternDoc::from_pattern(
    id=edited,
    pat=@pattern.note(60.0),
  )
  let active_snapshot = try! active_doc.lower()

  let replacement_doc = @pattern.PatternDoc::from_pattern(
    id=replacement_root,
    pat=@pattern.note(67.0),
  )
  let replacement = try! replacement_doc.lower()
  let left = @moondsp.AudioBuffer::filled(128)
  let right = @moondsp.AudioBuffer::filled(128)
  sched.queue_pattern_snapshot(active_snapshot)
  sched.process_snapshot_block(pool, left, right)
  let outcome = sched
    .queue_pattern_snapshot_effect_result(
      replacement,
      @scheduler.PatternVoiceScope::node(edited),
      @scheduler.ActiveVoiceEffect::Release,
      pool,
    )
    .unwrap()

  assert_eq(outcome.retuned_voice_count, 0)
  assert_eq(outcome.detached_note_count, 1)
  assert_true(sched.accepted_snapshot() is Some(_))
  assert_true(
    sched.queued_snapshot() is Some(@scheduler.PlaybackSnapshot::Pattern(_)),
  )
  assert_eq(sched.active_note_count(), 0)
}
```
