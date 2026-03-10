# Task Template

Use this template when you want Codex to work autonomously for a long stretch
without stopping for avoidable clarification.

## Copy-Paste Template

```md
Goal:
<One concrete outcome. Keep it singular and testable.>

Source of truth:
- AGENTS.md
- <primary spec or issue>
- <secondary doc if needed>

Success criteria:
- <measurable result 1>
- <measurable result 2>
- <verification result or artifact>

Non-goals:
- <explicitly out of scope item 1>
- <explicitly out of scope item 2>

Constraints:
- Preserve existing repo patterns unless there is a strong reason not to
- Prefer minimal, targeted diffs
- <any API, performance, compatibility, or style constraint>

Autonomy policy:
- Keep going until the success criteria are met or a real blocker is reached
- Do not stop for minor implementation choices
- Stop only for:
  - secrets, credentials, or external accounts
  - destructive actions not already requested
  - contradictory source documents
  - choices that materially change public API or architecture
- If multiple valid approaches exist, prefer <simplest / lowest-risk / fastest>

Verification:
- Run: <command 1>
- Run: <command 2>
- If a command fails, fix what is feasible and summarize the remaining issue

Artifacts:
- Update or create: <docs, snapshots, RESULTS.md, etc.>

Git:
- Commit when done with a sensible message
- <Do not push / Push when done>

Final report:
- What changed
- Verification results
- Remaining risks or unknowns
- Recommended next step
```

## Repo-Specific Default

Use this variant when the task is in this repository and you do not want to
rewrite the common parts every time.

```md
Goal:
<Concrete task in mdsp>

Source of truth:
- AGENTS.md
- docs/step0-instruction.md
- docs/salat-engine-blueprint.md
- <issue text or additional doc if relevant>

Success criteria:
- The requested implementation is complete
- `moon check` passes
- `moon test` passes, or any absence/failures are explained clearly
- Required docs or generated files are updated if needed

Non-goals:
- Unrelated refactors
- Style-only churn
- Expanding scope beyond the named task

Constraints:
- Follow MoonBit block style with `///|`
- Prefer explicit error handling when MoonBit shorthand is unclear
- Avoid allocation in audio-thread code
- Keep public API changes intentional and review `.mbti` diffs when applicable

Autonomy policy:
- Keep going without asking unless blocked by secrets, approvals, destructive
  actions, or conflicting instructions
- Prefer the simplest approach that satisfies the documented goal
- Use existing project structure and conventions instead of inventing new ones

Verification:
- Run `moon check`
- Run `moon test`
- Run `moon info` if public APIs may have changed
- Run `moon fmt` after edits

Artifacts:
- Update docs when behavior, workflow, or findings change
- Write `RESULTS.md` when the task is an experiment or platform validation

Git:
- Commit at the end with a sensible message
- Do not push unless explicitly asked

Final report:
- Brief summary of implementation
- Verification status
- Open risks, blockers, or follow-up work
```

## Good Prompt Example

```md
Read `docs/step0-instruction.md` and implement the minimal browser
AudioWorklet prototype in this repo.

Success criteria:
- MoonBit exports a `tick(freq, sample_rate)` sine oscillator
- `web/index.html` and `web/processor.js` exist
- `RESULTS.md` records what worked, what failed, and any wasm-gc findings
- `moon check` passes

Non-goals:
- No architecture refactor
- No extra DSP features
- No UI polish beyond what is needed for the demo

Autonomy policy:
- Keep going until complete
- Stop only if browser/manual interaction is required, network approval is
  needed, or the docs conflict

Git:
- Commit when done
- Do not push
```

## Practical Notes

- A strong long-running task starts with one primary goal, not a wishlist.
- Success criteria matter more than detailed implementation instructions.
- Non-goals prevent scope drift.
- If the repo depends on external services, make access and approval policy
  explicit up front.
- If you want checkpoints, say so explicitly, for example: "Commit at logical
  milestones and continue."
