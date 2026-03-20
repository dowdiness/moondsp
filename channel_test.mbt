///|
test "ChannelSpec: mono is 1 channel" {
  let m = @mdsp.Mono::new()
  assert_eq(m.channel_count(), 1)
}

///|
test "ChannelSpec: stereo is 2 channels" {
  let s = @mdsp.Stereo::new()
  assert_eq(s.channel_count(), 2)
}

///|
test "mono_shape matches MONO_SIGNAL_SHAPE" {
  assert_eq(@mdsp.mono_shape(), 0)
}

///|
test "stereo_shape matches STEREO_SIGNAL_SHAPE" {
  assert_eq(@mdsp.stereo_shape(), 1)
}
