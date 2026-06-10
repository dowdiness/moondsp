# Performance Snapshot — 2026-06-10: Declarative loop sweep

Style refactor converting mut-push accumulator loops to `Array::map` /
`filter` / `filter_map`, `Iter::flat_map` + `collect`, comprehensions, and
array-literal spread across `pattern`, `song`, `graph` (authoring/compile),
`scheduler` (snapshot copies/projections), `mini` (one map site), and `voice`
(rare compaction collect) — branch `style/rewrite-preferences`. Perf-relevant
touch points: `pattern/pattern.mbt` `pure`/`fast`/`rev` query closures,
`pattern/control.mbt` `merge_control`, `pattern/combinators.mbt`
`stack`/`euclid`/`degrade_by`/`every`, and `pattern/pattern_doc.mbt` sourced
query closures. Parser state machines, insertion sorts, index-map-interleaved
optimizer loops, and the audio-thread note-on path were intentionally left
imperative. Baseline measured on the same machine in the same session by
stashing the diff and re-running.

## Verdict: no regression except one bounded, accepted delta

`rev_4step` (pattern query through `Pat::rev`, now an `Iter::flat_map` chain)
moved 3.78 µs → 3.94–4.06 µs across two after-runs (~+4–7%, ~+200 ns/query).
This is a control-rate scheduler-side query, not audio-thread work; the
absolute cost is negligible and accepted for the declarative form. All other
rows are inside run-to-run variance, and several graph compile/template rows
improved (e.g. `template_analyze` large_130 5.28 µs → 4.68 µs).

## Numbers (`NEW_MOON_MOD=0 moon bench`, full workspace, 58/58 ok)

| Area | Case | Before (stash) | After |
|------|------|---------------:|------:|
| pattern query | rev_4step | 3.78 µs ± 45.9 ns | 4.06 µs ± 97.2 ns (rerun 3.94 µs ± 54.4 ns) |
| pattern query | fast_4step | 5.60 µs ± 120.0 ns | 5.80 µs ± 155.7 ns (rerun 5.69 µs ± 118.5 ns) |
| mini parse | s_rev | 0.71 µs ± 9.5 ns | 0.75 µs ± 14.7 ns |
| mini parse | s_fast | 0.85 µs ± 5.5 ns | 0.86 µs ± 10.5 ns |
| mini parse | stack_rev | 0.91 µs ± 8.4 ns | 0.90 µs ± 6.9 ns |
| scheduler | process_events_8_jux_events | 18.83 µs ± 393.3 ns | 18.80 µs ± 292.5 ns |
| scheduler | voicepool_process_8_panned_jux_voices | 38.53 µs ± 239.6 ns | 38.52 µs ± 337.2 ns |
| voice | note_on minimal/fm/full | 252 ns / 683 ns / 991 ns | 248 ns / 665 ns / 1020 ns |
| graph template | template_analyze large_130 | 5.28 µs ± 74.7 ns | 4.68 µs ± 62.3 ns |
| graph process | full_voice/128 | 5.81 µs ± 40.0 ns | 5.59 µs ± 36.7 ns |
| graph hotswap | minimal_voice/128 | 9.76 µs ± 54.2 ns | 9.80 µs ± 86.4 ns |
