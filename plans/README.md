# Implementation Plans

These plans are self-contained execution guides for contributors who are new to the affected code. Read a plan completely, run its drift check, follow its steps in order, and honor its STOP conditions.

## Execution order and status

| Plan | Title | Priority | Effort | Depends on | Status |
|---|---|---|---|---|---|
| 001 | Add owned audio power lifecycle | P1 | L | — | DONE |

Status values: TODO | IN PROGRESS | DONE | BLOCKED (with one-line reason) | REJECTED (with one-line rationale)

## Plan 001 contract

Plan 001 adds an opt-in `@moondsp/browser/audio` entry point for applications that want the package to own a realtime `AudioContext` and `GraphEngine` through repeated power cycles.

Its payload-carrying lifecycle states, centralized async liveness arbitration,
retirement tail, cleanup order, and failure precedence are implemented in the
existing JS-target MoonBit host module. Handwritten JavaScript remains only as
the Web Audio/GraphEngine effect adapter and npm-facing facade.

Public domain types:

- `AudioPower`: application-scoped owner of power-cycle sequencing;
- `PoweredAudio<Value>`: one generation-scoped handle for readiness, resume,
  retirement, and terminal observation;
- `AudioSetup`: suspended-context setup inputs; and
- `AudioEnd`: clean turn-off or failure result.

The plan preserves the root `GraphEngine` interface for caller-owned contexts, offline rendering, and custom destinations. It does not add application UI state, retry policy, note/control serialization, framework adapters, or a global singleton.

Execute: [`001-official-audio-power-ownership.md`](001-official-audio-power-ownership.md).
