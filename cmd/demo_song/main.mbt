///|
const SAMPLE_RATE : Double = 48000.0

///|
const BLOCK : Int32 = 128

///|
/// Seconds of tail rendered after the song ends, for releases and the room.
const TAIL_SECONDS : Double = 3.0

///|
/// A filtered-noise texture with an echo, written once against the tagless
/// traits and interpreted here by `GraphBuilder`. Node indices: [0] noise,
/// [1] band-pass, [2] delay, [3] mix, [4] gain, [5] output.
fn[T : @moondsp.FilterSym + @moondsp.DelaySym] noise_texture(
  seed : UInt32,
  cutoff : Double,
  q : Double,
  delay_samples : Int32,
  feedback : Double,
) -> T {
  let source : T = @moondsp.DspSym::noise(seed)
  let band = @moondsp.FilterSym::biquad(
    source,
    @moondsp.BiquadMode::BandPass,
    cutoff,
    q,
  )
  let echo = @moondsp.DelaySym::delay(band, 48000, delay_samples, feedback)
  let wet = @moondsp.ArithSym::mix(band, echo)
  @moondsp.DspSym::output(@moondsp.DspSym::gain(wet, 0.5))
}

///|
/// A stereo drone of a fifth (A2 + E3), low-passed, panned and echoed by a
/// stereo delay, built with `GraphBuilder` method chains.
fn stereo_drone() -> @moondsp.GraphBuilder {
  let root = @moondsp.GraphBuilder::constant(110.0).oscillator(
    @moondsp.Waveform::Triangle,
  )
  let fifth = @moondsp.GraphBuilder::constant(164.81).oscillator(
    @moondsp.Waveform::Triangle,
  )
  root
  .mix(fifth)
  .biquad(@moondsp.BiquadMode::LowPass, 900.0, 0.7)
  .pan(-0.2)
  .stereo_delay(36000, 13800, 0.5)
  .stereo_gain(0.35)
  .stereo_output()
}

///|
fn clamp01(x : Double) -> Double {
  if x < 0.0 {
    0.0
  } else if x > 1.0 {
    1.0
  } else {
    x
  }
}

///|
let hex_digits : String = "0123456789abcdef"

///|
fn write_s16(out : StringBuilder, value : Double) -> Unit {
  let clamped = if value > 1.0 {
    1.0
  } else if value < -1.0 {
    -1.0
  } else {
    value
  }
  let v = (clamped * 32767.0).round().to_int()
  let u = v & 0xffff
  let lo = u & 0xff
  let hi = (u >> 8) & 0xff
  out.write_char(hex_digits[lo >> 4].unsafe_to_char())
  out.write_char(hex_digits[lo & 15].unsafe_to_char())
  out.write_char(hex_digits[hi >> 4].unsafe_to_char())
  out.write_char(hex_digits[hi & 15].unsafe_to_char())
}

