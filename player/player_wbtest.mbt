///|
fn test_drum(drum : @score.Drum) -> @moondsp.AnalyzedGraph {
  let freq = match drum {
    Bd => 60.0
    Sd => 180.0
    Hh => 8000.0
    Cp => 1200.0
    Oh => 6000.0
  }
  @moondsp.AnalyzedGraph::analyze([
    @moondsp.DspNode::oscillator(@moondsp.Waveform::Sine, freq),
    @moondsp.DspNode::adsr(
      attack_ms=0.5,
      decay_ms=60.0,
      sustain=0.0,
      release_ms=40.0,
    ),
    @moondsp.DspNode::envelope_gain(input=0, envelope=1, amount=1.0),
    @moondsp.DspNode::output(2),
  ])
}

///|
fn test_voice(_ : @score.Instrument) -> NoteVoice {
  {
    waveform: Sine,
    attack_ms: 10.0,
    decay_ms: 100.0,
    sustain: 0.7,
    release_ms: 300.0,
    lpf_hz: 8000.0,
    lpf_q: 0.707,
    amount: 1.0,
    voices: 12,
  }
}

///|
fn test_player(
  sample_rate~ : Double = 48000.0,
  block_size~ : Int32 = 128,
) -> Player raise UnsupportedFormat {
  let ctx = @moondsp.DspContext(sample_rate~, block_size~)
  Player(ctx, {
    drum: test_drum,
    instrument: test_voice,
    sampler: {
      attack_ms: 0.0,
      decay_ms: 0.0,
      sustain: 1.0,
      release_ms: 10.0,
      lpf_hz: 8000.0,
      lpf_q: 0.707,
      amount: 1.0,
      voices: 4,
    },
  })
}

///|
/// The score `player` compiles from the tracked input a draft of `text`
/// prepares, as the editor sends it.
fn tracked(player : Player, text : String) -> Score raise {
  guard @mini.Draft(text).prepare_playback() is Ok(input) else {
    fail("expected \{text} to prepare")
  }
  player.compile(input)
}

///|
fn wet_energy(player : Player) -> Double {
  let mut energy = 0.0
  for i in 0..<player.wet_left.length() {
    energy += player.wet_left.get(i).abs() + player.wet_right.get(i).abs()
  }
  energy
}

///|
test "offline rendering plays a finite song to its end and keeps its tails" {
  let player = test_player()
  let song = "bpm(240); song(section(\"a\",1,note(\"60 64\")),part(\"a1\",\"a\"))"
  player.restart(tracked(player, song))
  // One cycle at 240 BPM is one second: 375 blocks of 128 frames at 48 kHz.
  let mut blocks = 0
  let mut energy = 0.0
  while player.state() is Playing && blocks < 1000 {
    render_blocks(player, 1)
    energy += output_energy()
    blocks += 1
  }
  assert_eq(player.state(), Ended)
  assert_eq(blocks, 375)
  assert_true(energy > 0.01)
  assert_eq(player.sample_position(), 48000.0)
  // The last note ends with the song; its release still sounds.
  render_blocks(player, 1)
  assert_eq(player.state(), Ended)
  assert_true(output_energy() > 0.0)
}

///|
test "source tempo commits at unchanged musical position" {
  let player = test_player()
  let song = fn(bpm : Int32) {
    "song(bpm(\{bpm}),section(\"a\",8,note(\"60\")),part(\"a1\",\"a\"))"
  }
  player.restart(tracked(player, song(120)))
  render_blocks(player, 4)
  player.update(tracked(player, song(90)))
  assert_eq(player.scheduler.sample_counter(), 512L)
  assert_eq(player.scheduler.bpm(), 90.0)
  render_blocks(player, 1)
  assert_eq(
    player.scheduler.current_block().unwrap().logical_arc.begin,
    @pattern.Rational(512L * 120L + 128L * 90L, 11520000L),
  )
}

///|
test "shared room tail survives a two-part continue edit and restart clears it" {
  let before = "song(section(\"a\",4,s(\"bd\").slow(8).room(1)),section(\"b\",4,s(\"sd\").slow(8)),part(\"a1\",\"a\",0),part(\"b1\",\"b\",0))"
  let after = "song(section(\"a\",4,s(\"bd\").slow(8).gain(0)),section(\"b\",4,s(\"sd\").slow(8)),part(\"a1\",\"a\",0),part(\"b1\",\"b\",0))"
  let player = test_player()
  player.restart(tracked(player, before))
  render_blocks(player, 30)
  assert_true(wet_energy(player) > 0.0)
  player.update(tracked(player, after))
  render_blocks(player, 1)
  assert_true(wet_energy(player) > 0.0)
  assert_true(player.scheduler.active_note_count() > 0)
  assert_true(output_energy() > 0.0)
  player.restart(tracked(player, after))
  render_blocks(player, 1)
  assert_eq(wet_energy(player), 0.0)
  assert_true(player.scheduler.active_note_count() > 0)
}

