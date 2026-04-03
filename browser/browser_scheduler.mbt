///|
let sched_pool : @ref.Ref[@lib.VoicePool?] = @ref.new(None)

///|
let sched_scheduler : @ref.Ref[@scheduler.PatternScheduler?] = @ref.new(None)

///|
let sched_left : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let sched_right : @ref.Ref[@lib.AudioBuffer?] = @ref.new(None)

///|
let sched_pattern_index : @ref.Ref[Int] = @ref.new(0)

///|
let sched_gain : @ref.Ref[Double] = @ref.new(0.3)

///|
fn sched_template() -> Array[@lib.DspNode] {
  [
    @lib.DspNode::oscillator(@lib.Waveform::Sine, 440.0),
    @lib.DspNode::adsr(0.01, 0.1, 0.7, 0.3),
    @lib.DspNode::gain(0, 1.0),
    @lib.DspNode::output(2),
  ]
}

///|
pub fn init_scheduler_graph(sample_rate : Double, block_size : Int) -> Bool {
  if sample_rate <= 0.0 || block_size <= 0 {
    reset_scheduler_graph()
    return false
  }
  let ctx = @lib.DspContext::new(sample_rate, block_size)
  let template = sched_template()
  let pool = @lib.VoicePool::new(template, ctx, max_voices=8)
  match pool {
    None => {
      reset_scheduler_graph()
      false
    }
    Some(p) => {
      let bindings_result = @lib.ControlBindingBuilder::new()
        .bind(key="note", node_index=0, slot=@lib.GraphParamSlot::Value0)
        .build(template)
      match bindings_result {
        Err(_) => {
          reset_scheduler_graph()
          false
        }
        Ok(bindings) => {
          let scheduler = @scheduler.PatternScheduler::new(
            bpm=120.0,
            bindings~,
            ctx~,
          )
          sched_pool.val = Some(p)
          sched_scheduler.val = Some(scheduler)
          sched_left.val = Some(@lib.AudioBuffer::filled(block_size))
          sched_right.val = Some(@lib.AudioBuffer::filled(block_size))
          sched_pattern_index.val = 0
          sched_gain.val = 0.3
          true
        }
      }
    }
  }
}

///|
fn reset_scheduler_graph() -> Unit {
  sched_pool.val = None
  sched_scheduler.val = None
  sched_left.val = None
  sched_right.val = None
  sched_pattern_index.val = 0
  sched_gain.val = 0.3
}

///|
pub fn scheduler_left_sample(index : Int) -> Double {
  checked_sample(index, sched_left.val)
}

///|
pub fn scheduler_right_sample(index : Int) -> Double {
  checked_sample(index, sched_right.val)
}

///|
fn sched_get_pattern(index : Int) -> @pattern.Pat[@pattern.ControlMap] {
  match index {
    1 =>
      @pattern.sequence([
        @pattern.note(60.0),
        @pattern.note(64.0),
        @pattern.note(67.0),
        @pattern.note(72.0),
      ])
    2 =>
      @pattern.stack([
        @pattern.note(60.0),
        @pattern.note(64.0),
        @pattern.note(67.0),
      ])
    3 => @pattern.note(60.0).fast(@pattern.Rational::from_int(4))
    _ => @pattern.note(60.0)
  }
}

///|
pub fn set_scheduler_pattern(index : Int) -> Unit {
  let clamped = if index < 0 { 0 } else if index > 3 { 3 } else { index }
  sched_pattern_index.val = clamped
}

///|
pub fn process_scheduler_block() -> Bool {
  let pool = match sched_pool.val {
    Some(p) => p
    None => return false
  }
  let scheduler = match sched_scheduler.val {
    Some(s) => s
    None => return false
  }
  let left = match sched_left.val {
    Some(b) => b
    None => return false
  }
  let right = match sched_right.val {
    Some(b) => b
    None => return false
  }
  let pat = sched_get_pattern(sched_pattern_index.val)
  scheduler.process_block(pat, pool, left, right)
  let gain = sched_gain.val
  let len = left.length()
  for i = 0; i < len; i = i + 1 {
    left.set(i, left.get(i) * gain)
    right.set(i, right.get(i) * gain)
  }
  true
}

///|
pub fn set_scheduler_bpm(bpm : Double) -> Unit {
  match sched_scheduler.val {
    None => ()
    Some(s) => s.set_bpm(bpm)
  }
}

///|
pub fn set_scheduler_gain(gain : Double) -> Unit {
  sched_gain.val = if gain < 0.0 {
    0.0
  } else if gain > 1.0 {
    1.0
  } else {
    gain
  }
}
