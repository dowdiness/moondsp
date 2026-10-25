# Browser updates: resolve at mount, send numeric batches

Measured 2026-10-23 in the Linux x64 orb with Node v26.12.1 and Moon
0.1.20260920 (914d7da), release wasm-gc. This compares the local named-JSON
update implementation before this change with the numeric implementation.
The baseline was uncommitted work in this thread, not `origin/main`.

## Isolated update cost

[`scripts/bench-browser-update.cjs`](../../scripts/bench-browser-update.cjs)
mounts a 375 Hz square oscillator → named gain → output at 48 kHz. It alternates
gain 0.1/0.2, warms up 10,000 calls, then measures seven rounds of 100,000 updates.
The final rendered sample is asserted to equal 0.2 for both implementations.

| Direct JS/Wasm path | First run median µs/update | Repeat median µs/update |
|---|---:|---:|
| JSON stringify, character transfer, decode, name resolution, apply | 1.080 | 1.129 |
| Begin fixed batch, push numeric binding/value, apply | 0.109 | 0.072 |

First-run observations, µs/update:

- JSON: 1.3214, 1.0677, 1.0096, 1.0573, 1.0802, 1.1652, 1.1574.
- Numeric: 0.2227, 0.1087, 0.0798, 0.0673, 0.1262, 0.0763, 0.1222.

This supports removing repeated JSON/name work from the receive path. It does
**not** measure public `sound.update()` latency, main-thread input capture,
MessagePort overhead, render throughput, GC pauses, or audible glitches. Runs
were sequential in a shared orb; treat the magnitude as workload-specific,
not a stable whole-engine speedup.

Reproduce the current path:

```sh
NEW_MOON_MOD=0 moon build browser --target wasm-gc --release
node scripts/bench-browser-update.cjs _build/wasm-gc/release/build/browser/browser.wasm numeric
```

The script's explicit `json` mode requires a matching pre-change Wasm artifact;
it is benchmark support, not a production compatibility path. Artifact SHA-256:

- Before: `523a311b1a2ebc18b8e979dab181346a4523ffee24d2fd56d076e1cdb3cb185a`
- After: `c21def18e7a0d7416b408592616c8eead5660a5bc07b12cd945cb96882eec7bf`

## Allocation boundary and correctness

Mounting owns target validation and compiled-index resolution. A 320-entry
numeric batch and each graph's staging buffers are preallocated. Updates no
longer construct JSON trees, control arrays, or control messages in MoonBit.
Overflow poisons the batch until cleared, preventing a truncated commit.

Initial release WAT inspection (`moon build ... --output-wat`) showed
`struct.new` for successful result wrappers in the then-public
`MountedGraph::update`. The follow-up below removes those wrappers.
MessagePort delivery and reply objects also allocate, and diagnostic errors
construct JSON. This is **not an allocation-free audio-thread implementation**;
an end-to-end allocation audit is still required. No SAB or object-pool
fallback is introduced here.

Engine tests cover rejected prefixes, capacity overflow/recovery, invalid
binding IDs/values, gate order, authoring-index diagnostics, and stale handles.
Browser PCM tests cover parameter fan-out, mount isolation, invalid atomic
updates, Unicode/special names, caller mutation, and getter/toJSON avoidance.

## Follow-up: simplify ownership and audit the transport

The input adapter now validates own data properties directly into numeric
commands, without a parameter/gate snapshot or prototype changes. The existing
45 graph-engine browser tests passed unchanged against this refactor.

A Chromium OfflineAudioContext probe queued 64 public `sound.update()` calls
before awaiting them. It observed 64 typed-array update messages (1,024 bytes
of command payload) and 64 acknowledgement objects; the resulting square-wave
sample was exactly 0.5, the final submitted gain. Counts were recorded before
the engine's response handler resolved promises, to avoid an observer-removal
race at the final acknowledgement. This measures protocol traffic, not heap
allocation bytes or GC pauses.

The probe ran with `crossOriginIsolated === false`, matching the current
standalone examples. A mandatory SharedArrayBuffer queue would change their
hosting requirements (COOP/COEP headers) and needs an explicit queue-capacity,
completion, and suspended-context contract. This change does not introduce a
second, fallback transport or silently require shared memory. MessagePort
delivery/replies remain outside the allocation-free claim.

## Entry-path release WAT inspection

Bindings now live in an internal `BoundDsp`, constructed and resolved before
registration. Numeric batch types and updates are absent from the normal
MoonBit facade; the unused raw-control JSON ABI has been removed.

The browser update and render adapters use nullable errors instead of raising
success wrappers. Inspection of the final release WAT found:

- Browser `graph_host_process` forwarding and implementation: no direct
  allocation instructions or `Result` references.
- Shared `Engine.process<BoundDsp>`: success returns `ref.null`; its only
  `struct.new` is the rejected buffer-size error. No `Result` references.
- `BoundDsp.update`: no `Result` references; three `struct.new` sites construct
  invalid parameter, gate, or binding errors only.

This is an entry-path audit, not proof about every transitive DSP call or the
JavaScript transport. Full MoonBit tests passed (1,309); Chromium graph,
lifetime, and audio-power tests passed (70), including actual PCM assertions.

## 2026-10-25: transitive allocation audit

