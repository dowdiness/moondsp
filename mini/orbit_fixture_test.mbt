///|
const ORBIT_ORIGINAL : String =
  #|song(
  #|  section("seed",12,stack(note("E4 G4 A4").slow(3).gain(0.105),chord("Cmaj9").slow(12).gain(0.10))),
  #|  section("second_orbit",12,stack(note("E4 G4 A4").slow(3).gain(0.105),note("D5 A4 G4 E5").slow(4).jux(rev).gain(0.055),s("hh(3,8)").slow(4).gain(0.045))),
  #|  section("ground",24,stack(note("E4 G4 A4").slow(3).gain(0.105),note("D5 A4 G4 E5").slow(4).jux(rev).gain(0.055),s("bd").gain(0.46),s("hh(5,8)").slow(4).every(3, rev).degradeBy(0.12).gain(0.065),note("C2(3,8) A1(3,8,1)").slow(24).gain(0.23),chord("Cmaj9 Am7").slow(24).gain(0.11))),
  #|  section("daybreak",48,stack(note("E4 G4 A4").slow(3).gain(0.105),note("D5 A4 G4 E5").slow(4).jux(rev).gain(0.055),chord("Cmaj9 Am7 Fmaj9 G6").slow(48).gain(0.12),note("C2(3,8) A1(3,8,1) F2(3,8) G2(3,8,1)").slow(48).gain(0.25),s("bd").gain(0.46),s("cp(2,4,1)").slow(4).gain(0.13),s("hh(5,8)").slow(4).every(3, rev).degradeBy(0.12).gain(0.065),s("oh(2,8,1)").slow(4).gain(0.055))),
  #|  section("suspension",24,stack(chord("Fmaj9 Cmaj9").slow(24).gain(0.12),note("E4 G4 A4").slow(6).jux(rev).gain(0.075),note("D5 A4 G4 E5").slow(8).gain(0.065))),
  #|  section("refraction",23,stack(note("A4 G4 E4").slow(3).gain(0.105),note("D5 A4 G4 E5").slow(4).jux(rev).gain(0.055),chord("Am7 G6").slow(24).gain(0.11),note("A1(3,8) G2(3,8,1)").slow(24).gain(0.23),s("bd(3,8)").slow(4).gain(0.40),s("hh(5,8)").slow(4).every(3, rev).degradeBy(0.12).gain(0.065),s("cp(2,4,1)").slow(4).gain(0.13))),
  #|  section("one_breath",1,stack(note("C4").gain(0))),
  #|  section("confluence",24,stack(note("E4 G4 A4").slow(3).gain(0.105),note("D5 A4 G4 E5").slow(4).jux(rev).gain(0.055),chord("Cmaj9 Am7 Fmaj9 G6").slow(48).gain(0.12),note("C2(3,8) A1(3,8,1) F2(3,8) G2(3,8,1)").slow(48).gain(0.25),s("bd").gain(0.46),s("cp(2,4,1)").slow(4).gain(0.13),s("hh(5,8)").slow(4).every(3, rev).degradeBy(0.12).gain(0.065),s("oh(2,8,1)").slow(4).gain(0.055),note("G5(2,8) E5(2,8,1)").slow(12).gain(0.035))),
  #|  section("alignment",24,stack(note("E4 G4 A4").slow(4).gain(0.105),note("D5 A4 G4 E5").slow(4).jux(rev).gain(0.055),chord("Fmaj9 G6 Cmaj9").slow(24).gain(0.13),note("F2 G2 C2").slow(24).gain(0.25),s("bd").gain(0.46),s("cp(2,4,1)").slow(4).gain(0.13),s("hh(5,8)").slow(4).every(3, rev).degradeBy(0.12).gain(0.065),s("oh(2,8,1)").slow(4).gain(0.055))),
  #|  section("unthread",24,stack(note("E4 G4 A4").slow(3).gain(0.105),note("D5 A4 G4 E5").slow(4).jux(rev).gain(0.055),chord("Fmaj9 Cmaj9").slow(24).gain(0.10),note("F2 C2").slow(24).gain(0.18),s("hh(5,8)").slow(4).every(3, rev).degradeBy(0.12).gain(0.065))),
  #|  section("remember",12,stack(note("E4 G4 A4").slow(6).gain(0.075),chord("Am7").slow(12).gain(0.10))),
  #|  section("still_light",12,stack(note("E4 G4 A4").slow(6).gain(0.06),chord("Cmaj9").slow(12).gain(0.085))),
  #|  part("r1","seed"),
  #|  part("r2","second_orbit"),
  #|  part("r3","ground"),
  #|  part("r4","daybreak"),
  #|  part("r5","suspension"),
  #|  part("r6","refraction"),
  #|  part("r7","one_breath"),
  #|  part("r8","confluence"),
  #|  part("r9","alignment"),
  #|  part("r10","unthread"),
  #|  part("r11","remember"),
  #|  part("r12","still_light")
  #|)