///|
test "room send leaves dry playback dry and adds one wet return" {
  let dry = test_player()
  dry.restart(tracked(dry, "s(\"bd\").slow(8)"))
  render_blocks(dry, 30)
  assert_eq(wet_energy(dry), 0.0)
  let dry_output = output_energy()
  let wet = test_player()
  wet.restart(tracked(wet, "s(\"bd\").slow(8).room(1)"))
  render_blocks(wet, 30)
  assert_true(wet_energy(wet) > 0.0)
  assert_true((output_energy() - dry_output).abs() > 0.000001)
}

///|
/// Energy of `blocks` blocks of a sampler note on sample 0 of the context's
/// store, with its low-pass at `lpf_hz` and its voice gain at `gain`. The
/// note's controls are set as graph params, so the pool is tested without a
/// score.
fn sampler_energy(
  pool : @moondsp.BoundVoicePool,
  ctx : @moondsp.DspContext,
  lpf_hz~ : Double = 18000.0,
  gain~ : Double = 1.0,
  blocks~ : Int32 = 8,
) -> Double raise {
  pool.kill_all()
  let handle = pool
    .note_on_graph_controls([
      @moondsp.GraphControl::set_param(0, @moondsp.GraphParamSlot::Value0, 0.0),
      @moondsp.GraphControl::set_param(
        2,
        @moondsp.GraphParamSlot::Value0,
        lpf_hz,
      ),
    ])
    .unwrap()
  assert_true(pool.set_voice_gain_result(handle, gain) is Ok(_))
  let left = @moondsp.AudioBuffer::filled(128)
  let right = @moondsp.AudioBuffer::filled(128)
  let mut energy = 0.0
  for _ in 0..<blocks {
    left.fill(0.0)
    right.fill(0.0)
    pool.process(ctx, left, right)
    for i in 0..<128 {
      energy = energy + left.get(i) * left.get(i)
    }
  }
  energy
}

///|
test "the sampler pool is silent until its sample loads, then lpf and gain shape it" {
  let samples = @moondsp.SampleStore(
    entries=4,
    max_length=48000,
    capacity=48000,
  )
  let ctx = @moondsp.DspContext(sample_rate=48000.0, block_size=128, samples~)
  let pool = make_sample_pool(
    {
      attack_ms: 0.0,
      decay_ms: 0.0,
      sustain: 1.0,
      release_ms: 10.0,
      lpf_hz: 8000.0,
      lpf_q: 0.707,
      amount: 1.0,
      voices: 4,
    },
    ctx,
  ).unwrap()
  assert_true(pool.binding(Lpf) is Some(_))
  assert_true(pool.binding(Note) is Some(_))
  assert_true(!samples.has(0))
  assert_eq(sampler_energy(pool, ctx), 0.0)
  // A noise burst, so the low-pass has highs to remove.
  let length = 4800
  let mut state = 12345
  assert_true(samples.begin(0, length, root_pitch=60.0) is None)
  for offset in 0..<length {
    state = (state * 1103515245 + 12345) & 0x7fffffff
    samples.write(
      offset,
      Float::from_double(state.to_double() / 1073741824.0 - 1.0),
    )
  }
  // Pending, not yet committed: still silence.
  assert_eq(sampler_energy(pool, ctx), 0.0)
  assert_true(samples.commit())
  assert_true(samples.has(0))
  let open = sampler_energy(pool, ctx)
  let filtered = sampler_energy(pool, ctx, lpf_hz=300.0)
  let quieter = sampler_energy(pool, ctx, gain=0.5)
  assert_true(open > 1.0)
  assert_true(filtered < open * 0.2)
  assert_true((quieter / open - 0.25).abs() < 0.01)
}

///|
test "a score with no source text plays and reports no source" {
  let player = test_player()
  let doc = @pattern.PatternDoc::from_pattern(
    id=@identity.PatternNodeId::from_string("generated"),
    pat=@pattern.sequence([@score.note(60.0), @score.note(67.0)]),
  )
  player.restart(Score::pattern(doc.lower(), tempo=Tempo(120.0)))
  assert_eq(player.mode(), Some(Pattern))
  render_blocks(player, 1)
  assert_true(output_energy() > 0.01)
}

///|
test "process refuses buffers that do not hold one block" {
  let player = test_player()
  player.restart(tracked(player, "note(\"60\")"))
  let short = @moondsp.AudioBuffer::filled(64)
  guard player.process(short, out_right)
    is Some(BufferSizeMismatch(expected=128, actual=64)) else {
    fail("expected a buffer size mismatch")
  }
  assert_eq(player.scheduler.sample_counter(), 0L)
}

///|
test "a score compiled for shorter blocks is refused, and for the same blocks accepted" {
  let short_blocks = test_player(block_size=64)
  let score = short_blocks.compile(@mini.PlaybackInput::text("note(\"60\")"))
  let long_blocks = test_player(block_size=128)
  guard raised(() => long_blocks.restart(score))
    is Some(CompiledForShorterBlocks) else {
    fail("expected a score compiled for 64-frame blocks to be refused")
  }
  assert_eq(long_blocks.state(), Empty)
  let same_blocks = test_player(block_size=64)
  same_blocks.restart(score)
  assert_eq(same_blocks.state(), Playing)
}
