# Polyphonic voice pools

`voice` turns a compiled mono graph template into a fixed-capacity polyphonic
instrument. Each slot owns its DSP runtime state. The pool starts notes, gates
envelopes, steals voices under load, pans and mixes active voices to stereo,
and reclaims finished releases.

## Create a voice pool

A voice template may contain any valid mono graph. Every authored `Adsr` must be
connected to the output; orphan envelopes are rejected because the pool gates
all surviving envelopes for each note.

```mbt check
///|
test "start, render, and release a voice" {
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=16)
  let template = @graph.CompiledTemplate::analyze([
    @graph.DspNode::oscillator(@dsp.Waveform::Sine, 440.0),
    @graph.DspNode::adsr(
      attack_ms=0.0,
      decay_ms=0.0,
      sustain=1.0,
      release_ms=5.0,
    ),
    @graph.DspNode::envelope_gain(input=0, envelope=1, amount=0.25),
    @graph.DspNode::output(2),
  ])
  let pool = @voice.VoicePool::new(template, context, max_voices=4).unwrap()
  let handle = pool.note_on([]).unwrap()
  let left = context.make_buffer()
  let right = context.make_buffer()

  assert_true(pool.voice_state(handle) is @voice.VoiceState::Active)
  pool.process(context, left, right)
  assert_true(left.any(sample => sample != 0.0))
  assert_true(right.any(sample => sample != 0.0))

  assert_true(pool.note_off_result(handle) is Ok(_))
  assert_true(pool.voice_state(handle) is @voice.VoiceState::Releasing)
}
```

`note_off_result` starts the envelope release. `kill_result` immediately returns
a slot to `Idle`; `note_off_all` and `kill_all` apply those behaviors to the
whole pool.

## Per-note graph controls

`VoicePool::note_on` accepts a transactional batch of `GraphControl` values.
Controls target authoring indices in the template and are applied before its
ADSR gates open.

```mbt check
///|
test "set oscillator frequency for one voice" {
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=8)
  let template = @graph.CompiledTemplate::analyze([
    @graph.DspNode::oscillator(@dsp.Waveform::Triangle, 220.0),
    @graph.DspNode::output(0),
  ])
  let pool = @voice.VoicePool::new(template, context, max_voices=2).unwrap()
  let handle = pool.note_on([
    @graph.GraphControl::set_param(0, @graph.GraphParamSlot::Value0, 440.0),
  ])

  assert_true(handle is Some(_))
  assert_eq(pool.active_voice_count(), 1)
}
```

Invalid batches do not activate or partially configure a voice.

## Voice stealing and handles

Allocation follows three priorities:

1. an idle slot;
2. the oldest releasing voice;
3. the oldest active voice.

`VoiceHandle` combines a slot index with a generation. Reusing a stolen slot
increments its generation, so an old handle cannot release or modify the new
occupant.

```mbt check
///|
test "a stolen handle cannot control its replacement" {
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=4)
  let template = @graph.CompiledTemplate::analyze([
    @graph.DspNode::constant(0.25),
    @graph.DspNode::output(0),
  ])
  let pool = @voice.VoicePool::new(template, context, max_voices=1).unwrap()
  let stale = pool.note_on([]).unwrap()
  let current = pool.note_on([]).unwrap()

  assert_true(stale != current)
  assert_true(
    pool.note_off_result(stale)
    is Err(@voice.VoiceControlError::InvalidVoiceHandle(_)),
  )
  assert_true(pool.voice_state(current) is @voice.VoiceState::Active)
}
```

Use the result-returning mutation methods when the host needs the rejection
reason. The deprecated Boolean wrappers collapse invalid and stale handles into
`false`.

## Bind pattern controls once

`BoundVoicePool` couples a `VoicePool` with a `ControlBindingMap` validated
against the same `CompiledTemplate`. It converts named pattern controls into
graph controls without making the pattern layer know graph indices.

```mbt check
///|
test "resolve a named control at note-on" {
  let context = @dsp.DspContext::new(sample_rate=48000.0, block_size=8)
  let template = @graph.CompiledTemplate::analyze([
    @graph.DspNode::oscillator(@dsp.Waveform::Saw, 220.0),
    @graph.DspNode::output(0),
  ])
  let bindings = @graph.ControlBindingBuilder::new().bind(
    key="note",
    node_index=0,
    slot=@graph.GraphParamSlot::Value0,
  )
  let pool = @voice.BoundVoicePool::new(
    template,
    context,
    bindings,
    max_voices=4,
  ).unwrap()
  let handle = pool.note_on_controls({ "note": 330.0 })

  assert_true(handle is Some(_))
  assert_eq(pool.active_voice_count(), 1)
}
```

`set_template` replaces the template and bindings transactionally. If graph or
binding validation fails, the previous pair remains active. Notes already
sounding keep their compiled graph and envelope-index snapshot.

Use `VoicePool` when the caller already produces `GraphControl` values. Use
`BoundVoicePool` at the pattern-to-audio boundary, where events carry named
control maps.

## Pan, send, and output

Both pools mix every mono voice into left and right output buffers using cached
equal-power pan gains. `set_voice_pan_result` changes one live voice.
`process_with_send` also writes a single post-pan stereo send; use
`set_voice_send_result` to set its normalized gain.

`process` clears and fills the destination buffers. After mixing, non-finite
samples are replaced with zero; `last_sanitized_count` reports the number
replaced during the most recent call.

## Gate timing

`BoundVoicePool::note_gate` lets the scheduler derive a physical gate duration
from named envelope controls. A valid `hold` control produces
`AfterSeconds(attack + hold)` only when attack, decay, sustain, and release are
all bound. Otherwise the event retains `EventEnd` timing. Invalid durations
produce `InvalidDuration`.

Release processing continues after gate-off until the compiled graph reports
that the voice is finished.

## Real-time behavior

`VoicePool::new` allocates every slot, mono scratch buffer, and initial compiled
graph before playback. With an unchanged template, an idle slot resets and
reuses its prepared graph.

Two paths need care:

- after `set_template`, the generic note-on path may compile the replacement
  lazily when a slot is reused;
- stealing an active voice with a non-empty generic control batch may compile a
  fresh graph so a rejected batch cannot damage the old voice.

Hosts with a fixed, prevalidated four-parameter layout can use
`note_on_prevalidated_params4_id`. It reuses a prepared slot and returns a
packed primitive handle, or a negative value when the slot is not prepared.
Keep template compilation and generic allocation paths off the audio callback.

## Package boundary

`voice` owns polyphonic allocation, per-slot graph state, envelope lifecycle,
pan, and mixdown. It does not schedule musical time or interpret pattern arcs.

- [`graph/`](../graph/) — graph compilation and runtime controls.
- [`scheduler/`](../scheduler/) — pattern events, note expiry, and block timing.
- [Technical reference](../docs/technical-reference.md#353-pattern-to-dsp-control-binding)
- [Mini-to-graph boundary](../docs/mini-graph-authoring-boundary.md)
