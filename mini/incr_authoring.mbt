///|
/// Experimental incr-backed authoring pipeline for mini notation.
///
/// Contract for the Phase 6+ design slice:
/// - The input text is the only mutable authoring signal.
/// - Parsing remains delegated to the handwritten PatternDoc parser and still
///   reparses the whole source string on each text change.
/// - Successful reparses pass the last successful PatternDoc as the
///   `previous` argument to `parse_doc`, preserving stable subtree IDs
///   across edits.
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
/// This intentionally wraps `parse_doc` (with `previous=Some(...)` for
/// reuse) before introducing loom or a token-level incremental parser.
/// The runtime parser and PatternDoc parser remain separate entry points
/// for now.
pub struct MiniAuthoringPipeline {
  priv scope : @incr.Scope
  priv text : @incr.Signal[String]
  priv source_edit : @incr.Signal[MiniSourceEditSpan?]
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
  priv accepted : @incr.AcceptedDerived[
    @pattern.PatternDoc[@pattern.ControlMap],
    String,
  ]
}

///|
pub fn MiniAuthoringPipeline::new(input : String) -> MiniAuthoringPipeline {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let text = scope.signal(input, label="mini.text")
  let source_edit : @incr.Signal[MiniSourceEditSpan?] = scope.signal(
    None,
    label="mini.source_edit",
  )
  // Previous source text for token realignment across edits.
  // Updated alongside `previous` in the parsed memo's Ok branch.
  let mut previous_source : String = input
  let token_count = scope.memo(
    () => {
      let current = text.get()
      let tokens = tokenize_mini_authoring_source(current)
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
      let current = text.get()
      let tokens = match previous {
        None => tokenize_mini_authoring_source(current)
        Some(_) =>
          match source_edit.get() {
            Some(span) =>
              realign_mini_authoring_tokens_with_source_edit(
                previous_source, current, span,
              )
            None => realign_mini_authoring_tokens(previous_source, current)
          }
      }
      let result = parse_doc_with_token_identities(current, previous, tokens)
      match result {
        Ok(doc) => {
          previous_source = current
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
  // Prime parsed before accepted_memo's eager fold reads it.
  // The parsed memo mutates local state (`previous`, `previous_source`),
  // which must not happen inside a reactive compute context.
  ignore(parsed_observer.get())
  // AcceptedDerived for last-good: retains the last successful PatternDoc
  // across parse errors. Scope::accepted_memo allocates its own child scope
  // and registers the accepted cell internally — no extra add_cell_ids needed.
  let accepted = scope.accepted_memo(
    () => parsed.get(),
    label="mini.accepted_doc",
  )

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
    source_edit,
    parsed_observer,
    snapshot_observer,
    token_count_observer,
    lowering_cache,
    parse_compute_count_fn: fn() { parse_compute_count },
    snapshot_compute_count_fn: fn() { snapshot_compute_count },
    accepted,
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
  self.source_edit.set(None)
  self.text.set(input)
}

///|
pub fn MiniAuthoringPipeline::set_input_with_source_edit(
  self : MiniAuthoringPipeline,
  input : String,
  old_start~ : Int,
  old_end~ : Int,
  new_end~ : Int,
) -> Unit {
  self.source_edit.set(Some({ old_start, old_end, new_end }))
  self.text.set(input)
}

///|
pub fn MiniAuthoringPipeline::parse_doc(
  self : MiniAuthoringPipeline,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  self.parsed_observer.get()
}

///|
/// The last successfully parsed PatternDoc, retained across parse errors.
/// Returns `None` until the first successful parse.
pub fn MiniAuthoringPipeline::accepted_doc(
  self : MiniAuthoringPipeline,
) -> @pattern.PatternDoc[@pattern.ControlMap]? {
  self.accepted.accepted_or_abort()
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
