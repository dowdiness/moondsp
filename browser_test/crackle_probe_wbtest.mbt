///|
test "crackle probe routes compile and match direct reference" {
  for route in 0..<8 {
    crackle_probe_reset()
    assert_true(crackle_probe_run(route, 0, 440.0, 48000.0, 128, 4))
    assert_true(crackle_probe_last_error() == 0)
    assert_true(crackle_probe_block_count() == 4)
    assert_true(crackle_probe_metric(3, 4) == 0.0)
    assert_true(crackle_probe_metric(3, 7) < 0.000000001)
    assert_true(crackle_probe_metric(3, 8) < 0.000000001)
    assert_true(crackle_probe_metric(3, 11) < 0.000000001)
  }
}

///|
test "crackle probe triangle control routes compile" {
  for route in 2..<8 {
    crackle_probe_reset()
    assert_true(crackle_probe_run(route, 3, 440.0, 48000.0, 128, 4))
    assert_true(crackle_probe_last_error() == 0)
    assert_true(crackle_probe_metric(3, 4) == 0.0)
    assert_true(crackle_probe_metric(3, 7) < 0.000000001)
  }
}

///|
test "crackle probe stream rejects process before init" {
  crackle_probe_reset()
  assert_true(!crackle_probe_stream_process())
  assert_true(crackle_probe_last_error() == 10)
  assert_true(crackle_probe_block_count() == 0)
}

///|
test "crackle probe stream advances one block per call" {
  crackle_probe_reset()
  assert_true(crackle_probe_stream_init(3, 0, 440.0, 48000.0, 128))
  for block in 0..<4 {
    assert_true(crackle_probe_stream_process())
    assert_true(crackle_probe_block_count() == block + 1)
    assert_true(crackle_probe_metric(block, 4) == 0.0)
    assert_true(crackle_probe_metric(block, 7) < 0.000000001)
    assert_true(crackle_probe_metric(block, 8) < 0.000000001)
    assert_true(crackle_probe_metric(block, 11) < 0.000000001)
  }
}

///|
test "crackle probe stream covers browser synth shape" {
  crackle_probe_reset()
  assert_true(crackle_probe_stream_init(7, 0, 440.0, 48000.0, 128))
  for block in 0..<4 {
    assert_true(crackle_probe_stream_process())
    assert_true(crackle_probe_block_count() == block + 1)
    assert_true(crackle_probe_metric(block, 3) == 0.0)
    assert_true(crackle_probe_metric(block, 4) == 0.0)
    assert_true(crackle_probe_metric(block, 7) < 0.000000001)
  }
}

///|
test "crackle probe rejects invalid inputs with stable error codes" {
  crackle_probe_reset()
  assert_true(!crackle_probe_run(8, 0, 440.0, 48000.0, 128, 4))
  assert_true(crackle_probe_last_error() == 1)
  assert_true(crackle_probe_block_count() == 0)

  assert_true(!crackle_probe_run(0, 4, 440.0, 48000.0, 128, 4))
  assert_true(crackle_probe_last_error() == 2)

  assert_true(!crackle_probe_run(0, 0, 0.0, 48000.0, 128, 4))
  assert_true(crackle_probe_last_error() == 3)

  assert_true(!crackle_probe_run(0, 0, 440.0, 0.0, 128, 4))
  assert_true(crackle_probe_last_error() == 4)

  assert_true(!crackle_probe_run(0, 0, 440.0, 48000.0, 0, 4))
  assert_true(crackle_probe_last_error() == 5)

  assert_true(!crackle_probe_run(0, 0, 440.0, 48000.0, 128, 0))
  assert_true(crackle_probe_last_error() == 6)
}
