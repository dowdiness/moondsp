///|
/// Experimental incr-backed authoring pipeline for mini notation.
///
/// Contract for the Phase 6+ design slice:
/// - The input text is the only mutable authoring signal.
/// - Parsing remains delegated to the handwritten PatternDoc parser and still
///   reparses the whole source string on each text change.
/// - Successful reparses pass the last successful PatternDoc to
///   `parse_doc_reusing`, preserving stable subtree IDs across edits.
/// - Parse errors are propagated as `Err(String)` and do not replace the last
///   reusable document.
/// - Lowering uses one persistent PatternLoweringCache owned by the pipeline,
///   so the current reuse win is stable-subtree and lowering-cache reuse after
///   parse, not token-level incremental parsing.
/// - Scope owns the long-lived cells, and persistent Observer handles anchor
///   the public parsed/snapshot reads for the pipeline lifetime.
/// - Compute counters are exposed for tests and diagnostics so callers can
///   distinguish whole-document recomputation from lowering-cache reuse.
///
/// This intentionally wraps `parse_doc_reusing` before introducing loom or a
/// token-level incremental parser. The runtime parser and PatternDoc parser
/// remain separate entry points for now.
pub struct MiniAuthoringPipeline {
  priv scope : @incr.Scope
  priv text : @incr.Signal[String]
  priv parsed_observer : @incr.Observer[
    Result[@pattern.PatternDoc[@pattern.ControlMap], String],
  ]
  priv snapshot_observer : @incr.Observer[
    Result[@pattern.PatternSnapshot[@pattern.ControlMap], String],
  ]
  priv token_count_observer : @incr.Observer[Int]
  priv lowering_cache : @pattern.PatternLoweringCache[@pattern.ControlMap]
  priv parse_compute_count_fn : () -> Int
  priv snapshot_compute_count_fn : () -> Int
}

///|
pub fn MiniAuthoringPipeline::new(input : String) -> MiniAuthoringPipeline {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let text = scope.signal(input, label="mini.text")
  let token_count = scope.memo(
    fn() {
      let tokens = tokenize_mini_authoring_source(text.get())
      ignore(mini_authoring_token_fingerprint(tokens))
      tokens.length()
    },
    label="mini.token_count",
  )
  let token_count_observer = scope.add_observer(token_count.observe())
  // Last successful parse is intentional mutable state: errors should surface
  // to callers without discarding the previous reusable PatternDoc.
  let mut previous : @pattern.PatternDoc[@pattern.ControlMap]? = None
  let mut parse_compute_count = 0
  let parsed = @incr.Memo::new_no_backdate(
    rt,
    fn() {
      parse_compute_count += 1
      let result = match previous {
        None => parse_doc(text.get())
        Some(doc) => parse_doc_reusing(text.get(), doc)
      }
      match result {
        Ok(doc) => {
          previous = Some(doc)
          Ok(doc)
        }
        Err(msg) => Err(msg)
      }
    },
    label="mini.parsed_doc",
  )
  scope.add_cell_ids([parsed.id()])
  let parsed_observer = scope.add_observer(parsed.observe())
  let lowering_cache : @pattern.PatternLoweringCache[@pattern.ControlMap] = @pattern.PatternLoweringCache::new()
  let mut snapshot_compute_count = 0
  let snapshot = @incr.Memo::new_no_backdate(
    rt,
    fn() {
      snapshot_compute_count += 1
      match parsed.get() {
        Err(msg) => Err(msg)
        Ok(doc) => {
          let result = try? doc.lower_with_cache(lowering_cache)
          match result {
            Ok(snapshot) => Ok(snapshot)
            Err(_) => Err("internal mini PatternDoc lowering failed")
          }
        }
      }
    },
    label="mini.snapshot",
  )
  scope.add_cell_ids([snapshot.id()])
  let snapshot_observer = scope.add_observer(snapshot.observe())
  {
    scope,
    text,
    parsed_observer,
    snapshot_observer,
    token_count_observer,
    lowering_cache,
    parse_compute_count_fn: fn() { parse_compute_count },
    snapshot_compute_count_fn: fn() { snapshot_compute_count },
  }
}

///|
pub fn MiniAuthoringPipeline::input(self : MiniAuthoringPipeline) -> String {
  self.text.get()
}

///|
pub fn MiniAuthoringPipeline::set_input(
  self : MiniAuthoringPipeline,
  input : String,
) -> Unit {
  self.text.set(input)
}

///|
pub fn MiniAuthoringPipeline::parse_doc(
  self : MiniAuthoringPipeline,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  self.parsed_observer.get()
}

///|
pub fn MiniAuthoringPipeline::parse_snapshot(
  self : MiniAuthoringPipeline,
) -> Result[@pattern.PatternSnapshot[@pattern.ControlMap], String] {
  self.snapshot_observer.get()
}

///|
pub fn MiniAuthoringPipeline::dispose(self : MiniAuthoringPipeline) -> Unit {
  self.scope.dispose()
}

///|
pub fn MiniAuthoringPipeline::reset_lowering_stats(
  self : MiniAuthoringPipeline,
) -> Unit {
  self.lowering_cache.reset_stats()
}

///|
pub fn MiniAuthoringPipeline::lowering_cache_hits(
  self : MiniAuthoringPipeline,
) -> Int {
  self.lowering_cache.hit_count()
}

///|
pub fn MiniAuthoringPipeline::lowering_cache_misses(
  self : MiniAuthoringPipeline,
) -> Int {
  self.lowering_cache.miss_count()
}

///|
pub fn MiniAuthoringPipeline::lowering_cache_entries(
  self : MiniAuthoringPipeline,
) -> Int {
  self.lowering_cache.entry_count()
}

///|
pub fn MiniAuthoringPipeline::parse_compute_count(
  self : MiniAuthoringPipeline,
) -> Int {
  (self.parse_compute_count_fn)()
}

///|
pub fn MiniAuthoringPipeline::snapshot_compute_count(
  self : MiniAuthoringPipeline,
) -> Int {
  (self.snapshot_compute_count_fn)()
}

///|
pub fn MiniAuthoringPipeline::authoring_token_count(
  self : MiniAuthoringPipeline,
) -> Int {
  self.token_count_observer.get()
}