Counting executed GC construction instructions found what the entry-path
inspection missed: each biquad coefficient update called core `sin` and `cos`,
each constructing an array and its wrapper. Coefficients are recalculated on
render even without an application update. Reuse the existing scalar bounded
argument reduction for both sine and cosine; do not add a coefficient cache.
Other targets keep their core math implementations. Finite input multiplication
overflow still disables the filter, as before.

Rejected updates also formatted the MoonBit error through Debug and constructed
a JSON object/string. The host now exposes code, message, and node index as
primitive fields. Control messages are static categories; they no longer include
the rejected value or internal enum spelling. Public error codes and authoring
indices are unchanged. This is a breaking private Worklet ABI with no fallback.

### Executed construction counts, not estimated heap bytes

Moon 0.1.20260920, release wasm-gc, Node 26.12.1, Linux x64 orb.
Each case runs 200 warmup blocks, then 1,000 blocks at 48 kHz / 128 frames.
Six nodes: oscillator → biquad → multiply by ADSR → gain → output. Four oscillator
waveforms × three filter modes × four workloads give 48 cases. Every case in a
workload had the same count below. Initialization and mounting are excluded.

| Workload (one transaction per block where applicable) | Before | After |
|---|---:|---:|
| Continuous rendering | 4,000 | 0 |
| Pitch, cutoff, gain updates | 4,000 | 0 |
| Ordered gate off/on retriggers | 4,000 | 0 |
| Valid gain plus rejected sustain=1.5 | 252,011 | 1,001 |

The last count is one error value per rejected batch plus one first-use string
construction. Successful paths are zero **for these exercised Wasm workloads**.
Rejection is not allocation-free. JavaScript strings, Error objects, structured
cloning, acknowledgements, and browser-internal allocations are not counted.

All 6,144,000 output samples matched the pre-change binary byte-for-byte.
Rejected-update PCM also matched the no-update control. Instrumentation was
checked against uninstrumented output; mount counts served as a positive control.
The public Biquad regression covers 4,095 cutoffs plus neighboring floating-point
values around reduction boundaries, all three modes, and overflow rejection.

The instrumenter wraps every `struct.new*` / `array.new*` expression with a
per-function global counter. It counts executed instructions, not retained heap,
physical allocation bytes, GC pauses, or all possible graph workloads. Binaryen
125 first normalizes the binary to fully folded WAT. Its exact reference types
require an experimental Node flag for the **audit artifact only**, not production.

```sh
NEW_MOON_MOD=0 moon build browser --target wasm-gc --release
moon-wasm-opt _build/wasm-gc/release/build/browser/browser.wasm --all-features -S -o /tmp/folded.wat
python3 scripts/instrument-wasm-allocations.py /tmp/folded.wat /tmp/counted.wat
moon-wasm-opt /tmp/counted.wat --all-features -o /tmp/counted.wasm
node --experimental-wasm-custom-descriptors scripts/audit-browser-allocations.cjs /tmp/counted.wasm _build/wasm-gc/release/build/browser/browser.wasm
```

Before/after artifacts were local work, not `origin/main`; their SHA-256 values:

- Before: `a57b0936b491675420150f37930ea03ac73bbb915db611a27f82b42531b6efba`
- After: `6726b3a2910093aa9efcedbd164a971b3f4f0324eeb408cf9644c827ccda3650`

### Actual AudioWorklet timing, measured separately

Uninstrumented Chromium 145.0.7632.6; real AudioContext, 48 kHz / 128 frames,
2.666667 ms quantum. Each case uses a fresh context, two-second wall-clock
warmup, then 20 seconds of tracing. CDP categories:
`webaudio,disabled-by-default-audio-worklet`; durations come from
`AudioWorkletProcessor::Process (author script execution)` events.
Updates arrive every 10 ms without waiting for the preceding promise.

The six-node graph uses a sine, lowpass at 2 kHz / Q=.707, ADSR 2/20/.7/30 ms,
and gain .1. Parameters alternate pitch `220+(i%12)*20` and volume `.08+(i%3)*.01`;
gates submit off/on; rejected updates submit volume .2 and sustain 1.5.

| Case | Before p99 / max ms | After p99 / max ms | Before / after callbacks over quantum |
|---|---|---|---|
| Continuous | .054 / 3.011 | .045 / .276 | 1 / 0 |
| Parameters | .038 / .558 | .034 / .205 | 0 / 0 |
| Retriggers | .041 / .452 | .037 / .334 | 0 / 0 |
| Rejected | .044 / .411 | .043 / .105 | 0 / 0 |

After: 7,507 callbacks per case, p50 .007 ms throughout. Public update RTT p99
was .6 ms in all three update cases; maxima were 2.2 / 1.7 / 2.7 ms. There were
1,998 / 1,999 successful transactions and 2,000 expected `INVALID_CONTROL`
rejections. The last RTT exceeding a quantum is not a render deadline miss.

These single sequential runs in a shared virtualized orb do not establish a
speedup or hard-real-time guarantee. The original 3.011 ms callback had only
.051 ms trace thread time, consistent with preemption. A second original
browser-inclusive scope exceeded budget during retriggers (4.909 ms), while
the nested author callback took .023 ms. All after-run browser-inclusive
scopes were below the quantum, but late starts and hardware underruns were not
measured. Initial device startup also consumed much of the first case's warmup.
Message-handler CPU time was not isolated; public RTT includes both threads,
transport, and promise scheduling. No heap profile of MessagePort was performed.
