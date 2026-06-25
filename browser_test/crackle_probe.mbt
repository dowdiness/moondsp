///|
const CRACKLE_PROBE_METRIC_COUNT : Int = 14

///|
const CRACKLE_PROBE_METRIC_PEAK_ABS : Int = 0

///|
const CRACKLE_PROBE_METRIC_RMS : Int = 1

///|
const CRACKLE_PROBE_METRIC_MEAN : Int = 2

///|
const CRACKLE_PROBE_METRIC_NON_FINITE_COUNT : Int = 3

///|
const CRACKLE_PROBE_METRIC_SANITIZED_COUNT : Int = 4

///|
const CRACKLE_PROBE_METRIC_MAX_STEP_ABS : Int = 5

///|
const CRACKLE_PROBE_METRIC_BOUNDARY_STEP_ABS : Int = 6

///|
const CRACKLE_PROBE_METRIC_MAX_RESIDUAL_ABS : Int = 7

///|
const CRACKLE_PROBE_METRIC_RMS_RESIDUAL : Int = 8

///|
const CRACKLE_PROBE_METRIC_FIRST_SAMPLE : Int = 9

///|
const CRACKLE_PROBE_METRIC_LAST_SAMPLE : Int = 10

///|
const CRACKLE_PROBE_METRIC_BOUNDARY_STEP_DELTA : Int = 11

///|
const CRACKLE_PROBE_METRIC_MAX_STEP_INDEX : Int = 12

///|
const CRACKLE_PROBE_METRIC_MAX_RESIDUAL_INDEX : Int = 13

///|
const CRACKLE_PROBE_MAX_BLOCK_SIZE : Int = 4096

///|
const CRACKLE_PROBE_MAX_BLOCK_COUNT : Int = 4096

///|
const CRACKLE_PROBE_MAX_TOTAL_SAMPLES : Int = 1048576

///|
const CRACKLE_PROBE_ERROR_OK : Int = 0

///|
const CRACKLE_PROBE_ERROR_INVALID_ROUTE : Int = 1

///|
const CRACKLE_PROBE_ERROR_INVALID_WAVEFORM : Int = 2

///|
const CRACKLE_PROBE_ERROR_INVALID_FREQ : Int = 3

///|
const CRACKLE_PROBE_ERROR_INVALID_SAMPLE_RATE : Int = 4

///|
const CRACKLE_PROBE_ERROR_INVALID_BLOCK_SIZE : Int = 5

///|
const CRACKLE_PROBE_ERROR_INVALID_BLOCK_COUNT : Int = 6

///|
const CRACKLE_PROBE_ERROR_COMPILE_FAILED : Int = 7

///|
const CRACKLE_PROBE_ERROR_CONTROL_FAILED : Int = 8

///|
const CRACKLE_PROBE_ERROR_NOTE_ON_FAILED : Int = 9

///|
const CRACKLE_PROBE_ERROR_STREAM_NOT_INITIALIZED : Int = 10

///|
priv enum CrackleProbeStreamState {
  StreamDirect(
    Int,
    @moondsp.Waveform,
    Double,
    Double,
    @moondsp.Oscillator,
    @moondsp.Oscillator
  )
  StreamCompiled(
    @moondsp.Waveform,
    Double,
    @moondsp.CompiledDsp,
    @moondsp.Oscillator
  )
  StreamVoicePool(
    @moondsp.Waveform,
    Double,
    @moondsp.BoundVoicePool,
    @moondsp.AudioBuffer,
    @moondsp.Oscillator,
    Double
  )
  StreamBrowserSynthShape(@moondsp.BoundVoicePool, @moondsp.AudioBuffer)
}

///|
priv struct CrackleProbeValidatedInput {
  route_id : Int
  waveform : @moondsp.Waveform
  freq_hz : Double
  sample_rate : Double
  block_size : Int
}

///|
let crackle_probe_metrics : @ref.Ref[FixedArray[Double]?] = @ref.new(None)

///|
let crackle_probe_output : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let crackle_probe_reference : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let crackle_probe_residual : @ref.Ref[@moondsp.AudioBuffer?] = @ref.new(None)

