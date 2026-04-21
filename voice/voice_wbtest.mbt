///|
/// Force a slot's generation to a specific value.
/// Whitebox test helper — needs access to private `slots` field.
fn set_slot_generation(
  pool : VoicePool,
  slot_index : Int,
  generation : Int,
) -> Unit {
  if slot_index >= 0 && slot_index < pool.max_voices {
    pool.slots[slot_index].generation = generation
  }
}

///|
/// Force the pool's next_allocation_order to a specific value.
/// Whitebox test helper — needs access to private field.
fn set_next_allocation_order(pool : VoicePool, value : Int) -> Unit {
  pool.next_allocation_order = value
}

///|
test "VoiceHandle becomes invalid after generation overflow resets to 0" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=1).unwrap()
  // Force generation near the overflow cap (@int.MAX_VALUE - 1 = 2147483646).
  // Next note_on increments to 2147483646, the one after triggers the guard.
  set_slot_generation(pool, 0, @int.MAX_VALUE - 2)
  // note_on #1: generation -> @int.MAX_VALUE - 1
  let h1 = pool.note_on([]).unwrap()
  assert_true(pool.voice_state(h1) is VoiceState::Active)
  // note_on #2: steals slot 0, guard resets generation to 0.
  // h1's generation no longer matches -> stale handle.
  let h2 = pool.note_on([]).unwrap()
  assert_true(pool.voice_state(h2) is VoiceState::Active)
  assert_true(pool.voice_state(h1) is VoiceState::Idle)
  assert_true(!pool.note_off(h1))
  assert_true(pool.note_off(h2))
}

///|
test "compact_allocation_orders preserves relative voice age" {
  let ctx = DspContext::new(sample_rate=48000.0, block_size=16)
  let nodes = [DspNode::constant(440.0), DspNode::output(0)]
  let pool = VoicePool::new(nodes, ctx, max_voices=4).unwrap()
  // Activate 3 voices so they get sequential allocation_orders 0, 1, 2
  let h0 = pool.note_on([]).unwrap()
  let h1 = pool.note_on([]).unwrap()
  let h2 = pool.note_on([]).unwrap()
  // Force next_allocation_order near overflow to trigger compaction on next note_on
  set_next_allocation_order(pool, @int.MAX_VALUE - 1)
  // This note_on should trigger compact_allocation_orders
  let h3 = pool.note_on([]).unwrap()
  // All 4 voices should still be valid and active
  assert_true(pool.voice_state(h0) is VoiceState::Active)
  assert_true(pool.voice_state(h1) is VoiceState::Active)
  assert_true(pool.voice_state(h2) is VoiceState::Active)
  assert_true(pool.voice_state(h3) is VoiceState::Active)
  // After compaction, next_allocation_order should be small (4 active voices -> 4)
  assert_true(pool.next_allocation_order <= 5)
}
