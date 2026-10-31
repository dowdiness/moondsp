///|
/// Where a followed bus value goes on its voice (ADR-0019 Decision 8).
priv enum BusTarget {
  Gain
  Pan
  Send
  /// A graph parameter; the value converts through its binding's unit.
  Param(@moondsp.ControlUnit, Int, @moondsp.GraphParamSlot)
}

///|
/// One voice parameter that reads one bus while the voice sounds.
priv struct BusFollower {
  instrument : Int
  handle : @moondsp.VoiceHandle
  origin : @model.VoiceOrigin
  reader : @pattern.BusReader
  target : BusTarget
  /// The last pattern-domain value sent, so unchanged values send nothing.
  mut last : Double
}

///|
/// Every bus-bound parameter of every sounding voice. A follower stays until
/// its voice becomes idle, so release tails keep following (Decision 9).
priv struct BusFollowers {
  followers : Array[BusFollower]
}

///|
fn BusFollowers::BusFollowers() -> BusFollowers {
  { followers: [], }
}

///|
/// Record the time-varying buses of a voice that just started from `values`.
/// Keys the voice cannot receive are skipped.
fn BusFollowers::follow(
  self : BusFollowers,
  instrument : Int,
  handle : @moondsp.VoiceHandle,
  origin : @model.VoiceOrigin,
  buses : @pattern.EventBuses,
  pool : @moondsp.BoundVoicePool,
  values : @pattern.ControlMap,
) -> Unit {
  // A stolen slot's previous voice no longer exists.
  self.drop_where(follower => {
    follower.instrument == instrument && follower.handle.slot == handle.slot
  })
  buses.each_reader((key, reader) => {
    let target = pool
      .binding(key)
      .map(binding => {
        match binding.target {
          Voice(Gain) => Gain
          Voice(Pan) => Pan
          Voice(Send) => Send
          Graph(node, slot) => Param(binding.unit, node, slot)
        }
      })
    if target is Some(target) {
      self.followers.push({
        instrument,
        handle,
        origin,
        reader,
        target,
        last: values.get(key).unwrap_or(@double.not_a_number),
      })
    }
  })
}

///|
/// Send each changed bus value at `at`, and forget voices that went idle.
/// Allocates nothing.
fn BusFollowers::update(
  self : BusFollowers,
  at : @pattern.Rational,
  pools : Array[@moondsp.BoundVoicePool],
) -> Unit {
  let mut i = 0
  while i < self.followers.length() {
    let follower = self.followers[i]
    let pool = pools[follower.instrument]
    if pool.voice_state(follower.handle) is Idle {
      self.remove_at(i)
      continue
    }
    i += 1
    let value = follower.reader.value(at)
    if value.is_nan() || value == follower.last {
      continue
    }
    follower.last = value
    match follower.target {
      Gain => ignore(pool.set_voice_gain_result(follower.handle, value))
      Pan => ignore(pool.set_voice_pan_bool(follower.handle, value))
      Send => ignore(pool.set_voice_send_result(follower.handle, value))
      Param(unit, node, slot) =>
        ignore(
          pool.apply_voice_param_bool(
            follower.handle,
            node,
            slot,
            unit.convert(value),
          ),
        )
    }
  }
}

///|
/// Detach voices: a detached voice keeps its last value.
fn BusFollowers::drop_matching(
  self : BusFollowers,
  matches : (@model.VoiceOrigin) -> Bool,
) -> Unit {
  self.drop_where(follower => matches(follower.origin))
}

///|
fn BusFollowers::drop_where(
  self : BusFollowers,
  drop : (BusFollower) -> Bool,
) -> Unit {
  let mut i = 0
  while i < self.followers.length() {
    if drop(self.followers[i]) {
      self.remove_at(i)
    } else {
      i += 1
    }
  }
}

///|
/// Swap-remove: follower order is not observable.
fn BusFollowers::remove_at(self : BusFollowers, i : Int) -> Unit {
  let last = self.followers.length() - 1
  if i < last {
    self.followers[i] = self.followers[last]
  }
  ignore(self.followers.pop())
}

///|
fn BusFollowers::clear(self : BusFollowers) -> Unit {
  self.followers.clear()
}