///|
let crackle_probe_blocks : @ref.Ref[Int] = @ref.new(0)

///|
let crackle_probe_last_error_code : @ref.Ref[Int] = @ref.new(0)

///|
let crackle_probe_stream_state : @ref.Ref[CrackleProbeStreamState?] = @ref.new(
  None,
)

///|
let crackle_probe_stream_context : @ref.Ref[@moondsp.DspContext?] = @ref.new(
  None,
)

///|
let crackle_probe_stream_block_size : @ref.Ref[Int] = @ref.new(0)

///|
let crackle_probe_stream_has_previous : @ref.Ref[Bool] = @ref.new(false)

///|
let crackle_probe_stream_previous_output : @ref.Ref[Double] = @ref.new(0.0)

///|
let crackle_probe_stream_previous_reference : @ref.Ref[Double] = @ref.new(0.0)

///|
pub fn crackle_probe_reset() -> Unit {
  crackle_probe_clear_results()
  crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_OK
}

///|
/// Run a Phase-1 crackle probe. Route ids:
/// 0 = direct tick_waveform loop; 1 = direct process_waveform;
/// 2 = CompiledDsp oscillator(waveform, freq);
/// 3 = CompiledDsp oscillator(waveform, placeholder) + Value0 control;
/// 4 = CompiledDsp oscillator_from(constant(freq), waveform);
/// 5 = CompiledDsp oscillator_from(controlled constant, waveform);
/// 6 = BoundVoicePool note_on_controls({"note": freq}) binding to Value0;
/// 7 = BoundVoicePool browser-synth-shape clone with selectable waveform.
/// Waveform ids: 0=Sine, 1=Saw, 2=Square, 3=Triangle.
/// Route 7 has no direct oscillator reference; residual metrics are disabled
/// by copying its output into the reference buffer before metric collection.
pub fn crackle_probe_run(
  route_id : Int,
  waveform_id : Int,
  freq_hz : Double,
  sample_rate : Double,
  block_size : Int,
  block_count : Int,
) -> Bool {
  crackle_probe_clear_results()
  crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_OK
  let input = match
    crackle_probe_validate_inputs(
      route_id,
      waveform_id,
      freq_hz,
      sample_rate,
      block_size,
      block_count~,
    ) {
    Some(value) => value
    None => return false
  }

  let context = @moondsp.DspContext::new(
    sample_rate=input.sample_rate,
    block_size=input.block_size,
  )
  let output = @moondsp.AudioBuffer::filled(input.block_size)
  let reference = @moondsp.AudioBuffer::filled(input.block_size)
  let residual = @moondsp.AudioBuffer::filled(input.block_size)
  let metrics = FixedArray::make(block_count * CRACKLE_PROBE_METRIC_COUNT, 0.0)
  let ok = if input.route_id == 0 || input.route_id == 1 {
    crackle_probe_run_direct(
      input.route_id,
      input.waveform,
      input.freq_hz,
      input.sample_rate,
      context,
      input.block_size,
      block_count,
      output,
      reference,
      residual,
      metrics,
    )
  } else if input.route_id <= 5 {
    crackle_probe_run_compiled(
      input.route_id,
      input.waveform,
      input.freq_hz,
      context,
      input.block_size,
      block_count,
      output,
      reference,
      residual,
      metrics,
    )
  } else if input.route_id == 6 {
    crackle_probe_run_voice_pool(
      input.waveform,
      input.freq_hz,
      context,
      input.block_size,
      block_count,
      output,
      reference,
      residual,
      metrics,
    )
  } else {
    crackle_probe_run_browser_synth_shape(
      input.waveform,
      input.freq_hz,
      context,
      input.block_size,
      block_count,
      output,
      reference,
      residual,
      metrics,
    )
  }
  if ok {
    crackle_probe_metrics.val = Some(metrics)
    crackle_probe_output.val = Some(output)
    crackle_probe_reference.val = Some(reference)
    crackle_probe_residual.val = Some(residual)
    crackle_probe_blocks.val = block_count
    crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_OK
  }
  ok
}

