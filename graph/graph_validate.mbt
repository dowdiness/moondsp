///|
fn valid_any_node_inputs(
  node : DspNode,
  node_count : Int,
  sample_rate : Double,
  output_kind : DspNodeKind,
) -> Bool {
  match node.kind {
    Constant => @dsp.is_finite(node.value0)
    Oscillator =>
      if node.input0 >= 0 {
        valid_reference(node.input0, node_count)
      } else {
        @dsp.is_finite(node.value0)
      }
    Noise => true
    Adsr =>
      @dsp.is_finite(node.value0) &&
      @dsp.is_finite(node.value1) &&
      @dsp.is_finite(node.value2) &&
      @dsp.is_finite(node.value3)
    Biquad =>
      valid_reference(node.input0, node_count) &&
      valid_biquad_graph_params(sample_rate, node.value0, node.value1)
    Delay =>
      valid_reference(node.input0, node_count) &&
      valid_delay_feedback(node.value0) &&
      valid_delay_samples(node.delay_samples, node.delay_max_samples)
    Gain =>
      valid_reference(node.input0, node_count) && @dsp.is_finite(node.value0)
    Mul =>
      valid_reference(node.input0, node_count) &&
      valid_reference(node.input1, node_count)
    Mix =>
      valid_reference(node.input0, node_count) &&
      valid_reference(node.input1, node_count)
    Clip =>
      valid_reference(node.input0, node_count) &&
      @dsp.is_finite(node.value0) &&
      node.value0 > 0.0
    Output =>
      node.kind == output_kind && valid_reference(node.input0, node_count)
    Pan =>
      valid_reference(node.input0, node_count) && @dsp.is_finite(node.value0)
    StereoGain =>
      valid_reference(node.input0, node_count) && @dsp.is_finite(node.value0)
    StereoClip =>
      valid_reference(node.input0, node_count) &&
      @dsp.is_finite(node.value0) &&
      node.value0 > 0.0
    StereoBiquad =>
      valid_reference(node.input0, node_count) &&
      valid_biquad_graph_params(sample_rate, node.value0, node.value1)
    StereoDelay =>
      valid_reference(node.input0, node_count) &&
      valid_delay_feedback(node.value0) &&
      valid_delay_samples(node.delay_samples, node.delay_max_samples)
    StereoMixDown => valid_reference(node.input0, node_count)
    StereoOutput =>
      node.kind == output_kind && valid_reference(node.input0, node_count)
  }
}

///|
fn valid_node_inputs(
  node : DspNode,
  node_count : Int,
  sample_rate : Double,
) -> Bool {
  valid_any_node_inputs(node, node_count, sample_rate, Output)
}

///|
fn valid_stereo_node_inputs(
  node : DspNode,
  node_count : Int,
  sample_rate : Double,
) -> Bool {
  valid_any_node_inputs(node, node_count, sample_rate, StereoOutput)
}

///|
fn valid_reference(input : Int, node_count : Int) -> Bool {
  input >= 0 && input < node_count
}

///|

