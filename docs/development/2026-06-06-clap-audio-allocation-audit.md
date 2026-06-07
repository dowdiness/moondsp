# CLAP audio-callback allocation audit

Issue: #173

## Method

Built the Linux native payload with:

```bash
scripts/build-clap-prototype.sh
```

Then audited `moondsp_plugin_process` with an `LD_PRELOAD` malloc/calloc/realloc
counter enabled only around each `plugin->process` call. The reusable command is:

```bash
scripts/audit-clap-audio-allocations.sh
```

The current measured CLAP event/render paths pass:

```bash
scripts/audit-clap-audio-allocations.sh --expect-zero
```

## Measured callback allocations

After moving render `DspContext` creation to activation-owned engine state and
routing CLAP event handling through prepared scalar controls, the measured Linux
callback-path allocation counts are:

| Scenario | Allocations | Bytes |
| --- | ---: | ---: |
| Steady idle render, no events | 0 | 0 |
| Note-on event at frame 64 | 0 | 0 |
| Steady active render, no events | 0 | 0 |
| Master-gain automation with active voice | 0 | 0 |
| Cutoff automation with active voice | 0 | 0 |
| Voice-gain automation with active voice | 0 | 0 |
| Pan automation with active voice | 0 | 0 |
| CLAP note-off with active voice | 0 | 0 |
| Transport play with active voice | 0 | 0 |
| Transport stop with active voice | 0 | 0 |
| MIDI note-on | 0 | 0 |
| Steady MIDI active render | 0 | 0 |
| MIDI note-off with active voice | 0 | 0 |
| MIDI all-notes-off CC with active voice | 0 | 0 |

`CLAP_PROCESS_CONTINUE` is reported as status `1` by the harness.

## Source-path inventory

- The C callback does not directly allocate in `clear_output`, event dispatch,
  `render_span`, or output copy. Host-provided event accessors are outside the
  plugin's allocation count.
- Event timestamp block splitting is preserved. Events at non-zero frame times
  still render the pre-event span, handle the event, then render the post-event
  span.
- Steady render is allocation-free in the measured native payload. The engine
  preallocates render contexts for supported span sizes during activation and
  selects the matching context per span.
- Note-on and MIDI note-on are allocation-free in the measured stable-template
  CLAP path. The path now bypasses CLAP note-control maps, graph-control batch
  construction, result-typed graph-control application, ADSR snapshot copies,
  boxed voice-handle return values, pan result boxing, and growable active-note
  map insertion.
- Cutoff, voice-gain, and pan automation are allocation-free in the measured
  CLAP path. They use primitive active-note storage and allocation-conscious
  voice/graph parameter predicates instead of graph-control arrays and boxed
  result-returning wrappers.
- CLAP note-off, MIDI note-off, transport-stop, and MIDI all-notes-off are
  allocation-free in the measured path after switching ADSR gate helpers and
  note-off dispatch to allocation-conscious primitives.
- Output copying from the engine buffers to CLAP `data32`/`data64` does not
  allocate.

## Remaining production blockers

Current CLAP support remains prototype-only. The audited CLAP event/render paths
now satisfy the allocation gate for #173, including `--expect-zero`. Do not treat
that as DAW readiness. Remaining production gates are outside this allocation
slice:

1. Keep any future template-edit path from lazily compiling on the audio thread;
   the fixed CLAP stable-template path currently fails closed if a prepared slot
   is stale.
2. Stabilize the MoonBit/native bridge symbols and repeat the allocation audit
   after bridge changes.
3. Load the plugin in a real CLAP host/DAW before changing the CLAP plan from
   prototype status.
