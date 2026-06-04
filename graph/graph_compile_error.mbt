///|
/// Typed rejection reason for graph compilation.
///
/// Node indices reported by public `compile_result` entry points are original
/// authoring indices when they can be mapped from the analyzed template.
pub(all) enum GraphCompileError {
  InvalidSampleRate(Double)
  MissingOutput(DspNodeKind)
  MultipleOutputs(DspNodeKind)
  WrongOutputKind(Int, DspNodeKind, DspNodeKind)
  InvalidInput(Int, DspNodeKind, GraphTopologyInputSlot, Int)
  InvalidParamValue(Int, DspNodeKind, GraphParamSlot, Double)
  InvalidDelaySamples(Int, Int, Int)
  UnreachableNode(Int)
  InvalidFeedbackEdge(Int, Int, Int)
  DuplicateFeedbackInput(Int, GraphTopologyInputSlot)
  InvalidTerminalShape(DspNodeKind)
  InternalRejected(DspNodeKind)
} derive(Debug)

///|
pub impl Show for GraphCompileError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn graph_input_slot_from_runtime(
  slot : @runtime.GraphInputSlot,
) -> GraphTopologyInputSlot {
  match slot {
    @runtime.GraphInputSlot::Input0 => GraphTopologyInputSlot::Input0
    @runtime.GraphInputSlot::Input1 => GraphTopologyInputSlot::Input1
  }
}

///|
fn graph_compile_error_from_runtime(
  error : @runtime.GraphCompileError,
) -> GraphCompileError {
  match error {
    @runtime.GraphCompileError::InvalidSampleRate(sample_rate) =>
      GraphCompileError::InvalidSampleRate(sample_rate)
    @runtime.GraphCompileError::MissingOutput(kind) =>
      GraphCompileError::MissingOutput(dsp_node_kind_from_model(kind))
    @runtime.GraphCompileError::MultipleOutputs(kind) =>
      GraphCompileError::MultipleOutputs(dsp_node_kind_from_model(kind))
    @runtime.GraphCompileError::WrongOutputKind(index, actual, expected) =>
      GraphCompileError::WrongOutputKind(
        index,
        dsp_node_kind_from_model(actual),
        dsp_node_kind_from_model(expected),
      )
    @runtime.GraphCompileError::InvalidInput(index, kind, slot, input) =>
      GraphCompileError::InvalidInput(
        index,
        dsp_node_kind_from_model(kind),
        graph_input_slot_from_runtime(slot),
        input,
      )
    @runtime.GraphCompileError::InvalidParamValue(index, kind, slot, value) =>
      GraphCompileError::InvalidParamValue(
        index,
        dsp_node_kind_from_model(kind),
        graph_param_slot_from_model(slot),
        value,
      )
    @runtime.GraphCompileError::InvalidDelaySamples(
      index,
      delay_samples,
      delay_max_samples
    ) =>
      GraphCompileError::InvalidDelaySamples(
        index, delay_samples, delay_max_samples,
      )
    @runtime.GraphCompileError::UnreachableNode(index) =>
      GraphCompileError::UnreachableNode(index)
    @runtime.GraphCompileError::InvalidFeedbackEdge(source, target, slot) =>
      GraphCompileError::InvalidFeedbackEdge(source, target, slot)
    @runtime.GraphCompileError::DuplicateFeedbackInput(target, slot) =>
      GraphCompileError::DuplicateFeedbackInput(
        target,
        graph_input_slot_from_runtime(slot),
      )
    @runtime.GraphCompileError::InvalidTerminalShape(kind) =>
      GraphCompileError::InvalidTerminalShape(dsp_node_kind_from_model(kind))
    @runtime.GraphCompileError::InternalRejected(kind) =>
      GraphCompileError::InternalRejected(dsp_node_kind_from_model(kind))
  }
}

///|
/// Compile a declarative mono graph and return a typed rejection reason when
/// compilation fails.
pub fn CompiledDsp::compile_result(
  compiled_template : CompiledTemplate,
  context : DspContext,
) -> Result[CompiledDsp, GraphCompileError] {
  match @runtime.CompiledDsp::compile_result(compiled_template.raw(), context) {
    Ok(compiled) => Ok(CompiledDsp::from_internal(compiled))
    Err(error) => Err(graph_compile_error_from_runtime(error))
  }
}

///|
/// Compile a declarative terminal-stereo graph and return a typed rejection
/// reason when compilation fails.
pub fn CompiledStereoDsp::compile_result(
  compiled_template : CompiledTemplate,
  context : DspContext,
) -> Result[CompiledStereoDsp, GraphCompileError] {
  match
    @runtime.CompiledStereoDsp::compile_result(compiled_template.raw(), context) {
    Ok(compiled) => Ok(CompiledStereoDsp::from_internal(compiled))
    Err(error) => Err(graph_compile_error_from_runtime(error))
  }
}