///|
fn valid_feedback_terminal_mono_graph(
  nodes : FixedArray[DspNode],
  feedback_edges : FixedArray[(Int, Int, Int)],
) -> Bool {
  // Build per-slot back-edge source maps for shape resolution.
  let be_input0_src = FixedArray::make(nodes.length(), -1)
  let be_input1_src = FixedArray::make(nodes.length(), -1)
  for i = 0; i < feedback_edges.length(); i = i + 1 {
    let edge = feedback_edges[i]
    if edge.2 == 0 {
      be_input0_src[edge.1] = edge.0
    } else {
      be_input1_src[edge.1] = edge.0
    }
  }
  let shapes = FixedArray::make(nodes.length(), MONO_SIGNAL_SHAPE)
  for index = 0; index < nodes.length(); index = index + 1 {
    let node = nodes[index]
    let shape = match node.kind {
      Constant => MONO_SIGNAL_SHAPE
      Oscillator =>
        if node.input0 >= 0 {
          match
            feedback_resolved_input_shape(
              node.input0,
              be_input0_src[index],
              shapes,
              nodes,
            ) {
            Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
            _ => return false
          }
        } else {
          MONO_SIGNAL_SHAPE
        }
      Noise => MONO_SIGNAL_SHAPE
      Adsr => MONO_SIGNAL_SHAPE
      Biquad =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Delay =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Gain =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Mul => {
        let s0 = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        let s1 = feedback_resolved_input_shape(
          node.input1,
          be_input1_src[index],
          shapes,
          nodes,
        )
        if is_mono_shape(s0) && is_mono_shape(s1) {
          MONO_SIGNAL_SHAPE
        } else {
          return false
        }
      }
      Mix => {
        let s0 = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        let s1 = feedback_resolved_input_shape(
          node.input1,
          be_input1_src[index],
          shapes,
          nodes,
        )
        if is_mono_shape(s0) && is_mono_shape(s1) {
          MONO_SIGNAL_SHAPE
        } else {
          return false
        }
      }
      Clip =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Output =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Pan =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(MONO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoGain =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoClip =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoBiquad =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoDelay =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoMixDown =>
        match
          feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          ) {
          Some(STEREO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      StereoOutput => return false
    }
    shapes[index] = shape
  }
  // Verify no feedback edges go through Output nodes
  for index = 0; index < feedback_edges.length(); index = index + 1 {
    let edge = feedback_edges[index]
    if nodes[edge.0].kind is Output || nodes[edge.1].kind is Output {
      return false
    }
    // Verify shape compatibility
    match feedback_target_shape(nodes[edge.1], edge.2) {
      Some(expected_shape) =>
        if shapes[edge.0] != expected_shape {
          return false
        }
      None => return false
    }
  }
  let last = nodes.length() - 1
  nodes[last].kind is DspNodeKind::Output && shapes[last] == MONO_SIGNAL_SHAPE
}

///|
fn valid_terminal_mono_shapes(nodes : FixedArray[DspNode]) -> Bool {
  let shapes = FixedArray::make(nodes.length(), MONO_SIGNAL_SHAPE)
  for index = 0; index < nodes.length(); index = index + 1 {
    let node = nodes[index]
    let shape = match node.kind {
      Constant => MONO_SIGNAL_SHAPE
      Oscillator =>
        if node.input0 >= 0 {
          match input_shape(node.input0, shapes) {
            Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
            _ => return false
          }
        } else {
          MONO_SIGNAL_SHAPE
        }
      Noise => MONO_SIGNAL_SHAPE
      Adsr => MONO_SIGNAL_SHAPE
      Biquad =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Delay =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Gain =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Mul =>
        if is_mono_shape(input_shape(node.input0, shapes)) &&
          is_mono_shape(input_shape(node.input1, shapes)) {
          MONO_SIGNAL_SHAPE
        } else {
          return false
        }
      Mix =>
        if is_mono_shape(input_shape(node.input0, shapes)) &&
          is_mono_shape(input_shape(node.input1, shapes)) {
          MONO_SIGNAL_SHAPE
        } else {
          return false
        }
      Clip =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Output =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      Pan =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoGain =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoClip =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoBiquad =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoDelay =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return false
        }
      StereoMixDown =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return false
        }
      StereoOutput => return false
    }
    shapes[index] = shape
  }

  let last = nodes.length() - 1
  nodes[last].kind is DspNodeKind::Output && shapes[last] == MONO_SIGNAL_SHAPE
}

///|
fn valid_terminal_stereo_shapes(nodes : FixedArray[DspNode]) -> Bool {
  compiled_stereo_shapes(nodes) is Some(_)
}

