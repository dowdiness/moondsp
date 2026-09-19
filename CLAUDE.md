# moondsp — MoonBit DSP Audio Engine

`moondsp` is a live-codable, portable DSP audio and pattern engine written in MoonBit. The browser path is complete; the native CLAP path is a prototype, not DAW-ready.

## Non-negotiable boundaries

- Compile DSP graphs; do not interpret them on the render path.
- **No audio-thread allocation: pre-allocated buffers only.**
- Keep CLAP C ABI details in `clap_plugin/`, primitive handles in `clap_host/`, synth state in `clap_engine/`, and reusable DSP below them.
- Do not let CLAP host/plugin details leak into graph, voice, pattern, scheduler, or browser packages.
- Never call the CLAP prototype DAW-ready without stable bridge symbols, a real host/DAW load, and an audio-thread allocation audit.
- `Array[DspNode]` is the authoring exchange type; `CompiledTemplate` is the runtime exchange type. The canonical crossing is `CompiledTemplate::analyze`. See ADR-0010 and `scripts/check-public-boundary.sh` when changing this boundary.
- Code is the implementation source of truth. `docs/technical-reference.md` is authoritative for the documented graph runtime-control contract.

## Working policy

- Continue until the requested done criteria are met or a real blocker is reached. Do not stop for ordinary implementation choices.
- Safe local checks may run without asking. Fix failures caused by the requested change and rerun the affected checks.
- Ask only when missing credentials or access block progress, source requirements genuinely conflict, or an action exceeds the approved task scope or granted permissions. This includes unapproved destructive actions and public API or architecture changes; changes explicitly requested by the user may proceed.
- Read public documentation and public source code needed for the task without separate approval. Do not send private repository data or secrets to external services without authorization. Commit, push, publish, or change external state only when authorized.
- Prefer the smallest change that satisfies the goal. Do not add a broad skill or preload unrelated documentation.
- Use `moon ide` for MoonBit symbol definitions, references, outlines, and API discovery. Use text search for non-MoonBit files and stylistic checks.

## Commands and verification

Prefix every direct Moon command with `NEW_MOON_MOD=0`; this prevents the experimental manifest migration from modifying the hand-maintained manifests. Wrapper scripts already handle their own invocation.

Choose checks by the changed surface instead of running every command for every task:

```bash
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test path/to/affected_test.mbt
NEW_MOON_MOD=0 moon test
NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon build --target wasm-gc
scripts/smoke-clap-prototype.sh
```

- MoonBit behavior changes: check coherent changes with `NEW_MOON_MOD=0 moon check` and run the affected test file or package, including sibling tests; use the full suite when shared behavior or public APIs change. Fix failures before building on the change, not by running checks after every individual file edit.
- Public API changes: run `NEW_MOON_MOD=0 moon info` and inspect `.mbti` diffs. Before committing MoonBit source changes, run `NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt`; investigate unexpected generated changes.
- Browser changes: build the relevant target and exercise the actual browser surface when available.
- CLAP/native changes: use the relevant build, smoke, validator, host-load, and allocation evidence; validator success alone is insufficient.
- Performance changes: reproduce the claimed bottleneck with an isolated benchmark before changing the implementation, then save a dated record under `docs/performance/`.
- Documentation/configuration-only changes: validate the changed format and links; do not run MoonBit tests solely because prose changed.

## Read when relevant

| Task | Read or run |
|---|---|
| Writing or reviewing MoonBit | `docs/moonbit-base.md` |
| Graph runtime-control | `docs/technical-reference.md` and the applicable graph ADR |
| Editor, Song, Update, identity, or playback-origin semantics | `CONTEXT.md` and the applicable ADR |
| Browser ABI or AudioWorklet lifecycle | `docs/browser-api-contract.md` |
| Mini notation or DSL lowering | `docs/mini-notation.md` and the applicable boundary document |
| CLAP/native ABI | `docs/clap-plugin-guide.md` and relevant `docs/development/` evidence |
| Architecture rationale | `docs/decisions/`; use `docs/archive/` only for explicit historical work |
| Package/API discovery | `moon ide outline <path>`; use `scripts/package-overview.sh` only for broad package work |
| Task prompt authoring | `TASK_TEMPLATE.md` |

`docs/README.md` is the documentation router. Do not read the entire documentation tree by default. The archive contains completed work and is not an active source of truth.
