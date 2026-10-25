///|
pub(all) enum GraphControlTarget {
  Param(Int, GraphParamSlot)
  Gate(Int)
}

///|
// Only the bound numeric update path can produce these failures.
// Keep a flat payload so rejected updates need no nested error allocation.
pub enum GraphControlBatchError {
  BatchCapacityExceeded
  InvalidBindingIndex(Int)
  InvalidGateValue(Int, Double)
  InvalidParamValue(Int, DspNodeKind, GraphParamSlot, Double)
}

///|
priv enum ResolvedControlTarget {
  Param(Int, Int, GraphParamSlot)
  Gate(Int, EnvelopeControl)
}

///|
pub struct GraphControlBatch {
  priv ids : FixedArray[Int]
  priv values : FixedArray[Double]
  priv mut count : Int
  priv mut overflowed : Bool
}

///|
pub fn GraphControlBatch::GraphControlBatch(
  capacity : Int,
) -> GraphControlBatch {
  // Zero is an empty batch: an empty update succeeds, any push poisons it.
  guard capacity >= 0 else { abort("negative control batch capacity") }
  {
    ids: FixedArray::make(capacity, 0),
    values: FixedArray::make(capacity, 0.0),
    count: 0,
    overflowed: false,
  }
}

///|
pub fn GraphControlBatch::clear(self : GraphControlBatch) -> Unit {
  self.count = 0
  self.overflowed = false
}

///|
pub fn GraphControlBatch::length(self : GraphControlBatch) -> Int {
  self.count
}

///|
pub fn GraphControlBatch::push(
  self : GraphControlBatch,
  target : Int,
  value : Double,
) -> Bool {
  guard self.count < self.ids.length() else {
    self.overflowed = true
    return false
  }
  self.ids[self.count] = target
  self.values[self.count] = value
  self.count += 1
  true
}

///|
fn Dsp::resolve_targets(
  self : Dsp,
  targets : Array[GraphControlTarget],
) -> Result[FixedArray[ResolvedControlTarget], GraphControlError] {
  let graph = self.0
  let bindings = []
  for target in targets {
    let authoring = match target {
      Param(i, _) | Gate(i) => i
    }
    let index = match graph.compiled_index_result(authoring) {
      Ok(i) => i
      Err(e) => return Err(e)
    }
    let node = graph.nodes[index]
    match target {
      Param(_, slot) => {
        guard @model.node_accepts_slot(node, slot) else {
          return Err(InvalidSlotForNode(authoring, node.kind(), slot))
        }
        guard runtime_param_state_available(graph, index, node, slot) else {
          return Err(MissingRuntimeState(authoring, node.kind()))
        }
        let value = match slot {
          Value0 => node.value0()
          Value1 => node.value1()
          Value2 => node.value2()
          Value3 => node.value3()
          DelaySamples => node.delay_samples().to_double()
        }
        guard model_node_param_valid(
          node,
          slot,
          value,
          graph.compile_sample_rate,
        ) else {
          return Err(InvalidParamValue(authoring, node.kind(), slot, value))
        }
        bindings.push(ResolvedControlTarget::Param(authoring, index, slot))
      }
      Gate(_) => {
        guard graph.controls.targets[index] is Envelope(env) else {
          return Err(InvalidGateNode(authoring, node.kind()))
        }
        bindings.push(ResolvedControlTarget::Gate(authoring, env))
      }
    }
  }
  Ok(FixedArray::makei(bindings.length(), i => bindings[i]))
}

///|
// Internal adapter runtime: bindings are constructed once, never replaced.
pub struct BoundDsp {
  priv graph : Dsp
  priv bindings : FixedArray[ResolvedControlTarget]
}

///|
pub suberror BoundGraphError {
  InvalidGraph(GraphCompileError)
  ControlRejected(GraphControlError)
}

///|
pub fn BoundDsp::BoundDsp(
  template : AnalyzedGraph,
  context : DspContext,
  targets : Array[GraphControlTarget],
) -> BoundDsp raise BoundGraphError {
  let graph = match Dsp::compile_result(template, context) {
    Ok(graph) => graph
    Err(error) => raise InvalidGraph(error)
  }
  let bindings = match graph.resolve_targets(targets) {
    Ok(bindings) => bindings
    Err(error) => raise ControlRejected(error)
  }
  { graph, bindings, }
}

///|
pub fn BoundDsp::process(
  self : BoundDsp,
  context : DspContext,
  output : AudioBuffer,
) -> Unit {
  self.graph.process(context, output)
}

///|
// None is success; only rejected batches construct an error payload.
pub fn BoundDsp::update(
  self : BoundDsp,
  batch : GraphControlBatch,
) -> GraphControlBatchError? {
  guard !batch.overflowed else { return Some(BatchCapacityExceeded) }
  let graph = self.graph.0
  graph.controls.begin(graph.nodes)
  for i = 0; i < batch.count; i = i + 1 {
    let id = batch.ids[i]
    guard id >= 0 && id < self.bindings.length() else {
      return Some(InvalidBindingIndex(id))
    }
    let value = batch.values[i]
    match self.bindings[id] {
      Param(authoring, index, slot) => {
        let node = graph.controls.nodes[index]
        guard set_model_node_param_in_place(
          node,
          slot,
          value,
          graph.compile_sample_rate,
        ) else {
          return Some(InvalidParamValue(authoring, node.kind(), slot, value))
        }
        graph.controls.touched[index] = true
      }
      Gate(authoring, env) => {
        guard value == 0.0 || value == 1.0 else {
          return Some(InvalidGateValue(authoring, value))
        }
        env.gate = fold_gate_state(env.gate, value == 1.0)
      }
    }
  }
  graph.commit_prepared_controls()
  None
}
