///|
/// Shared graph-test constants reduce repetition, but a wrong edit here can
/// affect multiple test expectations at once. Keep values local when they only
/// matter to a single case.
const STANDARD_SAMPLE_RATE : Double = 48000.0

///|
const ADSR_TEST_SAMPLE_RATE : Double = 1000.0

///|
const SMALL_BLOCK_SIZE : Int = 4

///|
const LARGE_BLOCK_SIZE : Int = 8

///|
const OSCILLATOR_FREQ : Double = 440.0

///|
const NOISE_SEED : UInt = 123U

///|
const UNIT_SAMPLE : Double = 1.0

///|
const ZERO_SAMPLE : Double = 0.0

///|
const QUARTER_SAMPLE : Double = 0.25

///|
const NEGATIVE_MIX_SAMPLE : Double = -0.1

///|
const MIXED_SAMPLE : Double = 0.15

///|
const HALF_GAIN : Double = 0.5

///|
const CLIP_THRESHOLD : Double = 0.2

///|
const LOWPASS_CUTOFF : Double = 1000.0

///|
const LOWPASS_Q : Double = 0.707

///|
const INVALID_NYQUIST_CUTOFF : Double = 24000.0

///|
const ADSR_ATTACK_MS : Double = 1.0

///|
const ADSR_DECAY_MS : Double = 1.0

///|
const ADSR_SUSTAIN_LEVEL : Double = 0.25

///|
const ADSR_RELEASE_MS : Double = 2.0

///|
const DELAY_CAPACITY : Int = 4

///|
const DELAY_SAMPLES : Int = 2

///|
const DELAY_SAMPLES_DOUBLE : Double = 2.0

///|
const DELAY_FEEDBACK : Double = 0.5

///|
const CLAMPED_HIGH_DELAY_FEEDBACK : Double = 0.995

///|
const CLAMPED_LOW_DELAY_FEEDBACK : Double = -0.995

///|
const INVALID_DELAY_FEEDBACK : Double = 1.0

///|
const PAN_HARD_LEFT : Double = -1.0

///|
const PAN_CENTER : Double = 0.0

///|
const PAN_HARD_RIGHT : Double = 1.0

///|
const PAN_CENTER_GAIN : Double = 0.7071067811865476

///|
const STEREO_CLIP_THRESHOLD : Double = 0.25
