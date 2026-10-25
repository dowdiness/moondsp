///|
// The browser wire format lowers directly to the internal graph model.
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
// References are browser authoring metadata, not additional DSP nodes.
// Binding IDs belong to this mount; parameter defaults stay in the nodes.
fn graph_json_param(
  node : Json,
  key : String,
  index : Int,
  slot : @model.GraphParamSlot,
  defaults : Map[String, Double],
  bindings : Map[String, Array[Int]],
  targets : Array[@runtime.GraphControlTarget],
) -> Double raise GraphDecodeError {
  guard node is Object(fields) else {
    raise InvalidDescription("Expected node object", index)
  }
  match fields.get(key) {
    Some(Object(reference)) => {
      guard reference.length() == 1 &&
        reference.get("param") is Some(String(name)) else {
        raise InvalidDescription(
          "Expected a parameter reference for \{key}",
          index,
        )
      }
      guard defaults.get(name) is Some(value) && bindings.get(name) is Some(ids) else {
        raise InvalidDescription("Unknown parameter \{name}", index)
      }
      ids.push(targets.length())
      targets.push(@runtime.GraphControlTarget::Param(index, slot))
      value
    }
    _ => graph_json_number(node, key, index)
  }
}

///|
/// Browser representation only: canonical authoring remains Array[DspNode].
fn decode_browser_graph(
  text : String,
  bindings~ : Map[String, Array[Int]],
  gates~ : Map[String, Int],
  targets~ : Array[@runtime.GraphControlTarget],
) -> Array[@model.DspNode] raise GraphDecodeError {
  let json = @json.parse(text) catch {
    _ => raise InvalidDescription("Invalid graph JSON", -1)
  }
  guard json is Object(fields) &&
    fields.get("nodes") is Some(Array(nodes)) &&
    nodes.length() > 0 &&
    nodes.length() <= 64 else {
    raise InvalidDescription("A graph must contain 1 to 64 nodes", -1)
  }
  let defaults : Map[String, Double] = Map([])
  match fields.get("params") {
    None => ()
    Some(Object(params)) => {
      guard params.length() <= 256 else {
        raise InvalidDescription(
          "A graph may declare at most 256 parameters", -1,
        )
      }
      for name, initial in params {
        guard initial is Number(value, ..) && @moondsp.is_finite(value) else {
          raise InvalidDescription(
            "Expected finite initial value for \{name}",
            -1,
          )
        }
        defaults[name] = value
        bindings[name] = []
      }
    }
    Some(_) =>
      raise InvalidDescription("Expected parameter declarations object", -1)
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
        @model.DspNode::oscillator(
          waveform,
          graph_json_param(
            node,
            "frequency",
            index,
            Value0,
            defaults,
            bindings,
            targets,
          ),
        )
      }
      { "type": String("adsr"), .. } =>
        @model.DspNode::adsr(
          attack_ms=graph_json_param(
            node,
            "attackMs",
            index,
            Value0,
            defaults,
            bindings,
            targets,
          ),
          decay_ms=graph_json_param(
            node,
            "decayMs",
            index,
            Value1,
            defaults,
            bindings,
            targets,
          ),
          sustain=graph_json_param(
            node,
            "sustain",
            index,
            Value2,
            defaults,
            bindings,
            targets,
          ),
          release_ms=graph_json_param(
            node,
            "releaseMs",
            index,
            Value3,
            defaults,
            bindings,
            targets,
          ),
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
        @model.DspNode::biquad(
          input=graph_json_input(node, nodes.length(), index),
          mode~,
          cutoff_hz=graph_json_param(
            node,
            "cutoff",
            index,
            Value0,
            defaults,
            bindings,
            targets,
          ),
          q=graph_json_param(
            node,
            "q",
            index,
            Value1,
            defaults,
            bindings,
            targets,
          ),
        )
      }
      { "type": String("gain"), .. } =>
        @model.DspNode::gain(
          graph_json_input(node, nodes.length(), index),
          graph_json_param(
            node,
            "gain",
            index,
            Value0,
            defaults,
            bindings,
            targets,
          ),
        )
      { "type": String("mul"), .. } =>
        @model.DspNode::mul(
          graph_json_input_field(node, "input0", nodes.length(), index),
          graph_json_input_field(node, "input1", nodes.length(), index),
        )
      { "type": String("output"), .. } =>
        @model.DspNode::output(graph_json_input(node, nodes.length(), index))
      _ =>
        raise InvalidDescription(
          "Unknown or incomplete node description", index,
        )
    }
    decoded.push(graph_node)
  }
  for name, targets in bindings {
    guard !targets.is_empty() else {
      raise InvalidDescription("Unused parameter \{name}", -1)
    }
  }
  match fields.get("gates") {
    None => ()
    Some(Object(names)) => {
      guard names.length() <= 64 else {
        raise InvalidDescription("A graph may declare at most 64 gates", -1)
      }
      for name, target in names {
        guard target is Number(index, ..) &&
          @moondsp.is_finite(index) &&
          index >= 0.0 &&
          index < nodes.length().to_double() &&
          @math.floor(index) == index else {
          raise InvalidDescription("Invalid gate target for \{name}", -1)
        }
        gates[name] = targets.length()
        targets.push(@runtime.GraphControlTarget::Gate(index.to_int()))
      }
    }
    Some(_) => raise InvalidDescription("Expected gate declarations object", -1)
  }
  decoded
}
