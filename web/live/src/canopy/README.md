# Vendored: `@canopy/editor-adapter`

These files are a **vendor copy** of `@canopy/editor-adapter`, taken at:

- Repo: `dowdiness/canopy`
- Commit: `9df029d` (chore(editor-adapter): publish as 0.1.0-alpha.0)
- Path: `adapters/editor-adapter/`
- Version on copy: `0.1.0-alpha.0`

## Why vendor

Canopy's `editor-adapter` is pre-1.0 alpha and not yet published to npm.
For phase A of moondsp's live-coding surface, vendoring keeps moondsp
self-contained (no sibling-checkout requirement, no `file:` dep) while
still validating the protocol shape against a real second consumer.

## What's copied

Only the files moondsp actually consumes:

- `index.ts` — public re-exports (trimmed: see below)
- `adapter.ts` — `EditorAdapter` interface
- `types.ts` — wire-format types (`ViewPatch`, `UserIntent`, `Decoration`, `Diagnostic`, `ViewNode`)
- `cm6-adapter.ts` — CodeMirror 6 adapter

`pm-adapter.ts`, `html-adapter.ts`, `markdown-preview.ts`, `block-input.ts`
are **not** copied — moondsp doesn't use them.

## Trim from upstream `index.ts`

Upstream re-exports `HTMLAdapter`, `PMAdapter`, `pmAdapterSchema`,
`MarkdownPreview`, and `BlockInput`. The local `index.ts` only re-exports
`CM6Adapter` and the type surface. If a future moondsp need pulls in
ProseMirror or HTML adapters, copy the corresponding files here and
re-add their exports.

## Sync policy

Do **not** edit these files in moondsp. If a fix is needed, fix upstream
first, bump the commit pinned above, and re-vendor. The diff against
upstream should always be empty (modulo trimmed exports).

When `@canopy/editor-adapter` ships to npm, swap this directory for a
real dependency — no API changes required because we vendored against
the public surface only.