///|
const ORBIT_NAMED : String =
  #|let motif = note("E4 G4 A4");
  #|let orbit = note("D5 A4 G4 E5");
  #|let lead = motif.slow(3).gain(0.105);
  #|let answer = orbit.slow(4).jux(rev).gain(0.055);
  #|let kick = s("bd").gain(0.46);
  #|let hats = s("hh(5,8)").slow(4).every(3, rev).degradeBy(0.12).gain(0.065);
  #|let clap = s("cp(2,4,1)").slow(4).gain(0.13);
  #|let open_hat = s("oh(2,8,1)").slow(4).gain(0.055);
  #|let harmony = chord("Cmaj9 Am7 Fmaj9 G6").slow(48).gain(0.12);
  #|let bass = note("C2(3,8) A1(3,8,1) F2(3,8) G2(3,8,1)").slow(48).gain(0.25);
  #|let groove = stack(kick, clap, hats, open_hat);
  #|
  #|song(
  #|  section("seed",12,stack(lead,chord("Cmaj9").slow(12).gain(0.10))),
  #|  section("second_orbit",12,stack(lead,answer,s("hh(3,8)").slow(4).gain(0.045))),
  #|  section("ground",24,stack(lead,answer,kick,hats,note("C2(3,8) A1(3,8,1)").slow(24).gain(0.23),chord("Cmaj9 Am7").slow(24).gain(0.11))),
  #|  section("daybreak",48,stack(lead,answer,harmony,bass,groove)),
  #|  section("suspension",24,stack(chord("Fmaj9 Cmaj9").slow(24).gain(0.12),motif.slow(6).jux(rev).gain(0.075),orbit.slow(8).gain(0.065))),
  #|  section("refraction",23,stack(note("A4 G4 E4").slow(3).gain(0.105),answer,chord("Am7 G6").slow(24).gain(0.11),note("A1(3,8) G2(3,8,1)").slow(24).gain(0.23),s("bd(3,8)").slow(4).gain(0.40),hats,clap)),
  #|  section("one_breath",1,stack(note("C4").gain(0))),
  #|  section("confluence",24,stack(lead,answer,harmony,bass,groove,note("G5(2,8) E5(2,8,1)").slow(12).gain(0.035))),
  #|  section("alignment",24,stack(motif.slow(4).gain(0.105),answer,chord("Fmaj9 G6 Cmaj9").slow(24).gain(0.13),note("F2 G2 C2").slow(24).gain(0.25),groove)),
  #|  section("unthread",24,stack(lead,answer,chord("Fmaj9 Cmaj9").slow(24).gain(0.10),note("F2 C2").slow(24).gain(0.18),hats)),
  #|  section("remember",12,stack(motif.slow(6).gain(0.075),chord("Am7").slow(12).gain(0.10))),
  #|  section("still_light",12,stack(motif.slow(6).gain(0.06),chord("Cmaj9").slow(12).gain(0.085))),
  #|  part("r1","seed"),
  #|  part("r2","second_orbit"),
  #|  part("r3","ground"),
  #|  part("r4","daybreak"),
  #|  part("r5","suspension"),
  #|  part("r6","refraction"),
  #|  part("r7","one_breath"),
  #|  part("r8","confluence"),
  #|  part("r9","alignment"),
  #|  part("r10","unthread"),
  #|  part("r11","remember"),
  #|  part("r12","still_light")
  #|)

///|
test "Light Orbit named score preserves every event across 240 cycles and the ending" {
  let original = unwrap_parsed_song(@mini.parse_song(ORBIT_ORIGINAL))
  let named = unwrap_parsed_song(@mini.parse_song(ORBIT_NAMED))
  @debug.assert_eq(named.duration(), @pattern.Rational::from_int(240))
  @debug.assert_eq(named.occurrences().length(), 12)
  for cycle in 0..<242 {
    // Half-cycle queries cross non-integral onsets as well as section boundaries.
    for half in 0..<2 {
      let begin = (cycle * 2 + half).to_int64()
      let span = song_span(begin, 2L, begin + 1L, 2L)
      assert_named_events(song_events(named, span), song_events(original, span))
    }
  }
}
