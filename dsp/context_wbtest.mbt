///|
test "normalize_sample_rate passes through positive value" {
  inspect(normalize_sample_rate(48000.0), content="48000")
}

///|
test "normalize_sample_rate clamps zero to 0.0" {
  inspect(normalize_sample_rate(0.0), content="0")
}

///|
test "normalize_sample_rate clamps negative to 0.0" {
  inspect(normalize_sample_rate(-1.0), content="0")
}

///|
test "normalize_sample_rate clamps NaN to 0.0" {
  inspect(normalize_sample_rate(0.0 / 0.0), content="0")
}

///|
test "normalize_block_size passes through positive value" {
  inspect(normalize_block_size(128), content="128")
}

///|
test "normalize_block_size clamps zero to 0" {
  inspect(normalize_block_size(0), content="0")
}

///|
test "normalize_block_size clamps negative to 0" {
  inspect(normalize_block_size(-1), content="0")
}

///|
test "DspContext::new with valid values" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=128)
  inspect(ctx.sample_rate(), content="48000")
  inspect(ctx.block_size(), content="128")
}

///|
test "DspContext::new normalizes negative sample_rate" {
  let ctx = DspContext::new(sample_rate=-44100.0, block_size=128)
  inspect(ctx.sample_rate(), content="0")
}

///|
test "DspContext::new normalizes negative block_size" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=-64)
  inspect(ctx.block_size(), content="0")
}
