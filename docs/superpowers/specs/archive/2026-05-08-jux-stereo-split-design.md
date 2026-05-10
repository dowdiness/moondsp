# `.jux(f)` — Strudel-style stereo split

**Date:** 2026-05-08
**Status:** Shipped; archived after implementation landed on `main`
**Phase:** Phase B — Strudel mini-notation extensions (the deferred
companion to PRs #15–#17)

**Prerequisite (resolved 2026-05-08):** PRs #15, #18 (replaced #16),
and #17 are now merged on `main`. The shared `Callback` grammar this
spec relies on is the rename of PR #17's `EveryCallback` /
`parse_every_callback` / `make_every_*` symbols. This prerequisite note is
preserved as historical context.

## Goal

Add a `.jux(f)` combinator to the moondsp pattern language so users can
write:

```
s("bd sd hh sd").jux(rev)
```

and hear the original pattern in the **left** channel, `f(original)` in
the **right** channel, both running concurrently with hard pan ±1.

## Why this is small

The brief flagged `.jux` as needing "stereo voice routing" — but the
routing already exists. Today's pipeline:

- `pattern/control.mbt` has `s_pan` and a `merge_control` that does
  last-wins ControlMap merging.
- `scheduler/scheduler.mbt` has `default_control_mapper` which extracts
  `pan` keys and emits `SetPan(v)` voice actions.
- `voice/voice.mbt` has `VoiceSlot::update_pan` clamping to `[-1, 1]`
  and computing `pan_left_gain` / `pan_right_gain`.
- `browser/slot.mbt` has `StereoOut` writing two `AudioBuffer`s.

So `.jux` is purely a *pattern-layer* combinator: split the pattern in
two, override `pan` on each half, stack them. No DSP, no voice, no
worklet, no scheduler changes.

## Design

### Combinator

Add to `pattern/control.mbt` (next to `merge_control` — it is
`ControlMap`-specific and not generic over `A`):

```moonbit
pub fn Pat::jux(
  self : Pat[ControlMap],
  f : (Pat[ControlMap]) -> Pat[ControlMap],
) -> Pat[ControlMap] {
  let left  = merge_control(self,    Pat::pure(single_control("pan", -1.0)))
  let right = merge_control(f(self), Pat::pure(single_control("pan",  1.0)))
  stack([left, right])
}
```

`merge_control(a, b)` does last-wins on overlapping events, so any
pre-existing `pan` in the input is overridden — matching Strudel's
unconditional behaviour.

### Parser

PR #17 introduced a fixed-grammar callback for `.every(n, f)`:

```
EveryCallback = (Pat[ControlMap]) -> Pat[ControlMap]
parse_every_callback :: Parser × method_start × name → EveryCallback
```

with arms for `fast(N) | slow(N) | rev[()]`.

Rename to `Callback` / `parse_callback` / `make_*` so the same grammar
is shared between `.every` and `.jux`. Add a `"jux"` arm in
`parse_method`:

```
"jux" => {
  expect '(' ; skip_ws ; let name = read_ident()
  let f = self.parse_callback(method_start, name, calling_method="jux")
  skip_ws ; expect ')'
  pat.jux(f)
}
```

**Error-message threading:** PR #17's callback error reads
`"position N: every() callback must be fast(N), slow(N), or rev; got 'X'"`.
After sharing between `.every` and `.jux`, the literal `every()` is
wrong for `.jux(weird)`. Thread the caller's method name through:

```moonbit
fn parse_callback(
  self, method_start, name,
  calling_method~ : String,
) -> Callback raise ParseError
```

Both call sites pass `"every"` or `"jux"`; the error string interpolates
that name. This is the load-bearing nuance of the rename — easy to
miss, and parser test #6 should assert the error mentions `jux()` so
the regression is locked in.

No new tokens, no new grammar — just a second consumer of the shared
`Callback` parser. Grammar comment updates accordingly.

### Mini-notation surface

The mini docstring (`mini/mini.mbt`) gains one bullet under method
chains:

> `.jux(fast(k)|slow(k)|rev)` — split stereo, apply f to right channel

### Live demo

`web/live/src/main.ts` initial pattern updates to exercise `.jux`:

```
s("bd(3,8), hh*16?, sd(2,8,2)").jux(rev)
```

Smoke test in `web/live/tests/smoke.spec.ts` keeps `INITIAL_PATTERN` in
sync.

## Tests

All in MoonBit (`pattern/control_test.mbt` and `mini/mini_test.mbt`):

1. **`jux(rev)` event count and pan keys** — `s("bd sd").jux(rev)`
   produces 4 events; assert two have `pan=-1`, two have `pan=1`.
2. **Channel identity** — for `jux(rev)`, the `pan=-1` events match
   `self.query(arc)` exactly (same parts, same non-pan keys), and the
   `pan=1` events match `f(self).query(arc)` exactly. This pins the
   convention down to "left=original, right=f(original)" and rejects
   a channel-swapped implementation that would still pass a weaker
   "the two sides differ" assertion.
3. **`jux` overrides pre-existing pan** — `merge_control(pat,
   pure(pan=0.5)).jux(rev)` still produces only ±1 pan values.
4. **`jux(fast(2))` doubles the right channel** — 2-event input → 6
   events out (2 left + 4 right).
5. **Parser: `s("bd sd").jux(rev)` parses, event count 4.**
6. **Parser: `s("bd").jux(weird)` errors** with a `ParseError` whose
   message contains `"jux()"` (not `"every()"`) — locks in the
   error-message threading from the parser section above.
7. **Parser smoke: `note("60 64").jux(rev)` parses** (covers non-`s`
   primary).
8. **Scheduler-level stereo proof** (in `scheduler/scheduler_test.mbt`)
   — uses `make_test_sched()` which already returns left/right
   `AudioBuffer`s. Schedule a single event with `pan=-1` (hard left),
   call `sched.process_block(...)`, then assert
   `sum(|left.as_fixed_array()|) > epsilon` and
   `sum(|right.as_fixed_array()|) < epsilon`.
   Mirror with a second test for `pan=+1`. This proves stereo routing
   actually flips end-to-end without exposing the private
   `pan_left_gain` / `pan_right_gain` fields on `priv struct VoiceSlot`.
   The existing scheduler pan test only proves a voice was *created*.

   **Why not "two simultaneous opposite-pan events":** if both fire
   the same DSP template, left and right buffers end up with identical
   magnitudes (each carries one event's signal), defeating the
   asymmetry assertion. The single-event-per-test shape is sharper.

   Counts as **two test cases** in the test count below (one per
   direction) — total new tests is therefore 9, not 8.

## Out of scope

- `.juxBy(width, f)` — the parameterized-width sibling. YAGNI for now;
  hard-pan is what users reach for first. Add later if asked. (See
  brainstorm 2026-05-08 for the explicit decision.)
- Per-voice DSP differences (left and right channels each get the same
  voice template). Strudel's `.juxBy` doesn't change voice routing
  either; both sides go through the same scheduler.
- Multi-channel (>2) variants like `.jux4`. Not on the Phase B menu.

## Risks and gotchas

- **Pan override semantics surprise:** users who set `.pan(0.5)` then
  `.jux(rev)` lose the 0.5 — this is Strudel-correct but worth one
  test (item 3 above) so the contract is locked in.
- **Voice pool capacity — situational, not universal:** `.jux` does
  *not* always double per-pool concurrency. For `.jux(rev)` on a
  pattern with distinct per-slot sounds (e.g. `s("bd sd hh sd")`),
  left and right channels fire different sounds at any given instant
  — bd-pool sees 1 simultaneous event, not 2. The doubling only
  manifests when `f` causes same-sound coincidence: `.jux(fast(2))`
  packs the right channel denser, and `.jux(rev)` over a single-sound
  layer like the demo's `hh*16?` puts left's hh at slot t and right's
  hh at slot 1−t — frequent coincidence at fine subdivisions.
  The browser demo today (`browser/browser_scheduler.mbt`) configures
  three drum pools — `bd`, `sd`, `hh` — each at `max_voices=4`, and
  one synth pool at `max_voices=8`. The steal policy is "oldest active
  note", so a saturated pool under `.jux` can cut a `.jux` sibling
  rather than an unrelated older note. Audible result: collapsed
  stereo on dense layers, not a graceful fade.
  Mitigation **in this PR**: bump *all four* pool sizes — bd/sd/hh
  drum pools each 4→8, synth pool 8→16 — alongside the `.jux` rollout.
  Frame this in code comments as "defensive headroom for `.jux(f)`
  patterns where `f` causes same-sound overlap (e.g. the demo's
  `hh*16?` layer)", *not* as "all `.jux` doubles concurrency".
  Per-channel routing is *not* the right response — the issue is
  pool-size headroom, not topology. Out of this PR: a future
  `voice/voice.mbt` change to stabilise equal-onset stealing (so
  siblings of a `.jux` pair survive together) is a separate cleanup
  if the doubled headroom proves insufficient.
- **Parser callback grammar drift:** sharing `parse_callback` between
  `.every` and `.jux` means any future extension (e.g. accepting
  `degradeBy(p)` as a callback) automatically applies to both. That's
  desirable, but the rename is the single critical step that needs to
  land cleanly to keep PR 3's behavior identical.

## Acceptance criteria

- All nine new tests pass (test items 1–7, plus item 8's two
  directional cases); total test count rises by 9.
- `moon check && moon test` clean.
- `pattern/pkg.generated.mbti` shows the new `Pat::jux` export. (The
  combinator lives in the `pattern` package, not `mini` — the parser
  only adds a method-arm that calls it. The root `dowdiness/moondsp`
  facade does not re-export `pattern` APIs today, so no facade change
  is needed.)
- Browser demo pool sizes bumped — `browser/browser_scheduler.mbt`
  bd/sd/hh drum pools each 4→8 and synth pool 8→16, plus a brief
  note explaining the headroom is defensive for `.jux(f)` patterns
  with same-sound overlap.
- Live demo loads with the new pattern and produces audible stereo
  separation (left = original, right = reversed) when verified manually
  in browser.
- The `.every` parser tests from PR 3 still pass unchanged after the
  callback-grammar rename.
