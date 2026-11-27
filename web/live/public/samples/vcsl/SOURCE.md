# Built-in bank recordings

These nine files are the recorded samples of moondsp's built-in sample bank
(`@score.Sample`, ADR-0026). Each name gives the instrument and the measured
root pitch, which is the pitch `s("name")` plays. `s` stands for a sharp, so
`fs5` is F#5.

## Source

[Versilian Community Sample Library](https://github.com/sgossner/VCSL) (VCSL)
by Versilian Studios. It is released under
[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/), so
these files carry no attribution requirement. This file records where they
came from anyway.

| File | Seconds | Root (MIDI) | VCSL file |
|---|---:|---:|---|
| `piano_c2.flac` | 12.0 | 36 (C2) | `Chordophones/Zithers/Grand Piano, Steinway B/NoSus/JHPiano_NoSus_Close_C2_vl3_rr1.wav` |
| `piano_c4.flac` | 10.0 | 60 (C4) | `Chordophones/Zithers/Grand Piano, Steinway B/NoSus/JHPiano_NoSus_Close_C4_vl3_rr1.wav` |
| `piano_c6.flac` | 6.0 | 84 (C6) | `Chordophones/Zithers/Grand Piano, Steinway B/NoSus/JHPiano_NoSus_Close_C6_vl3_rr1.wav` |
| `upright_a4.flac` | 8.0 | 69 (A4) | `Chordophones/Zithers/Upright Piano, Knight/Sustains/Player_vl1_rr1_A3.wav` |
| `mbira_e3.flac` | 3.0 | 52 (E3) | `Idiophones/Plucked Idiophones/Mbira dzaVadzimu Nyamaropa, Zimbabwe, Low B/MBira4_pluck_Main_E2_10_50_100_rr3.wav` |
| `mbira_b4.flac` | 2.5 | 71 (B4) | `Idiophones/Plucked Idiophones/Mbira dzaVadzimu Nyamaropa, Zimbabwe, Low B/MBira4_pluck_Main_B3_3_50_100_rr2.wav` |
| `mbira_fs5.flac` | 2.0 | 78 (F#5) | `Idiophones/Plucked Idiophones/Mbira dzaVadzimu Nyamaropa, Zimbabwe, Low B/MBira4_pluck_Main_F#4_20_50_100_rr3.wav` |
| `kalimba_cs5.flac` | 2.0 | 73 (C#5) | `Idiophones/Plucked Idiophones/Kalimba, Tanzania/MBira3_pluck_Main_C#4_k5_50_100_rr2.wav` |
| `kalimba_g5.flac` | 1.5 | 79 (G5) | `Idiophones/Plucked Idiophones/Kalimba, Tanzania/MBira3_pluck_Main_G4_k22_50_100_rr2.wav` |

The upright, mbira and kalimba files sound one octave above the note in their
VCSL file names. The roots above are measured, not taken from the names.

## Processing

Each file was made from its VCSL WAV in this order:

1. Keep the left channel only.
2. Resample to 48 kHz where the source is 44.1 kHz (the pianos), with a
   polyphase filter (`scipy.signal.resample_poly`, 160/147).
3. Remove leading silence: cut 1 ms before the first sample within 50 dB of
   the file's peak.
4. Cut to the length in the table, and fade out over the last 20% of it with
   a cos² curve.
5. Normalize the peak to 0.5.
6. Write 48 kHz mono 16-bit FLAC.

Together the files hold 47.0 s, 2,256,000 samples at 48 kHz, and 1.19 MB.

## Measured roots

The partial nearest each root was tracked at 0.02, 0.25, 0.5 and 1.0 s after
the start (for `piano_c2`, whose fundamental is weak, its sixth harmonic).
Deviation from the root, in cents:

| File | Deviation |
|---|---|
| `piano_c2` | −2 |
| `piano_c4` | +1 |
| `piano_c6` | +3 |
| `upright_a4` | +1 |
| `mbira_e3` | +16 |
| `mbira_b4` | +12 |
| `mbira_fs5` | +5 |
| `kalimba_cs5` | +10 |
| `kalimba_g5` | +33 |

`kalimba_g5` has a second mode at 815 Hz (G5 +67 cents) beside its 799 Hz
partial; the second is stronger after about 0.25 s, but the 799 Hz partial
dominates the whole clip.