///|
/// Initialize a streaming crackle probe. Each subsequent
/// `crackle_probe_stream_process` call advances exactly one render quantum and
/// appends one block of metrics readable through `crackle_probe_metric`.
pub fn crackle_probe_stream_init(
  route_id : Int,
  waveform_id : Int,
  freq_hz : Double,
  sample_rate : Double,
  block_size : Int,
) -> Bool {
  crackle_probe_clear_results()
  crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_OK
  let input = match
    crackle_probe_validate_inputs(
      route_id, waveform_id, freq_hz, sample_rate, block_size,
    ) {
    Some(value) => value
    None => return false
  }

  let context = @moondsp.DspContext::new(
    sample_rate=input.sample_rate,
    block_size=input.block_size,
  )
  let state = if input.route_id == 0 || input.route_id == 1 {
    Some(
      StreamDirect(
        input.route_id,
        input.waveform,
        input.freq_hz,
        input.sample_rate,
        @moondsp.Oscillator::new(),
        @moondsp.Oscillator::new(),
      ),
    )
  } else if input.route_id <= 5 {
    crackle_probe_stream_compiled_state(
      input.route_id,
      input.waveform,
      input.freq_hz,
      context,
    )
  } else if input.route_id == 6 {
    crackle_probe_stream_voice_pool_state(
      input.waveform,
      input.freq_hz,
      context,
      input.block_size,
    )
  } else {
    crackle_probe_stream_browser_synth_shape_state(
      input.waveform,
      input.freq_hz,
      context,
      input.block_size,
    )
  }

  match state {
    Some(stream_state) => {
      crackle_probe_stream_state.val = Some(stream_state)
      crackle_probe_stream_context.val = Some(context)
      crackle_probe_stream_block_size.val = input.block_size
      crackle_probe_stream_has_previous.val = false
      crackle_probe_stream_previous_output.val = 0.0
      crackle_probe_stream_previous_reference.val = 0.0
      crackle_probe_metrics.val = Some(
        FixedArray::make(
          CRACKLE_PROBE_MAX_BLOCK_COUNT * CRACKLE_PROBE_METRIC_COUNT,
          0.0,
        ),
      )
      crackle_probe_output.val = Some(
        @moondsp.AudioBuffer::filled(input.block_size),
      )
      crackle_probe_reference.val = Some(
        @moondsp.AudioBuffer::filled(input.block_size),
      )
      crackle_probe_residual.val = Some(
        @moondsp.AudioBuffer::filled(input.block_size),
      )
      crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_OK
      true
    }
    None => false
  }
}

