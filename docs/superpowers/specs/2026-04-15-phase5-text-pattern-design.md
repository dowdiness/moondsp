# Phase 5 Completion: Text Pattern to Audible Output

**Date:** 2026-04-15
**Status:** Draft
**Success metric:** `s("bd sd hh sd").fast(2)` plays a recognizable drum beat in the browser

---

## 1. Overview

Complete the Phase 5 deliverable: type a pattern expression in a text field, hear polyphonic audio in the browser. The pipeline is: text input → loom-based parser → Pat[ControlMap] → multi-pool scheduler routing → mixed stereo output.

## 2. Package Structure

```
mini/               NEW — loom-based mini-notation parser
  token.mbt           Token enum
  lexer.mbt           Tokenizer for loom
  parser.mbt          Grammar spec + CST fold → Pat[ControlMap]
  drums.mbt           Sound name → MIDI number mapping
  *_test.mbt          Parser tests

pattern/            MODIFIED — add filter_map combinator
browser/            MODIFIED — multi-pool routing, text input handling
web/index.html      MODIFIED — text input UI
web/processor.js    MODIFIED — pattern text message handling
```

### Dependencies

Add to `moon.mod.json`:
```json
"dowdiness/loom": { "path": "../canopy/loom/loom" },
"dowdiness/seam": { "path": "../canopy/loom/seam" }
```

`mini/` depends on: `loom`, `seam`, `pattern`. Zero dependency on `lib/`, `graph/`, `voice/`, `scheduler/`, `browser/`.

### Risk: loom wasm-gc compatibility

canopy targets JS by default. loom must compile to wasm-gc without JS-specific FFI. Verify early in implementation. Fallback: hand-written recursive descent parser (~150 lines) with the same public API.

## 3. Mini-Notation Grammar

### Entry points (outer syntax)

```
expr     = primary ( "." method )*
primary  = "s(" string ")" | "note(" string ")"
method   = "fast(" number ")" | "slow(" number ")" | "rev()"
```

### Inner notation (inside quotes)

```
string   = '"' notation '"'
notation = layer ( "," layer )*       // comma → stack
layer    = element+                    // space-separated → sequence
element  = atom | "[" notation "]"    // brackets → sub-group
atom     = identifier | number
```

### Semantics

| Input | Produces |
|-------|----------|
| `s("bd sd hh sd")` | `sequence([sound("bd"), sound("sd"), sound("hh"), sound("sd")])` |
| `s("bd [sd hh]")` | `sequence([sound("bd"), sequence([sound("sd"), sound("hh")])])` |
| `s("bd sd, hh hh hh")` | `stack([sequence([sound("bd"), sound("sd")]), sequence([sound("hh"), sound("hh"), sound("hh")])])` |
| `note("60 64 67")` | `sequence([note(60), note(64), note(67)])` |
| `s("bd sd").fast(2)` | above sequence with `.fast(Rational::from_int(2))` applied |

### ControlMap keys

**Critical: separate keys to avoid collision.**

- `s("bd")` produces `{"sound": 36.0}` — the "sound" key holds a GM drum number
- `note("60")` produces `{"note": 60.0}` — the "note" key holds a MIDI pitch
- These are mutually exclusive per event. The router checks which key is present.

### Sound name mapping (General MIDI drum numbers)

| Name | MIDI | Description |
|------|------|-------------|
| `bd` | 36 | Bass drum |
| `sd` | 38 | Snare drum |
| `hh` | 42 | Closed hi-hat |

Phase 5 ships with 3 sounds. Additional sounds (`cp`=39, `oh`=46, etc.) can be added later by registering new templates. Only known names are accepted in `s()`. Unknown names are parse errors.

### Input validation

- `fast(n)` / `slow(n)`: n must be a positive number. Zero and negative values are parse errors.
- Inside `s()`: only known sound names. Bare numbers are invalid.
- Inside `note()`: only numbers (integer or float). Names are invalid.
- Empty string or whitespace-only: parse error.
- On parse error: old pattern stays active, error message returned to main thread.

