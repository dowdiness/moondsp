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

Use `scripts/audit-clap-audio-allocations.sh --expect-zero` only after the
remaining event-path blockers are fixed.

## Measured callback allocations

After moving render `DspContext` creation to activation-owned engine state, the
measured Linux callback-path allocation counts are:

| Scenario | Allocations | Bytes |
| --- | ---: | ---: |
| Steady idle render, no events | 0 | 0 |
| Note-on event at frame 64 | 178 | 23879 |
| Steady active render, no events | 0 | 0 |
| Master-gain automation with active voice | 0 | 0 |
| Cutoff automation with active voice | 20 | 488 |
| Voice-gain automation with active voice | 25 | 596 |
| Pan automation with active voice | 1 | 12 |
| CLAP note-off with active voice | 9 | 132 |
| Transport play with active voice | 0 | 0 |
| Transport stop with active voice | 5 | 84 |
| MIDI note-on | 178 | 23879 |
| Steady MIDI active render | 0 | 0 |
| MIDI note-off with active voice | 17 | 312 |
| MIDI all-notes-off CC with active voice | 5 | 84 |

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
- Note-on and MIDI note-on are still allocation-heavy. The path builds a note
  control map, resolves it to graph controls, compiles a fresh per-voice graph,
  copies ADSR index snapshots, creates a voice handle, and stores an active-note
  map entry.
- Cutoff and voice-gain automation still allocate while voices are active. The
  path builds graph-control objects and one-element arrays, validates by copying
  simulated nodes, updates graph nodes by copy, and boxes `Result` values.
- Pan automation is smaller but still allocates a boxed result on the active
  voice-control path.
- Note-off, transport-stop, and MIDI all-notes-off paths still allocate through
  gate-off/result wrappers. MIDI note-off additionally takes the key-based
  active-note search path.
- Output copying from the engine buffers to CLAP `data32`/`data64` does not
  allocate.

## Remaining production blockers

Current CLAP support remains prototype-only. To resolve #173, the remaining work
is to remove allocations from note, release, and active-parameter event paths:

1. Precompile or otherwise reserve per-voice runtime graphs during activation or
   pool preparation, then reset/reuse them on note-on instead of compiling in the
   audio callback.
2. Replace the CLAP note-control `Map[String, Double]` path with a fixed,
   prevalidated control path for the built-in synth parameters.
3. Avoid graph-control arrays, simulated-node copies, copied `DspNode` updates,
   and boxed `Result` values on audio-thread parameter automation.
4. Replace or reserve the active-note lookup storage so note-on/off does not grow
   or allocate in the callback.
5. Re-run the allocation audit with `--expect-zero` before changing the CLAP
   plan from prototype status.
