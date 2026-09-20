///|
/// Experimental incr-backed authoring pipeline for mini notation.
///
/// Contract for the Phase 6+ design slice:
/// - Text and its optional source edit span are published atomically.
/// - Parsing remains delegated to the handwritten PatternDoc parser and still
///   reparses the whole source string on each text change.
/// - Successful reparses retain their aligned tokens as well as the last
///   successful PatternDoc. Unchanged tokens keep their identities, while
///   lifetime-scoped occurrence counters prevent deleted identities being reused.
/// - Parse errors are propagated as `Err(String)` and do not replace the last
///   reusable document. The last successful PatternDoc is separately
///   accessible via `accepted_doc()` (backed by incr `AcceptedDerived`).
/// - `new()` primes the first parse before attaching the accepted projection.
///   That projection can eagerly reparse when an input update is published;
///   snapshot lowering remains lazy until `parse_snapshot()` is read.
/// - Lowering uses one persistent PatternLoweringCache owned by the pipeline,
///   so the current reuse win is stable-subtree and lowering-cache reuse after
///   parse, not token-level incremental parsing.
/// - Scope owns the long-lived cells, and persistent Watch handles anchor
///   parsed, snapshot, and diagnostic reads for the pipeline lifetime.
/// - Compute counters are exposed for tests and diagnostics so callers can
///   distinguish whole-document recomputation from lowering-cache reuse.
///
/// This intentionally wraps `parse_doc` (with `previous=Some(...)` for
/// reuse) before introducing loom or a token-level incremental parser.
/// The runtime parser and PatternDoc parser remain separate entry points
/// for now.
pub struct MiniAuthoringPipeline {
  priv scope : @incr.Scope
  priv runtime : @incr.Runtime
  priv text : @incr.Input[String]
  priv source_edit : @incr.Input[MiniSourceEditSpan?]
  priv parsed_watch : @incr.Watch[
    Result[@pattern.PatternDoc[@pattern.ControlMap], String],
  ]
  priv snapshot_watch : @incr.Watch[
    () -> Result[@pattern.PatternSnapshot[@pattern.ControlMap], String],
  ]
  priv token_count_watch : @incr.Watch[() -> Int]
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
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let text = scope.input(input, label="mini.text")
  let source_edit : @incr.Input[MiniSourceEditSpan?] = scope.input(
    None,
    label="mini.source_edit",
  )
  // The token baseline follows the last successful parse; allocation counters
  // live for the entire pipeline, including failed parse attempts.
  let mut previous_tokens : Array[MiniToken]? = None
  let identity_counters : Map[String, Int] = Map([])
  let token_count = scope.derived_no_backdate(
    () => {
      let current = text.get()
      let cached : Ref[Int?] = Ref(None)
      fn() {
        match cached.val {
          Some(count) => count
          None => {
            let tokens = tokenize_mini_authoring_source(current)
            ignore(mini_authoring_token_fingerprint(tokens))
            let count = tokens.length()
            cached.val = Some(count)
            count
          }
        }
      }
    },
    label="mini.token_count",
  )
  let token_count_watch = scope.watch(token_count)
  // Last successful parse is intentional mutable state: errors should surface
  // to callers without discarding the previous reusable PatternDoc.
  let mut previous : @pattern.PatternDoc[@pattern.ControlMap]? = None
  let mut parse_compute_count = 0
  let parsed = scope.derived_no_backdate(
    fn() {
      parse_compute_count += 1
      let current = text.get()
      let tokens = match previous_tokens {
        None =>
          tokenize_mini_authoring_source(current, counters=identity_counters)
        Some(old_tokens) => {
          let new_tokens = tokenize_mini_authoring_source(current)
          let span = match source_edit.get() {
            Some(edit) =>
              mini_token_edit_span_from_source(old_tokens, new_tokens, edit)
            None => mini_token_edit_span(old_tokens, new_tokens)
          }
          mini_realign_token_identities_with_span(
            old_tokens,
            new_tokens,
            span,
            counters=identity_counters,
          )
        }
      }
      let result = parse_doc_with_token_identities(current, previous, tokens)
      match result {
        Ok(doc) => {
          previous_tokens = Some(tokens)
          previous = Some(doc)
          Ok(doc)
        }
        Err(msg) => Err(msg)
      }
    },
    label="mini.parsed_doc",
  )
  // Scope::watch registers and primes the persistent parsed root exactly once.
  // Priming happens before accepted_memo's eager fold reads parsed, because the
  // parse closure mutates local reuse state.
  let parsed_watch = scope.watch(parsed)
  // AcceptedDerived for last-good: retains the last successful PatternDoc
  // across parse errors. Scope::accepted_memo allocates its own child scope
  // and registers the accepted cell internally.
  let accepted = scope.accepted_memo(
    () => parsed.read_or_abort(),
    label="mini.accepted_doc",
  )

  let lowering_cache : @pattern.PatternLoweringCache[@pattern.ControlMap] = @pattern.PatternLoweringCache::new()
  let mut snapshot_compute_count = 0
  // Watch creation primes only this cheap reader-producing derived. Actual
  // lowering stays lazy until parse_snapshot() invokes the returned reader.
  let snapshot_reader = scope.derived_no_backdate(
    fn() {
      let current = parsed.read_or_abort()
      let cached : Ref[
        Result[@pattern.PatternSnapshot[@pattern.ControlMap], String]?,
      ] = Ref(None)
      fn() {
        match cached.val {
          Some(result) => result
          None => {
            snapshot_compute_count += 1
            let result = match current {
              Err(msg) => Err(msg)
              Ok(doc) => {
                let snapshot = doc.lower_with_cache(lowering_cache) catch {
                  _ => return Err("internal mini PatternDoc lowering failed")
                }
                Ok(snapshot)
              }
            }
            cached.val = Some(result)
            result
          }
        }
      }
    },
    label="mini.snapshot",
  )
  let snapshot_watch = scope.watch(snapshot_reader)
  {
    scope,
    runtime: rt,
    text,
    source_edit,
    parsed_watch,
    snapshot_watch,
    token_count_watch,
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
  self.runtime.batch(() => {
    self.source_edit.set(None)
    self.text.set(input)
  })
}

///|
/// Applies an edit relative to the last successfully parsed source. A rejected
/// draft does not advance that token baseline or replace the accepted document.
pub fn MiniAuthoringPipeline::set_input_with_source_edit(
  self : MiniAuthoringPipeline,
  input : String,
  old_start~ : Int,
  old_end~ : Int,
  new_end~ : Int,
) -> Unit {
  // Publish text and its edit span together: eager readers must not realign
  // the old text using the new edit span.
  self.runtime.batch(() => {
    self.source_edit.set(Some({ old_start, old_end, new_end, }))
    self.text.set(input)
  })
}

///|
pub fn MiniAuthoringPipeline::parse_doc(
  self : MiniAuthoringPipeline,
) -> Result[@pattern.PatternDoc[@pattern.ControlMap], String] {
  self.parsed_watch.read_or_abort()
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
  self.snapshot_watch.read_or_abort()()
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
  self.token_count_watch.read_or_abort()()
}