///|
/// Render the demo song. Lines starting with `#` are diagnostics; every
/// other line is one block of 16-bit little-endian stereo PCM in hex, which
/// `render.py` turns into a WAV file.
fn main {
  let store = @moondsp.SampleStore(entries=8, max_length=96000, capacity=200000)
  for problem in register_samples(store, SAMPLE_RATE) {
    println("# sample problem: \{problem}")
  }
  let ctx = @moondsp.DspContext(
    sample_rate=SAMPLE_RATE,
    block_size=BLOCK,
    samples=store,
  )

  // 1. The score: mini notation -> song -> scheduler -> voices -> graphs.
  let player = @player.Player(
    ctx,
    drum=d => @moondsp.AnalyzedGraph::analyze(drum_graph(d)),
    instrument=instrument_voice,
    sampler=sampler_voice(),
  ) catch {
    e => {
      println("# FATAL player: \{e.message()}")
      return
    }
  }
  player.set_gain(0.46)
  player.restart(@mini.PlaybackInput::text(song_source)) catch {
    e => {
      println("# FATAL score: \{e.message()}")
      return
    }
  }
  println("# mode=\{player.mode().to_repr()} state=\{player.state().to_repr()}")

  // 2. A riser texture on a hot-swappable mono graph, retuned every block.
  let riser_graph : @moondsp.GraphBuilder = noise_texture(
    424242U, 300.0, 4.0, 9000, 0.55,
  )
  let shimmer_graph : @moondsp.GraphBuilder = noise_texture(
    777U, 5200.0, 8.0, 18000, 0.6,
  )
  guard @moondsp.Dsp::compile(riser_graph.analyze(), ctx) is Some(riser_dsp) else {
    println("# FATAL riser graph did not compile")
    return
  }
  guard @moondsp.Dsp::compile(shimmer_graph.analyze(), ctx) is Some(shimmer_dsp) else {
    println("# FATAL shimmer graph did not compile")
    return
  }
  let riser = @moondsp.DspHotSwap::from_graph(riser_dsp, crossfade_samples=9600)
  let mut swapped = false

  // 3. A stereo drone compiled as a StereoDsp.
  guard @moondsp.StereoDsp::compile(stereo_drone().analyze(), ctx)
    is Some(drone) else {
    println("# FATAL drone graph did not compile")
    return
  }

  // 4. A sub bass on the host-independent GraphEngine, played in the outro.
  let engine = @moondsp.GraphEngine(ctx) catch {
    e => {
      println("# FATAL engine: \{e.to_repr()}")
      return
    }
  }
  let sub = engine.mount([
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, 55.0),
    @moondsp.DspNode::gain(0, 0.18),
    @moondsp.DspNode::output(1),
  ]) catch {
    e => {
      println("# FATAL mount: \{e.to_repr()}")
      return
    }
  }
  let mut sub_playing = false

  let riser_buf = ctx.make_buffer()
  let drone_l = ctx.make_buffer()
  let drone_r = ctx.make_buffer()
  let sub_buf = ctx.make_buffer()
  let max_blocks = (SAMPLE_RATE * 120.0 / BLOCK.to_double()).to_int()
  let tail_blocks = (SAMPLE_RATE * TAIL_SECONDS / BLOCK.to_double()).to_int()
  let mut ended_at = -1
  let mut blocks = 0
  let mut peak = 0.0
  let mut clipped = 0
  let mut control_errors = 0
  let mut last_section = -1
  let line = StringBuilder()
  while blocks < max_blocks {
    let cycle = player.cycle_position()
    // Host automation from the musical position.
    let cutoff = 300.0 + 3700.0 * clamp01((cycle - 14.0) / 6.0)
    if riser.set_param(1, @moondsp.GraphParamSlot::Value0, cutoff) is Err(_) {
      control_errors += 1
    }
    if !swapped && cycle >= 20.0 {
      match riser.queue_swap(shimmer_dsp) {
        Ok(_) => swapped = true
        Err(e) => {
          println("# hot swap refused: \{e}")
          swapped = true
        }
      }
    }
    if !sub_playing && cycle >= 28.0 {
      sub.play() catch {
        e => println("# sub play failed: \{e.to_repr()}")
      }
      sub_playing = true
    }
    let riser_level = if cycle < 14.0 {
      0.0
    } else if cycle < 20.0 {
      0.5 * clamp01((cycle - 14.0) / 6.0)
    } else {
      0.5 * (1.0 - clamp01((cycle - 20.0) / 6.0))
    }
    let drone_level = if cycle < 8.0 {
      clamp01(cycle / 4.0)
    } else if cycle >= 28.0 {
      clamp01((32.0 - cycle) / 4.0)
    } else {
      0.0
    }
    let section = cycle.to_int()
    if section != last_section && section % 2 == 0 {
      println("# cycle \{section} state=\{player.state().to_repr()}")
      last_section = section
    }

    if !player.process() {
      println("# FAULT \{player.fault().unwrap_or("unknown")}")
      break
    }
    riser.process(ctx, riser_buf)
    drone.process(ctx, drone_l, drone_r)
    engine.process(sub_buf) catch {
      e => println("# engine process failed: \{e.to_repr()}")
    }
    let left = player.left()
    let right = player.right()
    line.reset()
    for i in 0..<BLOCK {
      let shared = riser_level * riser_buf.get(i) + sub_buf.get(i)
      let l = left.get(i) + shared + drone_level * drone_l.get(i)
      let r = right.get(i) + shared + drone_level * drone_r.get(i)
      for v in [l, r] {
        let a = v.abs()
        if a > peak {
          peak = a
        }
        if a > 1.0 {
          clipped += 1
        }
      }
      write_s16(line, l)
      write_s16(line, r)
    }
    println(line.to_string())
    blocks += 1
    if ended_at < 0 && player.state() is Ended {
      ended_at = blocks
      println(
        "# song ended at block \{blocks} (\{blocks.to_double() * BLOCK.to_double() / SAMPLE_RATE} s)",
      )
      sub.pause() catch {
        _ => ()
      }
    }
    if ended_at >= 0 && blocks - ended_at >= tail_blocks {
      break
    }
  }
  let view = player.view()
  println(
    "# blocks=\{blocks} seconds=\{blocks.to_double() * BLOCK.to_double() / SAMPLE_RATE}",
  )
  println(
    "# peak=\{peak} clipped_samples=\{clipped} control_errors=\{control_errors}",
  )
  println(
    "# final state=\{view.state.to_repr()} bpm=\{view.bpm} pending=\{view.pending_materials} skipped=\{view.skipped_materials}",
  )
  sub.unmount() catch {
    _ => ()
  }
  engine.close()
}