///|
/// Process one streaming render quantum initialized by
/// `crackle_probe_stream_init`.
pub fn crackle_probe_stream_process() -> Bool {
  match crackle_probe_stream_state.val {
    Some(stream_state) =>
      match
        (
          crackle_probe_stream_context.val,
          crackle_probe_output.val,
          crackle_probe_reference.val,
          crackle_probe_residual.val,
          crackle_probe_metrics.val,
        ) {
        (
          Some(context),
          Some(output),
          Some(reference),
          Some(residual),
          Some(metrics),
        ) => {
          let block_index = crackle_probe_blocks.val
          if block_index < 0 || block_index >= CRACKLE_PROBE_MAX_BLOCK_COUNT {
            crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_INVALID_BLOCK_COUNT
            return false
          }
          let block_size = crackle_probe_stream_block_size.val
          let sanitized_count = match stream_state {
            StreamDirect(
              route_id,
              waveform,
              freq_hz,
              sample_rate,
              output_osc,
              reference_osc
            ) => {
              if route_id == 0 {
                for i in 0..<block_size {
                  output.set(
                    i,
                    output_osc.tick_waveform(waveform~, freq_hz~, sample_rate~),
                  )
                }
              } else {
                output_osc.process_waveform(
                  context~,
                  output~,
                  waveform~,
                  freq_hz~,
                )
              }
              reference_osc.process_waveform(
                context~,
                output=reference,
                waveform~,
                freq_hz~,
              )
              0
            }
            StreamCompiled(waveform, freq_hz, graph, reference_osc) => {
              graph.process(context, output)
              reference_osc.process_waveform(
                context~,
                output=reference,
                waveform~,
                freq_hz~,
              )
              graph.last_sanitized_count()
            }
            StreamVoicePool(
              waveform,
              freq_hz,
              pool,
              right,
              reference_osc,
              left_gain
            ) => {
              output.fill(0.0)
              right.fill(0.0)
              pool.process(context, output, right)
              reference_osc.process_waveform(
                context~,
                output=reference,
                waveform~,
                freq_hz~,
              )
              crackle_probe_scale_buffer(reference, block_size, left_gain)
              pool.last_sanitized_count()
            }
            StreamBrowserSynthShape(pool, right) => {
              output.fill(0.0)
              right.fill(0.0)
              pool.process(context, output, right)
              crackle_probe_copy_buffer(output, reference, block_size)
              pool.last_sanitized_count()
            }
          }
          crackle_probe_write_metrics(
            metrics,
            block_index,
            output,
            reference,
            residual,
            block_size,
            sanitized_count,
            crackle_probe_stream_has_previous.val,
            crackle_probe_stream_previous_output.val,
            crackle_probe_stream_previous_reference.val,
          )
          crackle_probe_stream_previous_output.val = output.get(block_size - 1)
          crackle_probe_stream_previous_reference.val = reference.get(
            block_size - 1,
          )
          crackle_probe_stream_has_previous.val = true
          crackle_probe_blocks.val = block_index + 1
          crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_OK
          true
        }
        _ => {
          crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_STREAM_NOT_INITIALIZED
          false
        }
      }
    None => {
      crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_STREAM_NOT_INITIALIZED
      false
    }
  }
}

///|
/// Read one per-block metric. Metric ids:
/// 0 peak_abs; 1 rms; 2 mean; 3 nan_or_inf_count after buffer writes;
/// 4 CompiledDsp sanitized_count; 5 max_step_abs within block;
/// 6 raw block_boundary_step_abs; 7 max_abs_residual_vs_reference;
/// 8 rms_residual_vs_reference; 9 first_sample; 10 last_sample;
/// 11 absolute boundary-step difference vs reference; 12 max_step_index;
/// 13 max_residual_index.
pub fn crackle_probe_metric(block_index : Int, metric_id : Int) -> Double {
  match crackle_probe_metrics.val {
    Some(metrics) =>
      if block_index >= 0 &&
        block_index < crackle_probe_blocks.val &&
        metric_id >= 0 &&
        metric_id < CRACKLE_PROBE_METRIC_COUNT {
        metrics[block_index * CRACKLE_PROBE_METRIC_COUNT + metric_id]
      } else {
        0.0
      }
    None => 0.0
  }
}

///|
/// Read a sample from the last processed block: 0=output, 1=reference,
/// 2=residual. Per-block metrics remain available through `crackle_probe_metric`.
pub fn crackle_probe_sample(kind_id : Int, sample_index : Int) -> Double {
  let maybe_buffer = match kind_id {
    0 => crackle_probe_output.val
    1 => crackle_probe_reference.val
    2 => crackle_probe_residual.val
    _ => None
  }
  match maybe_buffer {
    Some(buffer) =>
      if sample_index >= 0 && sample_index < buffer.length() {
        buffer.get(sample_index)
      } else {
        0.0
      }
    None => 0.0
  }
}

///|
pub fn crackle_probe_last_error() -> Int {
  crackle_probe_last_error_code.val
}

///|
pub fn crackle_probe_block_count() -> Int {
  crackle_probe_blocks.val
}

///|
fn crackle_probe_clear_results() -> Unit {
  crackle_probe_metrics.val = None
  crackle_probe_output.val = None
  crackle_probe_reference.val = None
  crackle_probe_residual.val = None
  crackle_probe_blocks.val = 0
  crackle_probe_stream_state.val = None
  crackle_probe_stream_context.val = None
  crackle_probe_stream_block_size.val = 0
  crackle_probe_stream_has_previous.val = false
  crackle_probe_stream_previous_output.val = 0.0
  crackle_probe_stream_previous_reference.val = 0.0
}

