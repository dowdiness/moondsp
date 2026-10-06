# Performance findings

Keep decision-bearing results here, not a file per benchmark run. These summaries preserve measured comparisons, rejected approaches and important limits; they are not current whole-engine or hard-real-time guarantees.

| Summary | Use it for |
|---|---|
| [Pattern allocation and onset investigations](2026-10-02-pattern-allocation-summary.md) | Adopted allocation reductions, the comparison baselines, rejected constructor caching, exact PCM/origin checks and profiler-attribution corrections. |
| [Playback and source origins](2026-09-24-playback-and-origin-summary.md) | Player/admission bounds, measured control latency, source-identity experiments and visualization evidence limits. |
| [DSP, graph controls and external authoring](2026-09-20-dsp-and-authoring-summary.md) | Sine scratch allocation, control-update costs, constant-fold barriers, delay-line reset and authoring baselines. |

## What to retain

- A result that changes an implementation or acceptance decision, with its source baseline, workload, target/toolchain, method and limitations.
- A failed approach or measurement correction that prevents repeating the same mistake.
- A useful regression baseline, not every full-suite timing dump. Preserve comparable numbers; do not claim speedups from uncontrolled shared-workstation runs.

Summarize overlapping investigations by topic. Prefer extending a concise summary with a clearly dated comparison over adding separate reports, JSON copies and logs for each iteration. New experiments still need an isolated benchmark and exercised behavior before claiming an improvement.

## What was removed

The 2026-10-03 consolidation removed the original report/result files, repetitive benchmark dumps and local reproduction archives after summarizing their useful findings. Version-controlled originals are recoverable from the [pre-consolidation snapshot](https://github.com/dowdiness/moondsp/tree/5a8e495e5ba3524ebe856643fd0526eff3440430/docs/performance). Untracked onset evidence was intentionally deleted from this working tree without creating a backup or uploading it elsewhere.

This reduces the checkout, not existing Git history. The summaries do not promise local replay of deleted profiles/binaries. Reproducing a historical experiment requires its actual inputs from Git history where available, or a new documented measurement. Keep raw data during active investigations; retain it afterward only when its replay value justifies the storage and an explicit storage decision has been made.
