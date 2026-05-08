# `.jux(f)` — Strudel-style stereo split

**Date:** 2026-05-08
**Phase:** Phase B — Strudel mini-notation extensions (the deferred
companion to PRs #15–#17)

**Prerequisite:** PR #17 must be merged first. This spec relies on the
shared `Callback` grammar (renamed from PR #17's `EveryCallback`) which
does not exist on `main` today. Implementation order is hard:
land #15 → #16 → #17 → this work.

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

Rename to `Callback` / `parse_callback` so the same grammar is shared
between `.every` and `.jux`. Add a `"jux"` arm in `parse_method`:

```
"jux" => {
  expect '(' ; let f = parse_callback(...) ; expect ')'
  pat.jux(f)
}
```

No new tokens, no new grammar — just a second consumer of the existing
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
6. **Parser: `s("bd").jux(weird)` errors** with a callback-name
   `ParseError`.
7. **Parser smoke: `note("60 64").jux(rev)` parses** (covers non-`s`
   primary).
8. **Scheduler-level stereo proof** (in `scheduler/scheduler_test.mbt`)
   — schedule two simultaneous events with opposite pans and assert
   the resulting voice slots have asymmetric `pan_left_gain` /
   `pan_right_gain`. The existing scheduler pan test only verifies a
   voice was created; this one proves stereo routing actually flips.

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
- **Voice pool capacity (sharper than I first thought):** `.jux`
  doubles the simultaneous event count *within the same per-sound
  pool*. The browser demo today configures only 4 voices for the drum
  pool and 8 for the synth pool (`browser/browser_scheduler.mbt`), and
  the steal policy is "oldest active note" — which under `.jux` can
  cut the left or right sibling of a stereo pair rather than an older
  unrelated note. Audible result: collapsed stereo on dense passages,
  not a graceful fade.
  Mitigation **in this PR**: bump the browser demo's drum pool to 8
  and synth pool to 16 alongside the `.jux` rollout. Document the
  doubling in the `Pat::jux` docstring. Per-channel routing is *not*
  the right response — the issue is pool-size headroom, not topology.
  Out of this PR: a future `voice/voice.mbt` change to stabilise
  equal-onset stealing (so siblings of a `.jux` pair survive together)
  is a separate cleanup if the doubled headroom proves insufficient.
- **Parser callback grammar drift:** sharing `parse_callback` between
  `.every` and `.jux` means any future extension (e.g. accepting
  `degradeBy(p)` as a callback) automatically applies to both. That's
  desirable, but the rename is the single critical step that needs to
  land cleanly to keep PR 3's behavior identical.

## Acceptance criteria

- All eight new tests pass; total test count rises by 8.
- `moon check && moon test` clean.
- `pattern/pkg.generated.mbti` shows the new `Pat::jux` export. (The
  combinator lives in the `pattern` package, not `mini` — the parser
  only adds a method-arm that calls it. The root `dowdiness/moondsp`
  facade does not re-export `pattern` APIs today, so no facade change
  is needed.)
- Browser demo pool sizes bumped — `browser/browser_scheduler.mbt`
  drum pool 4→8 and synth pool 8→16, plus a brief note in the
  module-level comment explaining the headroom is for `.jux`.
- Live demo loads with the new pattern and produces audible stereo
  separation (left = original, right = reversed) when verified manually
  in browser.
- The `.every` parser tests from PR 3 still pass unchanged after the
  callback-grammar rename.
