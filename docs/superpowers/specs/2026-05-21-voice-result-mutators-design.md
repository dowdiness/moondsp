# Voice Result Mutators

**Date:** 2026-05-21
**Status:** Draft design
**Tracker:** follow-on from ADR-0010 result-surface hardening

## Context

ADR-0010 moved `VoicePool::new` and `VoicePool::set_template` onto
`Result`-typed construction and template replacement, but a few voice mutation
APIs still report rejection as `Bool`:

- `VoicePool::note_off(handle) -> Bool`
- `VoicePool::set_voice_pan(handle, pan) -> Bool`
- `BoundVoicePool::note_off(handle) -> Bool`
- `BoundVoicePool::kill(handle) -> Bool`
- `BoundVoicePool::set_voice_pan(handle, pan) -> Bool`

The voice package already has the right error type for this class:
`VoiceControlError::InvalidVoiceHandle(handle)` represents stale, out-of-range,
idle, or otherwise unusable handles, and `VoiceControlError::Graph(...)`
represents graph-control rejection for live controls. The live-control APIs
already use this type through `apply_voice_control_result` and
`apply_voice_controls_result`.

This slice should make the handle-mutating voice operations observable without
starting the larger breaking rename/removal pass.

## Decision

Add result-returning peers for the existing voice handle mutators:

- `VoicePool::note_off_result(handle) -> Result[Unit, VoiceControlError]`
- `VoicePool::set_voice_pan_result(handle, pan) -> Result[Unit, VoiceControlError]`
- `BoundVoicePool::note_off_result(handle) -> Result[Unit, VoiceControlError]`
- `BoundVoicePool::kill_result(handle) -> Result[Unit, VoiceControlError]`
- `BoundVoicePool::set_voice_pan_result(handle, pan) -> Result[Unit, VoiceControlError]`

For this first additive slice, keep the existing `Bool` APIs and route them
through the new result APIs. `true` means `Ok(())`; `false` means any `Err`.
This preserves current callers while giving new code a typed path.

Do not rename the existing live-control `*_result` methods in this slice.
The graph package already uses unsuffixed `Result` methods, but `voice/` still
has mixed compatibility surface. Removing `Bool` wrappers or renaming methods
should be a separate semver-minor or semver-major API cleanup once callers have
a migration window.

## Error Semantics

All stale or unusable handle cases return:

```moonbit
Err(VoiceControlError::InvalidVoiceHandle(handle))
```

For `note_off_result` and `kill_result`, this includes:

- handle slot out of bounds
- generation mismatch after voice stealing
- the slot is already idle
- the slot no longer has a compiled voice

For `set_voice_pan_result`, preserve the existing `set_voice_pan` validity
rule: a generation-valid handle may update the slot's cached pan gains even if
the slot is currently idle. Only out-of-bounds or generation-mismatched handles
return `InvalidVoiceHandle`.

The result APIs should not partially mutate on error:

- failed `note_off_result` leaves the pool unchanged
- failed `kill_result` leaves the pool unchanged
- failed `set_voice_pan_result` leaves the pool unchanged

Successful operations keep existing behavior:

- `note_off_result` gates ADSRs off using the per-slot
  `adsr_authoring_indices_snapshot` captured at `note_on` time and moves the
  slot to `Releasing`
- `kill_result` clears the compiled voice and moves the slot to `Idle`
- `set_voice_pan_result` clamps pan through the existing `VoiceSlot::update_pan`
  helper and updates cached equal-power gains

## Out Of Scope

- `VoicePool::note_on(...) -> VoiceHandle?` migration. That needs either a new
  `VoiceNoteOnError` or the later `CompiledDsp::compile -> Result` migration.
- `CompiledDsp::compile(CompiledTemplate, DspContext) -> Result[...]`.
- Removing the existing `Bool` wrappers.
- Renaming `apply_voice_control_result`, `apply_voice_controls_result`, or
  `validate_voice_controls_result`.
- Browser wasm ABI changes. Browser-facing helpers intentionally keep Bool
  returns at the JS boundary.

## Public API Impact

This is an additive public API change in `voice/` and therefore also through
the root `@moondsp` facade's re-exported `BoundVoicePool`, `VoicePool`, and
`VoiceControlError` types. `moon info` should show only the new result methods
in `voice/pkg.generated.mbti`.

The changelog should describe this as a new typed failure path, not a breaking
change.

## Tests

Add focused tests in `voice/voice_test.mbt`:

- `VoicePool::note_off_result` returns `Ok(())` and moves an active voice to
  `Releasing`
- stale `VoicePool::note_off_result` returns
  `Err(VoiceControlError::InvalidVoiceHandle(handle))`
- stale `VoicePool::set_voice_pan_result` returns
  `Err(VoiceControlError::InvalidVoiceHandle(handle))`
- `BoundVoicePool::kill_result` returns `Ok(())` and moves an active voice to
  `Idle`
- stale `BoundVoicePool::kill_result` returns
  `Err(VoiceControlError::InvalidVoiceHandle(handle))`
- `BoundVoicePool::set_voice_pan_result` keeps the current pan behavior on
  success and reports stale handles as typed errors
- existing `Bool` wrappers still return the old true/false values

## Verification

Implementation should run:

```bash
rtk moon check
rtk moon test -p dowdiness/moondsp/voice
rtk moon fmt
rtk moon info
rtk moon test
```

Known repository warning debt: `rtk moon check` may still report the eight
upstream quickcheck `Show` vs `Debug` deprecation warnings. This slice should
not add new warnings.
