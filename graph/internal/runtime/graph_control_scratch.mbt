///|
/// Preallocated, private staging state for one compiled graph's controls.
/// The arrays are sized by graph node count, never by a control batch.
priv enum PreparedGate {
  None
  On
  Off
  OnThenOff
}

///|
priv struct EnvelopeControl {
  state : Adsr
  mut gate : PreparedGate
}

///|
priv enum ControlTarget {
  Plain
  Envelope(EnvelopeControl)
  Delay(DelayLine)
  StereoDelay(DelayLine, DelayLine)
}

///|
priv struct ControlScratch {
  nodes : FixedArray[@model.DspNode]
  touched : FixedArray[Bool]
  targets : FixedArray[ControlTarget]
}

///|
fn make_control_scratch(
  fixed_nodes : FixedArray[@model.DspNode],
  env_states : FixedArray[Adsr?],
  delay_states : FixedArray[DelayLine?],
  stereo_delay_left_states : FixedArray[DelayLine?],
  stereo_delay_right_states : FixedArray[DelayLine?],
) -> ControlScratch {
  let count = fixed_nodes.length()
  let targets = FixedArray::makei(count, i => {
    match fixed_nodes[i].kind() {
      Adsr =>
        match env_states[i] {
          Some(env) => ControlTarget::Envelope({ state: env, gate: None, })
          None => abort("ADSR control target missing")
        }
      Delay =>
        match delay_states[i] {
          Some(delay) => ControlTarget::Delay(delay)
          None => abort("delay control target missing")
        }
      StereoDelay =>
        match stereo_delay_left_states[i] {
          Some(left) =>
            match stereo_delay_right_states[i] {
              Some(right) => ControlTarget::StereoDelay(left, right)
              None => abort("stereo delay right control target missing")
            }
          None => abort("stereo delay left control target missing")
        }
      _ => ControlTarget::Plain
    }
  })
  {
    nodes: FixedArray::makei(count, i => @model.clone_node(fixed_nodes[i])),
    touched: FixedArray::make(count, false),
    targets,
  }
}

///|
fn ControlScratch::begin(
  self : ControlScratch,
  source : FixedArray[@model.DspNode],
) -> Unit {
  for i = 0; i < self.nodes.length(); i = i + 1 {
    copy_node_parameters(source[i], self.nodes[i])
    self.touched[i] = false
    match self.targets[i] {
      Envelope(target) => target.gate = None
      _ => ()
    }
  }
}

///|
fn copy_node_parameters(
  source : @model.DspNode,
  target : @model.DspNode,
) -> Unit {
  @model.set_node_value0(target, source.value0())
  @model.set_node_value1(target, source.value1())
  @model.set_node_value2(target, source.value2())
  @model.set_node_value3(target, source.value3())
  @model.set_node_delay_samples(target, source.delay_samples())
}

///|
fn fold_gate_state(previous : PreparedGate, gate_on : Bool) -> PreparedGate {
  if gate_on {
    PreparedGate::On
  } else {
    match previous {
      PreparedGate::On => PreparedGate::OnThenOff
      PreparedGate::OnThenOff => PreparedGate::OnThenOff
      PreparedGate::Off => PreparedGate::Off
      PreparedGate::None => PreparedGate::Off
    }
  }
}
