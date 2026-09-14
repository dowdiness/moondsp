///|
priv suberror GraphDecodeError {
  InvalidDescription(String, Int)
}

///|
fn graph_json_number(
  node : Json,
  key : String,
  index : Int,
) -> Double raise GraphDecodeError {
  guard node is Object(fields) &&
    fields.get(key) is Some(Number(value, ..)) &&
    @moondsp.is_finite(value) else {
    raise InvalidDescription("Expected finite numeric \{key}", index)
  }
  value
}

///|
fn graph_json_input_field(
  node : Json,
  key : String,
  count : Int,
  index : Int,
) -> Int raise GraphDecodeError {
  let value = graph_json_number(node, key, index)
  guard value >= 0.0 && value < count.to_double() && @math.floor(value) == value else {
    raise InvalidDescription("Input index is outside the graph", index)
  }
  value.to_int()
}

///|
fn graph_json_input(
  node : Json,
  count : Int,
  index : Int,
) -> Int raise GraphDecodeError {
  graph_json_input_field(node, "input", count, index)
}

///|
fn graph_json_node_index(
  node : Json,
  index : Int,
) -> Int raise GraphDecodeError {
  let value = graph_json_number(node, "node", index)
  guard value >= 0.0 && value <= 2147483646.0 && @math.floor(value) == value else {
    raise InvalidDescription("Node index must be a non-negative integer", index)
  }
  value.to_int()
}

///|
/// Browser representation only: canonical authoring remains Array[DspNode].
fn decode_browser_graph(
  text : String,
) -> Array[@moondsp.DspNode] raise GraphDecodeError {
  let json = @json.parse(text) catch {
    _ => raise InvalidDescription("Invalid graph JSON", -1)
  }
  guard json is { "nodes": Array(nodes), .. } &&
    nodes.length() > 0 &&
    nodes.length() <= 64 else {
    raise InvalidDescription("A graph must contain 1 to 64 nodes", -1)
  }
  let decoded = []
  for index, node in nodes {
    let graph_node = match node {
      { "type": String("oscillator"), "waveform": String(wave), .. } => {
        let waveform = match wave {
          "sine" => @moondsp.Waveform::Sine
          "saw" => @moondsp.Waveform::Saw
          "square" => @moondsp.Waveform::Square
          "triangle" => @moondsp.Waveform::Triangle
          _ => raise InvalidDescription("Unknown oscillator waveform", index)
        }
        @moondsp.DspNode::oscillator(
          waveform,
          graph_json_number(node, "frequency", index),
        )
      }
      { "type": String("adsr"), .. } =>
        @moondsp.DspNode::adsr(
          attack_ms=graph_json_number(node, "attackMs", index),
          decay_ms=graph_json_number(node, "decayMs", index),
          sustain=graph_json_number(node, "sustain", index),
          release_ms=graph_json_number(node, "releaseMs", index),
        )
      { "type": String("biquad"), .. } => {
        let mode = match node {
          { "mode": String(mode), .. } =>
            match mode {
              "lowpass" => @moondsp.BiquadMode::LowPass
              "highpass" => @moondsp.BiquadMode::HighPass
              "bandpass" => @moondsp.BiquadMode::BandPass
              _ => raise InvalidDescription("Unknown biquad mode", index)
            }
          _ => raise InvalidDescription("Expected biquad mode", index)
        }
        @moondsp.DspNode::biquad(
          input=graph_json_input(node, nodes.length(), index),
          mode~,
          cutoff_hz=graph_json_number(node, "cutoff", index),
          q=graph_json_number(node, "q", index),
        )
      }
      { "type": String("gain"), .. } =>
        @moondsp.DspNode::gain(
          graph_json_input(node, nodes.length(), index),
          graph_json_number(node, "gain", index),
        )
      { "type": String("mul"), .. } =>
        @moondsp.DspNode::mul(
          graph_json_input_field(node, "input0", nodes.length(), index),
          graph_json_input_field(node, "input1", nodes.length(), index),
        )
      { "type": String("output"), .. } =>
        @moondsp.DspNode::output(graph_json_input(node, nodes.length(), index))
      _ =>
        raise InvalidDescription(
          "Unknown or incomplete node description", index,
        )
    }
    decoded.push(graph_node)
  }
  decoded
}

///|
fn decode_browser_controls(
  text : String,
) -> Array[@moondsp.GraphControl] raise GraphDecodeError {
  let json = @json.parse(text) catch {
    _ => raise InvalidDescription("Invalid graph controls JSON", -1)
  }
  guard json is Array(controls) &&
    controls.length() >= 1 &&
    controls.length() <= 64 else {
    raise InvalidDescription("Controls must contain 1 to 64 messages", -1)
  }
  let decoded = []
  for control in controls {
    // Diagnostics identify authoring nodes, never positions in this batch.
    let index = graph_json_node_index(control, -1)
    let graph_control = match control {
      { "type": String("gateOn"), .. } => @moondsp.GraphControl::gate_on(index)
      { "type": String("gateOff"), .. } =>
        @moondsp.GraphControl::gate_off(index)
      { "type": String("setParam"), .. } => {
        let slot = match control {
          { "slot": String(slot), .. } =>
            match slot {
              "value0" => @moondsp.GraphParamSlot::Value0
              "value1" => @moondsp.GraphParamSlot::Value1
              "value2" => @moondsp.GraphParamSlot::Value2
              "value3" => @moondsp.GraphParamSlot::Value3
              "delaySamples" => @moondsp.GraphParamSlot::DelaySamples
              _ =>
                raise InvalidDescription(
                  "Unknown control parameter slot", index,
                )
            }
          _ =>
            raise InvalidDescription("Expected control parameter slot", index)
        }
        @moondsp.GraphControl::set_param(
          index,
          slot,
          graph_json_number(control, "value", index),
        )
      }
      _ =>
        raise InvalidDescription("Unknown or incomplete graph control", index)
    }
    decoded.push(graph_control)
  }
  decoded
}