///|
fn crackle_probe_validate_inputs(
  route_id : Int,
  waveform_id : Int,
  freq_hz : Double,
  sample_rate : Double,
  block_size : Int,
  block_count? : Int,
) -> CrackleProbeValidatedInput? {
  if route_id < 0 || route_id > 7 {
    crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_INVALID_ROUTE
    return None
  }
  let waveform = match crackle_probe_waveform(waveform_id) {
    Some(value) => value
    None => {
      crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_INVALID_WAVEFORM
      return None
    }
  }
  if !@moondsp.is_finite(freq_hz) || freq_hz <= 0.0 {
    crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_INVALID_FREQ
    return None
  }
  if !@moondsp.is_finite(sample_rate) || sample_rate <= 0.0 {
    crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_INVALID_SAMPLE_RATE
    return None
  }
  if block_size <= 0 || block_size > CRACKLE_PROBE_MAX_BLOCK_SIZE {
    crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_INVALID_BLOCK_SIZE
    return None
  }
  match block_count {
    Some(count) => {
      if count <= 0 || count > CRACKLE_PROBE_MAX_BLOCK_COUNT {
        crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_INVALID_BLOCK_COUNT
        return None
      }
      if count > CRACKLE_PROBE_MAX_TOTAL_SAMPLES / block_size {
        crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_INVALID_BLOCK_COUNT
        return None
      }
    }
    None => ()
  }
  Some({ route_id, waveform, freq_hz, sample_rate, block_size })
}

///|
fn crackle_probe_waveform(id : Int) -> @moondsp.Waveform? {
  match id {
    0 => Some(@moondsp.Waveform::Sine)
    1 => Some(@moondsp.Waveform::Saw)
    2 => Some(@moondsp.Waveform::Square)
    3 => Some(@moondsp.Waveform::Triangle)
    _ => None
  }
}

///|
fn crackle_probe_run_direct(
  route_id : Int,
  waveform : @moondsp.Waveform,
  freq_hz : Double,
  sample_rate : Double,
  context : @moondsp.DspContext,
  block_size : Int,
  block_count : Int,
  output : @moondsp.AudioBuffer,
  reference : @moondsp.AudioBuffer,
  residual : @moondsp.AudioBuffer,
  metrics : FixedArray[Double],
) -> Bool {
  let output_osc = @moondsp.Oscillator::new()
  let reference_osc = @moondsp.Oscillator::new()
  let mut has_previous = false
  let mut previous_output = 0.0
  let mut previous_reference = 0.0
  for block in 0..<block_count {
    if route_id == 0 {
      for i in 0..<block_size {
        output.set(
          i,
          output_osc.tick_waveform(waveform~, freq_hz~, sample_rate~),
        )
      }
    } else {
      output_osc.process_waveform(context~, output~, waveform~, freq_hz~)
    }
    reference_osc.process_waveform(
      context~,
      output=reference,
      waveform~,
      freq_hz~,
    )
    crackle_probe_write_metrics(
      metrics, block, output, reference, residual, block_size, 0, has_previous, previous_output,
      previous_reference,
    )
    previous_output = output.get(block_size - 1)
    previous_reference = reference.get(block_size - 1)
    has_previous = true
  }
  true
}

