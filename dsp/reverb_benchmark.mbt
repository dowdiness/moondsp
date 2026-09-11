///|
const REVERB_BENCH_SAMPLE_RATE : Double = 48000.0

///|
const REVERB_BENCH_BLOCK_SIZE : Int = 128

///|
test "bench/reverb/dry_stereo_copy_128" (b : @bench.T) {
  let context = DspContext(
    sample_rate=REVERB_BENCH_SAMPLE_RATE,
    block_size=REVERB_BENCH_BLOCK_SIZE,
  )
  let left_input = context.make_buffer()
  let right_input = context.make_buffer()
  let left_output = context.make_buffer()
  let right_output = context.make_buffer()
  for i in 0..<REVERB_BENCH_BLOCK_SIZE {
    left_input.set(i, (i % 17 - 8).to_double() * 0.01)
    right_input.set(i, (i % 13 - 6).to_double() * 0.01)
  }
  b.bench(fn() {
    for i in 0..<REVERB_BENCH_BLOCK_SIZE {
      left_output.set(i, left_input.get(i))
      right_output.set(i, right_input.get(i))
    }
    b.keep(left_output)
    b.keep(right_output)
  })
}

///|
test "bench/reverb/shared_stereo_128" (b : @bench.T) {
  let context = DspContext(
    sample_rate=REVERB_BENCH_SAMPLE_RATE,
    block_size=REVERB_BENCH_BLOCK_SIZE,
  )
  let reverb = StereoReverb(REVERB_BENCH_SAMPLE_RATE)
  let left_input = context.make_buffer()
  let right_input = context.make_buffer()
  let left_output = context.make_buffer()
  let right_output = context.make_buffer()
  for i in 0..<REVERB_BENCH_BLOCK_SIZE {
    left_input.set(i, (i % 17 - 8).to_double() * 0.01)
    right_input.set(i, (i % 13 - 6).to_double() * 0.01)
  }
  b.bench(fn() {
    reverb.process(context, left_input, right_input, left_output, right_output)
    b.keep(left_output)
    b.keep(right_output)
  })
}
