///|
pub(open) trait ChannelSpec {
  channel_count(Self) -> Int
}

///|
pub struct Mono {}

///|
pub fn Mono::new() -> Mono {
  Mono::{  }
}

///|
pub impl ChannelSpec for Mono with channel_count(_self) {
  1
}

///|
pub struct Stereo {}

///|
pub fn Stereo::new() -> Stereo {
  Stereo::{  }
}

///|
pub impl ChannelSpec for Stereo with channel_count(_self) {
  2
}

///|
/// Bridge to existing MONO_SIGNAL_SHAPE constant (value 0).
pub fn mono_shape() -> Int {
  0
}

///|
/// Bridge to existing STEREO_SIGNAL_SHAPE constant (value 1).
pub fn stereo_shape() -> Int {
  1
}