### Method chain evaluation

Left-to-right: `s("bd sd").fast(2).rev()` = `rev(fast(sequence([...]), 2))`.

## 4. New Pattern Combinator

Add `filter_map` to the `pattern/` package:

```
pub fn Pat::filter_map[A](self: Pat[A], f: (A) -> A?) -> Pat[A]
```

Queries the underlying pattern, keeps events where `f(value)` returns `Some(new_value)`, discards events where `f` returns `None`. Preserves event timing (whole and part spans unchanged).

Used by the browser layer to split a parsed pattern into sub-patterns per sound type.

**Efficiency note:** Each sub-pattern re-queries the full original pattern. Acceptable for Phase 5's small patterns (< 20 events/cycle). For Phase 6+, consider single-query-then-route.

## 5. Drum Templates

Each template is an `Array[DspNode]` chain with fixed parameters. ADSR values are starting points — tune by ear during implementation.

### bd (bass drum) — MIDI 36

```
Oscillator(Sine, 60.0)
→ ADSR(attack=0.001, decay=0.15, sustain=0.0, release=0.1)
→ Gain(_, 1.0)
→ Output(_)
```

Low sine thump with fast decay. No sustain — fully percussive.

### sd (snare drum) — MIDI 38

```
Noise
→ Biquad(BPF, cutoff=800.0, q=2.0)
→ ADSR(attack=0.001, decay=0.08, sustain=0.0, release=0.05)
→ Gain(_, 1.0)
→ Output(_)
```

Bandpass-filtered noise for a snappy character.

### hh (hi-hat) — MIDI 42

```
Noise
→ Biquad(HPF, cutoff=8000.0, q=1.0)
→ ADSR(attack=0.001, decay=0.03, sustain=0.0, release=0.02)
→ Gain(_, 1.0)
→ Output(_)
```

High-pass filtered noise, very short — metallic tick.

### default (pitched synth)

```
Oscillator(Sine, 440.0)
→ ADSR(attack=0.01, decay=0.1, sustain=0.7, release=0.3)
→ Gain(_, 1.0)
→ Output(_)
```

Current template, used for `note()` events. Frequency set via control binding on "note" key (midi_to_hz conversion in ControlMapper).

## 6. Multi-Pool Voice Routing

Lives entirely in `browser/browser_scheduler.mbt`. No changes to `scheduler/` package.

### Pool registry

```
pools: Map[String, (VoicePool, ControlBindingMap, PatternScheduler)]
  "bd"      → (pool_bd,  bindings_bd,  sched_bd)
  "sd"      → (pool_sd,  bindings_sd,  sched_sd)
  "hh"      → (pool_hh,  bindings_hh,  sched_hh)
  "default" → (pool_syn, bindings_syn, sched_syn)
```

Each pool has 4 voices (32 total across all pools). Each scheduler shares the same BPM.

### Pattern splitting

On receiving parsed `Pat[ControlMap]`:

```
pat_bd  = parsed.filter_map(keep_sound(36.0))
pat_sd  = parsed.filter_map(keep_sound(38.0))
pat_hh  = parsed.filter_map(keep_sound(42.0))
pat_syn = parsed.filter_map(keep_note)
```

Where `keep_sound(n)` keeps events with `{"sound": n}` and `keep_note` keeps events with a `"note"` key.

### Process flow per block

```
1. For each (name, pool, scheduler) in pools:
     scheduler.process_block(sub_pattern[name], pool, tmp_left, tmp_right)
     accumulate tmp_left/tmp_right into main left/right buffers
2. Apply master gain
3. Output
```

Temporary buffers are pre-allocated (no audio-thread allocation).

### BPM propagation

`set_scheduler_bpm(bpm)` iterates ALL schedulers and calls `set_bpm` on each. Same for gain.

### Timing synchronization

