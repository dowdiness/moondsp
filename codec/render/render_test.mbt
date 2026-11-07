// 黑盒测试:@render 的公开 API。合成器模板与 scheduler_test 的最小
// osc→adsr→envelope_gain→output 模板一致,因此本文件同时验证离线渲染
// 路径与既有调度语义的兼容性。

///|
fn err_of(f : () -> Unit raise @render.RenderError) -> @render.RenderError? {
  try {
    f()
    None
  } catch {
    error => Some(error)
  }
}

///|
test "render_samples produces finite stereo output at block granularity" {
  let samples = @render.render_samples(
    source="note(\"60\")",
    seconds=0.25,
    sample_rate=48000,
    block_size=128,
  )
  // 0.25s @ 48k = 12000 样本;12000/128 = 93.75 → 94 块
  assert_true(samples.length() == 94 * 128 * 2)
  let mut nonzero = 0
  for s in samples {
    assert_true(@dsp.is_finite(s))
    assert_true(s >= -1.0 && s <= 1.0)
    if s != 0.0 {
      nonzero += 1
    }
  }
  // 正弦音符应当实际发声
  assert_true(nonzero > 0)
}

///|
test "render_samples is deterministic" {
  let a = @render.render_samples(
    source="note(\"60 [60 67]\")",
    seconds=0.5,
    sample_rate=48000,
  )
  let b = @render.render_samples(
    source="note(\"60 [60 67]\")",
    seconds=0.5,
    sample_rate=48000,
  )
  assert_true(a.length() == b.length())
  for i = 0; i < a.length(); i = i + 1 {
    assert_true(a[i] == b[i])
  }
}

///|
test "render_wav round-trips through the wav decoder" {
  let bytes = @render.render_wav(
    source="note(\"72\")",
    seconds=0.25,
    sample_rate=48000,
    format=@wav.WavSampleFormat::PcmI16,
  )
  let f = @wav.decode(bytes)
  assert_true(f.sample_rate() == 48000)
  assert_true(f.channels() == 2)
  // 94 块 × 128 样本/块 = 12032 帧
  assert_true(f.frame_count() == 94 * 128)
  assert_true(f.duration_seconds() == (94 * 128).to_double() / 48000.0)
}

///|
test "render errors are structured, not panics" {
  // 解析失败
  assert_true(
    err_of(() => {
      let _ = @render.render_samples(
        source="note((\"broken\")",
        seconds=0.1,
        sample_rate=48000,
      )
    })
    is Some(@render.RenderError::ParseFailed(_)),
  )
  // 非法时长
  assert_true(
    err_of(() => {
      let _ = @render.render_samples(
        source="note(\"60\")",
        seconds=-1.0,
        sample_rate=48000,
      )
    })
    is Some(@render.RenderError::InvalidConfig(_)),
  )
  // 非法采样率
  assert_true(
    err_of(() => {
      let _ = @render.render_samples(
        source="note(\"60\")",
        seconds=0.1,
        sample_rate=0,
      )
    })
    is Some(@render.RenderError::InvalidConfig(_)),
  )
}
