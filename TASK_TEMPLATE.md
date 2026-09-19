# Task Template

Use this template for autonomous work that has a concrete outcome. Give the agent the sources and checks relevant to this task; do not list every repository document by default.

```md
Goal:
<One concrete, testable outcome.>

Read when relevant:
- <primary issue, spec, or source-of-truth document>
- <additional document only if this task crosses that boundary>

Done when:
- <observable result 1>
- <observable result 2>
- <verification result or artifact>

Boundaries:
- In scope: <files, package, or behavior>
- Out of scope: <unrelated refactors or behavior>
- Preserve existing public APIs, layer boundaries, and performance constraints unless the goal explicitly changes them.

Autonomy:
- Continue until the done criteria are met or a real blocker is reached.
- Make ordinary implementation choices without asking for approval.
- Run safe local checks, fix failures caused by this task, and rerun the affected checks.
- Ask only when missing credentials or access block progress, source requirements genuinely conflict, or an action exceeds the approved task scope or granted permissions. This includes unapproved destructive actions and public API or architecture changes; changes explicitly requested by the user may proceed.
- Prefer the simplest low-risk approach and the repository's existing patterns.

Verification:
- Follow CLAUDE.md, “Commands and verification,” for repository check scope and command policy.
- Run: <task-specific commands or scenarios, with expected results>
- If a check fails, fix what is feasible and report any remaining failure with its evidence.

External actions:
- Commit: <only if requested by this task>
- Read public documentation and public source code needed for this task without separate approval.
- Push, publish, change external state, or send private repository data to external services: <only within explicit authorization>

Final report:
- What changed
- Verification results
- Remaining risks or blockers
- Recommended next step
```

## Selecting verification

[Commands and verification](CLAUDE.md#commands-and-verification) is the canonical repository policy. Fill the template's verification field with concrete checks and expected outcomes for the changed surface, rather than copying a second policy table here.

For MoonBit test-file selection, snapshot updates, and proof-enabled packages, use the [MoonBit testing cautions](docs/moonbit-base.md#testing). Use [the documentation router](docs/README.md#read-when-changing) for browser, native, and other task-specific contracts.

## Repository boundaries worth repeating in implementation tasks

- **No audio-thread allocation: pre-allocated buffers only.**
- Keep CLAP ABI details at the outer boundary; do not leak them into reusable DSP, graph, voice, pattern, scheduler, or browser packages.
- `docs/technical-reference.md` is authoritative for the documented graph runtime-control contract. Code remains the implementation source of truth.
- Read `docs/moonbit-base.md` for MoonBit syntax and package conventions, `CONTEXT.md` for editor/Song/playback vocabulary, and the relevant document in `docs/README.md` for other task-specific contracts.
