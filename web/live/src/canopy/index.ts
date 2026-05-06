// Vendored from @canopy/editor-adapter@0.1.0-alpha.0 (canopy 9df029d).
// Do not edit — see ./README.md.
//
// Trimmed from upstream: only re-exports the surface moondsp consumes.
// Upstream additionally exports HTMLAdapter, PMAdapter, pmAdapterSchema,
// MarkdownPreview, BlockInput. Re-add here if/when needed.

export type {
  ViewNode,
  ViewPatch,
  UserIntent,
  Decoration,
  Diagnostic,
} from './types';

export type { EditorAdapter } from './adapter';

export { CM6Adapter } from './cm6-adapter';