///|
fn crackle_probe_run_compiled(
  route_id : Int,
  waveform : @moondsp.Waveform,
  freq_hz : Double,
  context : @moondsp.DspContext,
  block_size : Int,
  block_count : Int,
  output : @moondsp.AudioBuffer,
  reference : @moondsp.AudioBuffer,
  residual : @moondsp.AudioBuffer,
  metrics : FixedArray[Double],
) -> Bool {
  match
    crackle_probe_stream_compiled_state(route_id, waveform, freq_hz, context) {
    Some(StreamCompiled(stream_waveform, stream_freq_hz, graph, reference_osc)) => {
      let mut has_previous = false
      let mut previous_output = 0.0
      let mut previous_reference = 0.0
      for block in 0..<block_count {
        graph.process(context, output)
        reference_osc.process_waveform(
          context~,
          output=reference,
          waveform=stream_waveform,
          freq_hz=stream_freq_hz,
        )
        crackle_probe_write_metrics(
          metrics,
          block,
          output,
          reference,
          residual,
          block_size,
          graph.last_sanitized_count(),
          has_previous,
          previous_output,
          previous_reference,
        )
        previous_output = output.get(block_size - 1)
        previous_reference = reference.get(block_size - 1)
        has_previous = true
      }
      true
    }
    _ => false
  }
}

///|
fn crackle_probe_run_voice_pool(
  waveform : @moondsp.Waveform,
  freq_hz : Double,
  context : @moondsp.DspContext,
  block_size : Int,
  block_count : Int,
  output : @moondsp.AudioBuffer,
  reference : @moondsp.AudioBuffer,
  residual : @moondsp.AudioBuffer,
  metrics : FixedArray[Double],
) -> Bool {
  match
    crackle_probe_stream_voice_pool_state(
      waveform, freq_hz, context, block_size,
    ) {
    Some(
      StreamVoicePool(
        stream_waveform,
        stream_freq_hz,
        pool,
        right,
        reference_osc,
        left_gain
      )
    ) => {
      let mut has_previous = false
      let mut previous_output = 0.0
      let mut previous_reference = 0.0
      for block in 0..<block_count {
        output.fill(0.0)
        right.fill(0.0)
        pool.process(context, output, right)
        reference_osc.process_waveform(
          context~,
          output=reference,
          waveform=stream_waveform,
          freq_hz=stream_freq_hz,
        )
        crackle_probe_scale_buffer(reference, block_size, left_gain)
        crackle_probe_write_metrics(
          metrics,
          block,
          output,
          reference,
          residual,
          block_size,
          pool.last_sanitized_count(),
          has_previous,
          previous_output,
          previous_reference,
        )
        previous_output = output.get(block_size - 1)
        previous_reference = reference.get(block_size - 1)
        has_previous = true
      }
      true
    }
    _ => false
  }
}

///|
fn crackle_probe_run_browser_synth_shape(
  waveform : @moondsp.Waveform,
  freq_hz : Double,
  context : @moondsp.DspContext,
  block_size : Int,
  block_count : Int,
  output : @moondsp.AudioBuffer,
  reference : @moondsp.AudioBuffer,
  residual : @moondsp.AudioBuffer,
  metrics : FixedArray[Double],
) -> Bool {
  match
    crackle_probe_stream_browser_synth_shape_state(
      waveform, freq_hz, context, block_size,
    ) {
    Some(StreamBrowserSynthShape(pool, right)) => {
      let mut has_previous = false
      let mut previous_output = 0.0
      let mut previous_reference = 0.0
      for block in 0..<block_count {
        output.fill(0.0)
        right.fill(0.0)
        pool.process(context, output, right)
        crackle_probe_copy_buffer(output, reference, block_size)
        crackle_probe_write_metrics(
          metrics,
          block,
          output,
          reference,
          residual,
          block_size,
          pool.last_sanitized_count(),
          has_previous,
          previous_output,
          previous_reference,
        )
        previous_output = output.get(block_size - 1)
        previous_reference = reference.get(block_size - 1)
        has_previous = true
      }
      true
    }
    _ => false
  }
}

