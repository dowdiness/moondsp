# Performance Snapshot — 2026-06-10: Core-method adoption refactor

Style refactor replacing manual loops with core `Iter`/`Array`/`String`
methods across shipping packages (branch `refactor/core-method-adoption`).
Perf-relevant touch points: `pattern/combinators.mbt` `stack`/`filter_map`
query closures (`Array::append`, `Array::filter_map`), `bjorklund`
construction (`Array::makei`, view slicing, `flatten`), and
`mini/doc_parser.mbt` `doc_root_signature` (`map` + `join`). The `is_empty`
sweep is branch-equivalent and not perf-relevant.

## Verdict: no regression

Pattern-query rows moved DOWN vs the 2026-05-10 baseline while all mini-parse
rows (including `s_rev`/`s_fast`, which do not execute any refactored code)
moved UP by the same ~4–6% — a uniform machine-variance signature, not a
change signal.

## Numbers (`NEW_MOON_MOD=0 moon bench`, full workspace, 58/58 ok)

| Area | Case | Time | Prior (2026-05-10) |
|------|------|-----:|-------------------:|
| pattern query | rev_4step | 3.74 µs ± 71.6 ns | 3.86 µs |
| pattern query | fast_4step | 5.51 µs ± 167.1 ns | 5.72 µs |
| mini parse | s_rev | 0.71 µs ± 20.6 ns | 0.68 µs |
| mini parse | s_fast | 0.83 µs ± 9.9 ns | 0.78 µs |
| mini parse | stack_rev | 0.91 µs ± 15.9 ns | 0.86 µs |
| scheduler | process_events_8_jux_events | 18.12 µs ± 225.7 ns | — |
| scheduler | voicepool_process_8_panned_jux_voices | 39.46 µs ± 939.1 ns | — |
| scheduler | process_block_jux_rev | 12.87 µs ± 237.2 ns | — |
| voice | note_on minimal/fm/full | 237 ns / 671 ns / 967 ns | — |
| graph hotswap | branch_fanout_11_nodes | 226.45 ns ± 15.1 ns | — |
| graph hotswap | mix_bus_17_nodes | 214.34 ns ± 9.8 ns | — |
| graph hotswap | terminal_stereo_15_nodes | 398.94 ns ± 18.9 ns | — |
| graph hotswap | feedback_loop_6_nodes | 226.00 ns ± 13.4 ns | — |
