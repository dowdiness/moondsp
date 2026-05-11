# ADR-0005: Song sections as the long-form structure layer

- **Status:** Accepted
- **Date:** 2026-05-11
- **Source:** [PR #29](https://github.com/dowdiness/moondsp/pull/29) design discussion and implementation

## Context

The pattern engine already models musical time as query functions over
rational arcs. That works well for local pattern composition, but it does not
give a stable value for long-form song structure: named sections, section-local
timing context, and future operations like "replace the chorus counter-melody"
or "apply a bridge fill" need a layer above `Pat[A]`.

Putting this directly into `pattern/` would make a currently standalone package
responsible for song layout concerns. Putting it directly into `scheduler/`
would tie structure to DSP voice playback and make timeline/UI/collaboration
interpretations harder.

## Decision

Add a new `song/` package between `pattern/` and `scheduler/`.

The first accepted shape is:

- `TimeScope` — opaque section-local timing context, identity-only for now.
- `Section[A]` — named, length-bounded section that remains polymorphic in the
  payload type `A`.
- `SectionBody[A]` — either a single pattern or an ordered set of named layers.
- `SectionLayer[A]` — named layer wrapper around `Pat[A]`.
- `SectionPatch[A]` — small typed variation API for adding or replacing named
  layers.

`Section::body()` still returns a `Pat[A]` so existing scheduler integration can
consume a section without knowing whether its body is single-layer or layered.
Layered sections are lowered by stacking their ordered layers.

Core constructors use MoonBit struct-constructor syntax (`Section(...)`,
`SectionLayer(...)`, `TimeScope()`) rather than adding new `::new` methods.

## Consequences

**Positive**

- Long-form structure has a package boundary without contaminating the
  standalone `pattern/` layer or the DSP scheduler.
- `Section[A]` stays polymorphic, preserving room for UI timelines, analysis,
  serialization, and future non-DSP interpretations.
- Ordered layers make stacked playback deterministic while still giving names
  for variation and addressing.
- `SectionPatch[A]` gives the smallest useful variation primitive without
  introducing path strings or a song-layout model prematurely.

**Negative**

- `song/` now depends on `pattern/`, and `scheduler/` depends on `song/`, adding
  a new package edge to maintain.
- `SectionBody::Layers` is an ordered array rather than a map, so layer lookup
  is linear. This is acceptable at section-authoring scale, but it may need an
  index if sections grow many layers.
- `Section::body()` hides layer names by lowering to a stacked `Pat[A]`; code
  that cares about structure must use `section_body()` or layer-specific APIs.

**Deferred**

- Song layout, section occurrences, range addressing, boundary operations, and
  path parsing are deliberately not part of this decision. They require a
  separate model for references like `verse2.last(4)` and repeated choruses.