///|
fn crackle_probe_stream_compiled_state(
  route_id : Int,
  waveform : @moondsp.Waveform,
  freq_hz : Double,
  context : @moondsp.DspContext,
) -> CrackleProbeStreamState? {
  let nodes = match route_id {
    2 =>
      [
        @moondsp.DspNode::oscillator(waveform, freq_hz),
        @moondsp.DspNode::output(0),
      ]
    3 =>
      [@moondsp.DspNode::oscillator(waveform, 0.0), @moondsp.DspNode::output(0)]
    4 =>
      [
        @moondsp.DspNode::constant(freq_hz),
        @moondsp.DspNode::oscillator_from(0, waveform),
        @moondsp.DspNode::output(1),
      ]
    5 =>
      [
        @moondsp.DspNode::constant(0.0),
        @moondsp.DspNode::oscillator_from(0, waveform),
        @moondsp.DspNode::output(1),
      ]
    _ => return None
  }
  match
    @moondsp.CompiledDsp::compile(
      @moondsp.CompiledTemplate::analyze(nodes),
      context,
    ) {
    Some(graph) => {
      if route_id == 3 || route_id == 5 {
        if graph.apply_controls([
            @moondsp.GraphControl::set_param(
              0,
              @moondsp.GraphParamSlot::Value0,
              freq_hz,
            ),
          ])
          is Err(_) {
          crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_CONTROL_FAILED
          return None
        }
      }
      Some(StreamCompiled(waveform, freq_hz, graph, @moondsp.Oscillator::new()))
    }
    None => {
      crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_COMPILE_FAILED
      None
    }
  }
}

///|
fn crackle_probe_stream_voice_pool_state(
  waveform : @moondsp.Waveform,
  freq_hz : Double,
  context : @moondsp.DspContext,
  block_size : Int,
) -> CrackleProbeStreamState? {
  let template = @moondsp.CompiledTemplate::analyze([
    @moondsp.DspNode::oscillator(waveform, 0.0),
    @moondsp.DspNode::output(0),
  ])
  match
    @moondsp.BoundVoicePool::new(
      template,
      context,
      @moondsp.ControlBindingBuilder::new().bind(
        key="note",
        node_index=0,
        slot=@moondsp.GraphParamSlot::Value0,
      ),
      max_voices=1,
    ) {
    Ok(pool) => {
      let controls : Map[String, Double] = { "note": freq_hz }
      if pool.note_on_controls(controls) is None {
        crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_NOTE_ON_FAILED
        return None
      }
      Some(
        StreamVoicePool(
          waveform,
          freq_hz,
          pool,
          @moondsp.AudioBuffer::filled(block_size),
          @moondsp.Oscillator::new(),
          @moondsp.pan_left_gain(0.0),
        ),
      )
    }
    Err(_) => {
      crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_COMPILE_FAILED
      None
    }
  }
}

///|
fn crackle_probe_stream_browser_synth_shape_state(
  waveform : @moondsp.Waveform,
  freq_hz : Double,
  context : @moondsp.DspContext,
  block_size : Int,
) -> CrackleProbeStreamState? {
  let template = @moondsp.CompiledTemplate::analyze([
    @moondsp.DspNode::oscillator(waveform, 0.0),
    @moondsp.DspNode::adsr(
      attack_ms=2.0,
      decay_ms=800.0,
      sustain=0.08,
      release_ms=20.0,
    ),
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=0.5),
    @moondsp.DspNode::biquad(
      input=2,
      mode=@moondsp.BiquadMode::LowPass,
      cutoff_hz=8000.0,
      q=0.707,
    ),
    @moondsp.DspNode::output(3),
  ])
  match
    @moondsp.BoundVoicePool::new(
      template,
      context,
      @moondsp.ControlBindingBuilder::new().bind(
        key="note",
        node_index=0,
        slot=@moondsp.GraphParamSlot::Value0,
      ),
      max_voices=1,
    ) {
    Ok(pool) => {
      let controls : Map[String, Double] = { "note": freq_hz }
      if pool.note_on_controls(controls) is None {
        crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_NOTE_ON_FAILED
        return None
      }
      Some(
        StreamBrowserSynthShape(pool, @moondsp.AudioBuffer::filled(block_size)),
      )
    }
    Err(_) => {
      crackle_probe_last_error_code.val = CRACKLE_PROBE_ERROR_COMPILE_FAILED
      None
    }
  }
}

///|
fn crackle_probe_copy_buffer(
  source : @moondsp.AudioBuffer,
  target : @moondsp.AudioBuffer,
  block_size : Int,
) -> Unit {
  for i in 0..<block_size {
    target.set(i, source.get(i))
  }
}

