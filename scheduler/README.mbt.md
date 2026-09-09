# Scheduler

The scheduler bridges identity-bearing pattern/song snapshots to a bound voice
pool. Edit orchestration helpers let UI or authoring code stage a replacement
snapshot, choose how already-sounding voices should be reconciled, and
optionally apply live graph-control changes to matching active voices before the
replacement is accepted at the next block boundary. Normal browser edits keep
sounding voices and defer changed material until its next entry. The explicit
voice-control helpers below are separate operations.

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
layout change still requires Stop then Play. Group defaults, explicit seconds
in the language, and independent clocks are separate implementation stages.

## Pattern edits

An edit is accepted at the next render block. Each material finishes its current
source cycle, including notes that have not started yet. The edited material
starts at its next entry. A 3-cycle melody and a 4-cycle melody switch at their
own boundaries; neither waits for a common multiple. DSP rendering splits at
the exact boundary, rounded up to a sample, even inside an audio block.

Later edits replace the reserved content without moving its boundary. Invalid
input leaves the last valid reservation intact. Reverting to the active content
cancels that material's reservation. Deletion stops future events at the reserved
entry. Already sounding voices retain their deadlines and release tails.

Changing a material's period starts its new cycle at the reserved old entry.
Content-only edits preserve its origin and cycle count. Tempo changes preserve
the musical reservation; its physical sample position follows the transport.
A finite occurrence with no later entry keeps its current phrase. The latest
accepted score is used after Stop then Play. New materials join at the next
entry of their own source grid, without backfilling earlier notes.

The runtime mini compiler records authored periods rather than trying to infer
repetition from generated events. Literals have a one-cycle entry period;
`slow` and `fast` scale it. Ordinary stacks keep independent members, including
when gain or filtering wraps the stack. `every` and `jux` form one material with
the input's entry period: their changing values need not repeat every entry.

Named references keep addresses when uniquely named siblings are reordered
inside the same stack. Anonymous members use positions; repeated uses of the
same name use occurrence order. Restructuring a stack can therefore create new
addresses. This is not semantic identity inference from text similarity.

Library callers can use `named_entry` to name a material and `material()` to
make an expression indivisible. Names address edits; content comparison does
not depend on those names. Scalar notes, sounds, controls, silence, and their
combinations track content automatically. `same_content` answers whether two
patterns have known equal content without exposing the representation.

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

Revision accessors report the accepted authored score. They do not assert that
all its materials are already audible. Pending accessors also include materials
waiting for an entry. Worklet receipts use `acceptedAtSample`, replacing the
misleading `appliedAtSample`. The UI reports queued edits and keeps Play / Stop
as its only transport control.

Reconciliation and event selection are deterministic functions. The playback
owner installs their returned states; the scheduler owns clocks and voice
lifetimes. Parsing, metadata construction, and event queries still allocate.

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
  let arc = @pattern.TimeSpan::new(
    @pattern.Rational::from_int(0),
    @pattern.Rational::new(1L, 100L),
  )
  let active_playback = @scheduler.PlaybackSnapshot::pattern(active_snapshot)
  let active_events = active_playback.query_playback_events(arc)
  sched.process_playback_events(active_events, arc, pool)

  let replacement_doc = @pattern.PatternDoc::from_pattern(
    id=replacement_root,
    pat=@pattern.note(67.0),
  )
  let replacement = try! replacement_doc.lower()
  let outcome = sched
    .queue_pattern_snapshot_live_control_edit_result(
      snapshot=replacement,
      policy=@scheduler.AffectedVoicePolicy::GateOffAffected,
      edit=@scheduler.AffectedVoiceEditScope::pattern_node(edited),
      controls=[
        // Pattern notes use the "note" binding's MIDI-to-Hz mapping; direct
        // graph controls write the target slot's raw value.
        @moondsp.GraphControl::set_param(
          0,
          @moondsp.GraphParamSlot::Value0,
          330.0,
        ),
      ],
      pool~,
    )
    .unwrap()

  assert_eq(outcome.controlled_voice_count, 1)
  assert_eq(outcome.removed_active_note_count, 1)
  assert_true(sched.has_pending_pattern_snapshot())
  assert_eq(sched.active_note_count(), 0)
}
```