///|
fn compiled_stereo_shapes(nodes : FixedArray[DspNode]) -> FixedArray[Int]? {
  let shapes = FixedArray::make(nodes.length(), MONO_SIGNAL_SHAPE)
  for index = 0; index < nodes.length(); index = index + 1 {
    let node = nodes[index]
    let shape = match node.kind {
      Constant => MONO_SIGNAL_SHAPE
      Oscillator =>
        if node.input0 >= 0 {
          match input_shape(node.input0, shapes) {
            Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
            _ => return None
          }
        } else {
          MONO_SIGNAL_SHAPE
        }
      Noise => MONO_SIGNAL_SHAPE
      Adsr => MONO_SIGNAL_SHAPE
      Biquad =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      Delay =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      Gain =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      Mul =>
        if is_mono_shape(input_shape(node.input0, shapes)) &&
          is_mono_shape(input_shape(node.input1, shapes)) {
          MONO_SIGNAL_SHAPE
        } else {
          return None
        }
      Mix =>
        if is_mono_shape(input_shape(node.input0, shapes)) &&
          is_mono_shape(input_shape(node.input1, shapes)) {
          MONO_SIGNAL_SHAPE
        } else {
          return None
        }
      Clip =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      Output => return None
      Pan =>
        match input_shape(node.input0, shapes) {
          Some(MONO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      StereoGain =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      StereoClip =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      StereoBiquad =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      StereoDelay =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      StereoMixDown => return None
      StereoOutput =>
        match input_shape(node.input0, shapes) {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
    }
    shapes[index] = shape
  }

  let last = nodes.length() - 1
  if nodes[last].kind is DspNodeKind::StereoOutput &&
    shapes[last] == STEREO_SIGNAL_SHAPE {
    Some(shapes)
  } else {
    None
  }
}

///|
/// Infer signal shapes for a stereo feedback graph. Back-edge inputs are
/// resolved from the source node's intrinsic output shape rather than from
/// forward propagation, which lets the analysis succeed for cycles that cross
/// the mono/stereo boundary (e.g. Pan -> StereoGain -> StereoMixDown -> Mix).
fn compiled_feedback_stereo_shapes(
  nodes : FixedArray[DspNode],
  feedback_edges : FixedArray[(Int, Int, Int)],
) -> FixedArray[Int]? {
  // Build per-slot back-edge source maps so we can skip them during forward
  // shape propagation.
  let be_input0_src = FixedArray::make(nodes.length(), -1)
  let be_input1_src = FixedArray::make(nodes.length(), -1)
  for i = 0; i < feedback_edges.length(); i = i + 1 {
    let edge = feedback_edges[i]
    if edge.2 == 0 {
      be_input0_src[edge.1] = edge.0
    } else {
      be_input1_src[edge.1] = edge.0
    }
  }
  let shapes = FixedArray::make(nodes.length(), MONO_SIGNAL_SHAPE)
  for index = 0; index < nodes.length(); index = index + 1 {
    let node = nodes[index]
    let shape = match node.kind {
      Constant => MONO_SIGNAL_SHAPE
      Oscillator =>
        if node.input0 >= 0 {
          let s = feedback_resolved_input_shape(
            node.input0,
            be_input0_src[index],
            shapes,
            nodes,
          )
          match s {
            Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
            _ => return None
          }
        } else {
          MONO_SIGNAL_SHAPE
        }
      Noise => MONO_SIGNAL_SHAPE
      Adsr => MONO_SIGNAL_SHAPE
      Biquad => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      }
      Delay => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      }
      Gain => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      }
      Mul => {
        let s0 = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        let s1 = feedback_resolved_input_shape(
          node.input1,
          be_input1_src[index],
          shapes,
          nodes,
        )
        if is_mono_shape(s0) && is_mono_shape(s1) {
          MONO_SIGNAL_SHAPE
        } else {
          return None
        }
      }
      Mix => {
        let s0 = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        let s1 = feedback_resolved_input_shape(
          node.input1,
          be_input1_src[index],
          shapes,
          nodes,
        )
        if is_mono_shape(s0) && is_mono_shape(s1) {
          MONO_SIGNAL_SHAPE
        } else {
          return None
        }
      }
      Clip => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      }
      Output => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(MONO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      }
      Pan => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(MONO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      }
      StereoGain => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      }
      StereoClip => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      }
      StereoBiquad => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      }
      StereoDelay => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      }
      StereoMixDown => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(STEREO_SIGNAL_SHAPE) => MONO_SIGNAL_SHAPE
          _ => return None
        }
      }
      StereoOutput => {
        let s = feedback_resolved_input_shape(
          node.input0,
          be_input0_src[index],
          shapes,
          nodes,
        )
        match s {
          Some(STEREO_SIGNAL_SHAPE) => STEREO_SIGNAL_SHAPE
          _ => return None
        }
      }
    }
    shapes[index] = shape
  }

  let last = nodes.length() - 1
  if nodes[last].kind is DspNodeKind::StereoOutput &&
    shapes[last] == STEREO_SIGNAL_SHAPE {
    Some(shapes)
  } else {
    None
  }
}