///|
fn crackle_probe_scale_buffer(
  buffer : @moondsp.AudioBuffer,
  block_size : Int,
  gain : Double,
) -> Unit {
  for i in 0..<block_size {
    buffer.set(i, buffer.get(i) * gain)
  }
}

///|
fn crackle_probe_write_metrics(
  metrics : FixedArray[Double],
  block_index : Int,
  output : @moondsp.AudioBuffer,
  reference : @moondsp.AudioBuffer,
  residual : @moondsp.AudioBuffer,
  block_size : Int,
  sanitized_count : Int,
  has_previous : Bool,
  previous_output : Double,
  previous_reference : Double,
) -> Unit {
  let mut peak_abs = 0.0
  let mut sum = 0.0
  let mut sum_sq = 0.0
  let mut nan_or_inf_count = 0
  let mut max_step_abs = 0.0
  let mut max_step_index = 0
  let mut max_residual_abs = 0.0
  let mut max_residual_index = 0
  let mut residual_sum_sq = 0.0
  for i in 0..<block_size {
    let sample = output.get(i)
    let reference_sample = reference.get(i)
    let residual_sample = sample - reference_sample
    residual.set(i, residual_sample)
    if !@moondsp.is_finite(sample) {
      nan_or_inf_count = nan_or_inf_count + 1
    }
    let abs_sample = sample.abs()
    if abs_sample > peak_abs {
      peak_abs = abs_sample
    }
    sum = sum + sample
    sum_sq = sum_sq + sample * sample
    let abs_residual = residual_sample.abs()
    if abs_residual > max_residual_abs {
      max_residual_abs = abs_residual
      max_residual_index = i
    }
    residual_sum_sq = residual_sum_sq + residual_sample * residual_sample
    if i > 0 {
      let step = (sample - output.get(i - 1)).abs()
      if step > max_step_abs {
        max_step_abs = step
        max_step_index = i
      }
    }
  }
  let count = block_size.to_double()
  let boundary_step_abs = if has_previous {
    (output.get(0) - previous_output).abs()
  } else {
    0.0
  }
  let reference_boundary_step_abs = if has_previous {
    (reference.get(0) - previous_reference).abs()
  } else {
    0.0
  }
  let boundary_step_delta = (boundary_step_abs - reference_boundary_step_abs).abs()
  let base = block_index * CRACKLE_PROBE_METRIC_COUNT
  metrics[base + CRACKLE_PROBE_METRIC_PEAK_ABS] = peak_abs
  metrics[base + CRACKLE_PROBE_METRIC_RMS] = (sum_sq / count).sqrt()
  metrics[base + CRACKLE_PROBE_METRIC_MEAN] = sum / count
  metrics[base + CRACKLE_PROBE_METRIC_NON_FINITE_COUNT] = nan_or_inf_count.to_double()
  metrics[base + CRACKLE_PROBE_METRIC_SANITIZED_COUNT] = sanitized_count.to_double()
  metrics[base + CRACKLE_PROBE_METRIC_MAX_STEP_ABS] = max_step_abs
  metrics[base + CRACKLE_PROBE_METRIC_BOUNDARY_STEP_ABS] = boundary_step_abs
  metrics[base + CRACKLE_PROBE_METRIC_MAX_RESIDUAL_ABS] = max_residual_abs
  metrics[base + CRACKLE_PROBE_METRIC_RMS_RESIDUAL] = (residual_sum_sq / count).sqrt()
  metrics[base + CRACKLE_PROBE_METRIC_FIRST_SAMPLE] = output.get(0)
  metrics[base + CRACKLE_PROBE_METRIC_LAST_SAMPLE] = output.get(block_size - 1)
  metrics[base + CRACKLE_PROBE_METRIC_BOUNDARY_STEP_DELTA] = boundary_step_delta
  metrics[base + CRACKLE_PROBE_METRIC_MAX_STEP_INDEX] = max_step_index.to_double()
  metrics[base + CRACKLE_PROBE_METRIC_MAX_RESIDUAL_INDEX] = max_residual_index.to_double()
}
