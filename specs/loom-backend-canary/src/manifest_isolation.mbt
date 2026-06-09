// Phase 0 Check #4: manifest isolation. The authoritative enforcement is
// external — `scripts/check-public-boundary.sh` stays green and the
// `moon publish --dry-run` bundle for `dowdiness/moondsp` excludes everything
// under `specs/` and pulls no loom-stack file into a runtime-facing package.
//
// Code cannot enforce a manifest exclusion, so this file does NOT pretend to.
// It records the boundary invariants as data the canary test can assert on,
// keeping the intent auditable next to the probe rather than only in the report.

///|
/// The loom-stack dependencies this canary module is allowed to consume. They
/// must stay confined to this `specs/` module — none may appear in a
/// runtime-facing `dowdiness/moondsp` package's `moon.pkg`.
pub let loom_stack_deps : Array[String] = [
  "dowdiness/loom", "dowdiness/seam", "dowdiness/pretty", "dowdiness/incr", "dowdiness/text_change",
]

///|
/// Module boundary statement: this canary is a `specs/` leaf. Nothing under the
/// published `dowdiness/moondsp` bundle imports it, and it never publishes.
/// Verified externally by the dry-run bundle inspection (Check #4); recorded
/// here so the invariant lives beside the code it constrains.
pub let canary_module_name : String = "dowdiness/moondsp/loom-backend-canary"

///|
/// True iff every consumed loom-stack dep is namespaced under `dowdiness/`
/// (i.e. a path-dep'd sibling, never a `moonbitlang/x/*` native-FFI package).
/// A cheap structural restatement of the Check #2 invariant the build graph
/// proves authoritatively.
pub fn loom_stack_is_namespace_isolated() -> Bool {
  for dep in loom_stack_deps {
    if !dep.has_prefix("dowdiness/") {
      return false
    }
  }
  true
}