All schedulers are created together in `init_scheduler_graph`. They start at sample counter 0 and advance together (called in sequence within the same process block). Timing stays perfectly synchronized.

## 7. Browser Wiring

### Parsing location

Inside the AudioWorklet wasm instance. Main thread sends raw text, worklet parses and updates the active pattern. Parsing runs once on user input, not per audio block.

### Exported functions (browser/ package)

- `parse_and_set_pattern(text: String) -> String` — calls mini/ parser. On success, updates sub-patterns and returns empty string. On failure, returns error message and keeps old pattern.
- `init_scheduler_graph(sample_rate, block_size) -> Bool` — creates all pools and schedulers.
- `process_scheduler_block() -> Bool` — renders one block across all pools.
- `set_scheduler_bpm(bpm)` — propagates to all schedulers.
- `set_scheduler_gain(gain)` — sets master gain.

### postMessage protocol

```
// Main thread → Worklet
{ type: "set-pattern-text", text: "s(\"bd sd hh sd\").fast(2)" }

// Worklet → Main thread
{ type: "pattern-updated" }
{ type: "pattern-error", message: "unknown sound name: snare (at position 3)" }
```

### processor.js changes

Handle `set-pattern-text` message: call wasm `parse_and_set_pattern`, post result back. Remove hardcoded pattern index messages (`set-scheduler-pattern`).

## 8. UI Changes

Replace hardcoded pattern buttons in `web/index.html` scheduler controls with:

```
┌─────────────────────────────────────────────────┐
│  s("bd sd hh sd").fast(2)                  [▶]  │
├─────────────────────────────────────────────────┤
│  Pattern updated                                │
└─────────────────────────────────────────────────┘
│  BPM: ───●────────── 120                        │
│  Gain: ──●────────── 0.30                       │
└─────────────────────────────────────────────────┘
```

- Text input with default value `s("bd sd hh sd").fast(2)`
- Eval on Enter keypress or button click
- Status line below: green on success, red with error message on failure
- BPM and gain sliders remain
- Page title updates to "MoonBit DSP — Pattern Sequencer"

## 9. Non-Goals

- No incremental reparsing (full reparse each eval — Phase 6)
- No sample playback (all sounds are synthesized)
- No euclidean rhythms (`"bd(3,8)"`), randomness (`"bd?"`), or polymeter
- No structural editor integration (Phase 7 / canopy option B)
- No pitch envelope on drums (bd is a static 60Hz sine, not a swept tone)
- No per-sound parameter control (e.g., `s("bd").cutoff(200)`) — defer to later

## 10. Testing Strategy

### mini/ package (parser tests)

- Parse `s("bd sd hh sd")` → verify Pat produces correct events with sound keys
- Parse `note("60 64 67")` → verify note keys
- Parse method chains: `.fast(2)`, `.slow(2)`, `.rev()`
- Parse sub-groups: `s("bd [sd hh]")`
- Parse stacks: `s("bd sd, hh hh hh")`
- Reject invalid input: empty string, unknown names in `s()`, numbers in `s()`, names in `note()`, `fast(0)`, `fast(-1)`
- Verify error messages include position information

### pattern/ (filter_map tests)

- filter_map preserves matching events with correct timing
- filter_map removes non-matching events
- filter_map on empty pattern returns empty
- filter_map on pattern where all events match returns equivalent pattern

### browser/ (integration, manual verification)

- Build wasm, serve web/, type success metric pattern, hear drum beat
- Verify BPM slider affects all sounds
- Verify parse error keeps old pattern playing
- Verify switching between `s()` and `note()` patterns
- Verify gain slider works

## 11. Implementation Order

1. Verify loom compiles to wasm-gc (risk gate)
2. Add path dependencies (loom, seam) to moon.mod.json
3. Implement `Pat::filter_map` in pattern/
4. Implement mini/ parser (token, lexer, grammar, fold)
5. Implement drum templates and multi-pool routing in browser/
6. Update web/index.html and processor.js
7. End-to-end test in browser
