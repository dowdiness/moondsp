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
fn graph_json_input(
  node : Json,
  count : Int,
  index : Int,
) -> Int raise GraphDecodeError {
  let value = graph_json_number(node, "input", index)
  guard value >= 0.0 &&
    value < count.to_double() &&
    value.to_int().to_double() == value else {
    raise InvalidDescription("Input index is outside the graph", index)
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
      { "type": String("gain"), .. } =>
        @moondsp.DspNode::gain(
          graph_json_input(node, nodes.length(), index),
          graph_json_number(node, "gain", index),
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
