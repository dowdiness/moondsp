///|
/// Checked topology and immutable initial parameters. Runtime state is never
/// retained here: each instantiation owns its nodes, buffers and DSP histories.
priv struct GraphProgram {
  sample_rate : Double
  block_size : Int32
  samples : @dsp.SampleStore
  nodes : FixedArray[@model.DspNode]
  index_map : FixedArray[Int32]
  feedback_edges : FixedArray[(Int32, Int32, Int32)]
  self_enabled : FixedArray[Bool]
  back_edge_input0_source : FixedArray[Int32]
  back_edge_input1_source : FixedArray[Int32]
}

///|
priv struct DspProgram(GraphProgram)

///|
priv struct StereoDspProgram(GraphProgram)

///|
fn DspProgram::instantiate(self : DspProgram) -> Dsp {
  Dsp(self.0.instantiate())
}

///|
fn StereoDspProgram::instantiate(self : StereoDspProgram) -> StereoDsp {
  StereoDsp(self.0.instantiate())
}
