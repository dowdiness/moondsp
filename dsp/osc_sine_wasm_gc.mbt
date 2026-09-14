// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Adapted from moonbitlang/core math/{trig_double_nonjs,utils}.mbt shipped
// with moonc v0.10.12+1634b282e (2026-09-07):
// https://github.com/moonbitlang/core/tree/main/math
// Changes: retain only the oscillator's nonnegative, at-most-one-turn range;
// replace rem_pio2's scratch array with scalars. Coefficients and floating-point
// evaluation order are unchanged. Do not use this as a general-purpose sin.

///|
const SINE_PIO2_1 : Double = 1.5707963267341256e+00

///|
const SINE_PIO2_1T : Double = 6.0771005065061922e-11

///|
const SINE_PIO2_2 : Double = 6.0771005063039660e-11

///|
const SINE_PIO2_2T : Double = 2.0222662487959506e-21

///|
const SINE_PIO2_3 : Double = 2.0222662487111665e-21

///|
const SINE_PIO2_3T : Double = 8.4784276603688996e-32

///|
// Oscillator state is in [0, 1], or NaN after a scalar step overflows.
// Rounding while wrapping a tiny negative phase can produce exactly 1.
fn sine_for_phase(phase : Double) -> Double {
  let x = phase * 2.0 * @math.PI
  guard !x.is_nan() else { return x }
  guard x > 0.785398163397448309616 else { return sine_kernel(x, 0.0, false) }
  let ix = sine_high_word(x)
  // Preserve rem_pio2's high-word cutoff, which differs from sin's cutoff.
  guard ix > 0x3fe921fb else { return sine_kernel(x, 0.0, true) }
  let mut y0 = 0.0
  let mut y1 = 0.0
  let quadrant = if ix < 0x4002d97c {
    let z = x - SINE_PIO2_1
    if ix != 0x3ff921fb {
      y0 = z - SINE_PIO2_1T
      y1 = z - y0 - SINE_PIO2_1T
    } else {
      let z = z - SINE_PIO2_2
      y0 = z - SINE_PIO2_2T
      y1 = z - y0 - SINE_PIO2_2T
    }
    1
  } else {
    let n = (x * 6.3661977236758138e-01 + 0.5).to_int()
    let turns = n.to_double()
    let mut r = x - turns * SINE_PIO2_1
    let mut w = turns * SINE_PIO2_1T
    y0 = r - w
    // Only n=1..4 are reachable, so no npio2_hw lookup array is needed.
    let multiple_high_word = match n {
      1 => 0x3ff921fb
      2 => 0x400921fb
      3 => 0x4012d97c
      _ => 0x401921fb
    }
    if ix == multiple_high_word {
      let exponent = ix >> 20
      if exponent - ((sine_high_word(y0) >> 20) & 0x7ff) > 16 {
        let t = r
        w = turns * SINE_PIO2_2
        r = t - w
        w = turns * SINE_PIO2_2T - (t - r - w)
        y0 = r - w
        if exponent - ((sine_high_word(y0) >> 20) & 0x7ff) > 49 {
          let t = r
          w = turns * SINE_PIO2_3
          r = t - w
          w = turns * SINE_PIO2_3T - (t - r - w)
          y0 = r - w
        }
      }
    }
    y1 = r - y0 - w
    n
  }
  match quadrant & 3 {
    0 => sine_kernel(y0, y1, true)
    1 => sine_cosine_kernel(y0, y1)
    2 => -sine_kernel(y0, y1, true)
    _ => -sine_cosine_kernel(y0, y1)
  }
}

///|
fn sine_high_word(x : Double) -> Int {
  (x.reinterpret_as_uint64() >> 32).to_uint().reinterpret_as_int() & 0x7fffffff
}

///|
fn sine_kernel(x : Double, y : Double, reduced : Bool) -> Double {
  let s1 = -1.66666666666666324348e-01
  let s2 = 8.33333333332248946124e-03
  let s3 = -1.98412698298579493134e-04
  let s4 = 2.75573137070700676789e-06
  let s5 = -2.50507602534068634195e-08
  let s6 = 1.58969099521155010221e-10
  guard sine_high_word(x) >= 0x3e400000 else { return x }
  let z = x * x
  let v = z * x
  let r = s2 + z * (s3 + z * (s4 + z * (s5 + z * s6)))
  if reduced {
    x - (z * (0.5 * y - v * r) - y - v * s1)
  } else {
    x + v * (s1 + z * r)
  }
}

///|
fn sine_cosine_kernel(x : Double, y : Double) -> Double {
  let c1 = 4.16666666666666019037e-02
  let c2 = -1.38888888888741095749e-03
  let c3 = 2.48015872894767294178e-05
  let c4 = -2.75573143513906633035e-07
  let c5 = 2.08757232129817482790e-09
  let c6 = -1.13596475577881948265e-11
  let ix = sine_high_word(x)
  guard ix >= 0x3e400000 else { return 1.0 }
  let z = x * x
  let r = z * (c1 + z * (c2 + z * (c3 + z * (c4 + z * (c5 + z * c6)))))
  if ix < 0x3fd33333 {
    1.0 - (0.5 * z - (z * r - x * y))
  } else {
    let qx = if ix > 0x3fe90000 {
      0.28125
    } else {
      ((ix - 0x00200000).to_uint64() << 32).reinterpret_as_double()
    }
    let hz = 0.5 * z - qx
    let a = 1.0 - qx
    a - (hz - (z * r - x * y))
  }
}
