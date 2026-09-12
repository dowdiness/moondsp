///|
test "MiniAuthoringPipeline watches survive collection before consumer reads" {
  let pipeline = MiniAuthoringPipeline::new("s(\"bd sd\")")
  inspect(pipeline.parse_compute_count(), content="1")
  inspect(pipeline.snapshot_compute_count(), content="0")
  pipeline.scope.collect()
  guard pipeline.parse_doc() is Ok(_) else {
    abort("expected parsed Watch to survive Scope::collect")
  }
  inspect(pipeline.parse_compute_count(), content="1")
  inspect(pipeline.snapshot_compute_count(), content="0")
  guard pipeline.parse_snapshot() is Ok(_) else {
    abort("expected snapshot Watch to survive Scope::collect")
  }
  inspect(pipeline.snapshot_compute_count(), content="1")
  inspect(pipeline.authoring_token_count(), content="7")
  pipeline.dispose()
}

///|
test "AcceptedDerived preserves stamp for unchanged PatternDoc revision" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let select_second = scope.input(false)
  let id = @identity.PatternNodeId::from_string("backdate-root") catch {
    _ => abort("expected a valid PatternNodeId")
  }
  let first = @pattern.PatternDoc::pure(id~, value=1)
  let equivalent = @pattern.PatternDoc::pure(id~, value=99)
  let accepted : @incr.AcceptedDerived[@pattern.PatternDoc[Int], String] = scope.accepted_memo(() => {
      Ok(if select_second.get() { equivalent } else { first })
    },
  )
  ignore(accepted.accepted_or_abort())
  let accepted_changed_at = accepted.accepted_changed_at()
  select_second.set(true)
  ignore(accepted.accepted_or_abort())
  assert_true(accepted.accepted_changed_at() == accepted_changed_at)
  scope.dispose()
}

///|
test "panic MiniAuthoringPipeline parse_doc fails after disposal" {
  let pipeline = MiniAuthoringPipeline::new("s(\"bd sd\")")
  pipeline.dispose()
  ignore(pipeline.parse_doc())
}

///|
test "panic MiniAuthoringPipeline parse_snapshot fails after disposal" {
  let pipeline = MiniAuthoringPipeline::new("s(\"bd sd\")")
  pipeline.dispose()
  ignore(pipeline.parse_snapshot())
}

///|
test "panic MiniAuthoringPipeline token count fails after disposal" {
  let pipeline = MiniAuthoringPipeline::new("s(\"bd sd\")")
  pipeline.dispose()
  ignore(pipeline.authoring_token_count())
}

///|
test "panic MiniAuthoringPipeline accepted_doc fails after disposal" {
  let pipeline = MiniAuthoringPipeline::new("s(\"bd sd\")")
  pipeline.dispose()
  ignore(pipeline.accepted_doc())
}