///|
/// Resolve the shape of an input, accounting for back-edges. If the input is a
/// back-edge, use the intrinsic output shape of the source node.
fn feedback_resolved_input_shape(
  input_index : Int,
  back_edge_source : Int,
  shapes : FixedArray[Int],
  nodes : FixedArray[DspNode],
) -> Int? {
  if back_edge_source >= 0 {
    Some(nodes[back_edge_source].signal_shape())
  } else {
    input_shape(input_index, shapes)
  }
}

///|
fn valid_feedback_terminal_stereo_graph(
  nodes : FixedArray[DspNode],
  feedback_edges : FixedArray[(Int, Int, Int)],
) -> Bool {
  let shapes = match compiled_feedback_stereo_shapes(nodes, feedback_edges) {
    Some(shapes) => shapes
    None => return false
  }
  for index = 0; index < feedback_edges.length(); index = index + 1 {
    let edge = feedback_edges[index]
    if nodes[edge.0].kind is Output ||
      nodes[edge.0].kind is StereoOutput ||
      nodes[edge.1].kind is Output ||
      nodes[edge.1].kind is StereoOutput {
      return false
    }
    // Verify shape compatibility: source shape must match what target slot expects
    match feedback_target_shape(nodes[edge.1], edge.2) {
      Some(expected_shape) =>
        if shapes[edge.0] != expected_shape {
          return false
        }
      None => return false
    }
  }
  true
}

///|
fn feedback_target_shape(node : DspNode, target_slot : Int) -> Int? {
  match node.kind {
    Biquad => if target_slot == 0 { Some(MONO_SIGNAL_SHAPE) } else { None }
    Delay => if target_slot == 0 { Some(MONO_SIGNAL_SHAPE) } else { None }
    Gain => if target_slot == 0 { Some(MONO_SIGNAL_SHAPE) } else { None }
    Mul =>
      if target_slot == 0 || target_slot == 1 {
        Some(MONO_SIGNAL_SHAPE)
      } else {
        None
      }
    Mix =>
      if target_slot == 0 || target_slot == 1 {
        Some(MONO_SIGNAL_SHAPE)
      } else {
        None
      }
    Clip => if target_slot == 0 { Some(MONO_SIGNAL_SHAPE) } else { None }
    Pan => if target_slot == 0 { Some(MONO_SIGNAL_SHAPE) } else { None }
    StereoGain =>
      if target_slot == 0 {
        Some(STEREO_SIGNAL_SHAPE)
      } else {
        None
      }
    StereoClip =>
      if target_slot == 0 {
        Some(STEREO_SIGNAL_SHAPE)
      } else {
        None
      }
    StereoBiquad =>
      if target_slot == 0 {
        Some(STEREO_SIGNAL_SHAPE)
      } else {
        None
      }
    StereoDelay =>
      if target_slot == 0 {
        Some(STEREO_SIGNAL_SHAPE)
      } else {
        None
      }
    StereoMixDown =>
      if target_slot == 0 {
        Some(STEREO_SIGNAL_SHAPE)
      } else {
        None
      }
    Output => if target_slot == 0 { Some(MONO_SIGNAL_SHAPE) } else { None }
    StereoOutput =>
      if target_slot == 0 {
        Some(STEREO_SIGNAL_SHAPE)
      } else {
        None
      }
    _ => None
  }
}

///|
fn input_shape(input : Int, shapes : FixedArray[Int]) -> Int? {
  if input < 0 || input >= shapes.length() {
    None
  } else {
    Some(shapes[input])
  }
}
