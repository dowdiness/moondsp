///|
/// The sample store of the browser host (ADR-0026 Decision 6): 64 sample
/// numbers, waveforms up to 30 s at 48 kHz, and 32 MiB of samples in all.
pub const SAMPLE_ENTRIES : Int32 = 64

///|
pub const SAMPLE_MAX_LENGTH : Int32 = 1440000

///|
pub const SAMPLE_CAPACITY : Int32 = 8388608

///|
/// Made once by `init_sample_store`. Making it takes 15–20 ms, so the host
/// makes it before the first render, not while one runs.
let sample_store : @ref.Ref[@moondsp.SampleStore?] = Ref(None)

///|
/// Make the browser's sample store if there is none yet. Players built after
/// it read their samples from it. Returns its capacity.
pub fn init_sample_store() -> Int32 {
  match sample_store.val {
    Some(store) => store.capacity()
    None => {
      let store = @moondsp.SampleStore(
        entries=SAMPLE_ENTRIES,
        max_length=SAMPLE_MAX_LENGTH,
        capacity=SAMPLE_CAPACITY,
      )
      sample_store.val = Some(store)
      store.capacity()
    }
  }
}

///|
/// A context of this format that compiles graphs over the sample store, or
/// over an empty store before `init_sample_store`.
fn sample_context(
  sample_rate : Double,
  block_size : Int32,
) -> @moondsp.DspContext {
  match sample_store.val {
    Some(samples) => @moondsp.DspContext(sample_rate~, block_size~, samples~)
    None => @moondsp.DspContext(sample_rate~, block_size~)
  }
}

///|
/// The built-in bank by sample number, built once so loading on the audio
/// thread reads it without allocating.
let bank : Array[@score.Sample] = @score.Sample::all()

///|
/// The number of samples in the built-in bank; sample number `n` is
/// `@score.Sample::all()[n]`.
pub fn sample_bank_count() -> Int32 {
  bank.length()
}

///|
/// The name of bank sample `entry`, or "" outside the bank.
pub fn sample_bank_name(entry : Int32) -> String {
  if entry >= 0 && entry < bank.length() {
    bank[entry].name()
  } else {
    ""
  }
}

///|
/// Begin loading a waveform of `length` samples into bank sample number
/// `entry`, whose root is its `@score.Sample::root_pitch`, which `s("…")`
/// plays it at. Returns 0, or what refused it: 1 the sample number, 2 the length, 3 the
/// store's memory (ADR-0026 Decision 6), 4 no store yet.
pub fn sample_load_begin(entry : Int32, length : Int32) -> Int32 {
  guard sample_store.val is Some(store) else { return 4 }
  // A replaced waveform no sounding voice plays is free for this load.
  if player.val is Some(owner) {
    owner.reclaim_samples()
  } else {
    store.begin_scan()
    store.end_scan()
  }
  guard entry >= 0 && entry < bank.length() else { return 1 }
  match store.begin(entry, length, root_pitch=bank[entry].root_pitch()) {
    None => 0
    Some(Entries) => 1
    Some(Length) => 2
    Some(Memory) => 3
  }
}

///|
/// Write sample `offset` of the waveform being loaded.
pub fn sample_load_write(offset : Int32, value : Float) -> Unit {
  if sample_store.val is Some(store) {
    store.write(offset, value)
  }
}

///|
/// Finish loading, so new notes on the sample number play the waveform.
/// Returns false when nothing was being loaded.
pub fn sample_load_commit() -> Bool {
  match sample_store.val {
    Some(store) => store.commit()
    None => false
  }
}

///|
/// Whether sample number `entry` has a waveform.
pub fn sample_loaded(entry : Int32) -> Bool {
  match sample_store.val {
    Some(store) => store.has(entry)
    None => false
  }
}
