///|
/// The score of the demo, in mini notation. It is one `song(...)` that names
/// reusable layers with `let`, combines them with `+`, and places sections
/// with `part`, `part_id`, an explicit start and a `fill`.
///
/// Cycle map at 124 BPM (one cycle is about 1.94 s):
///   0- 4 intro   4- 8 build   8-16 groove   16-18 break (fill)
///  18-20 riser  20-28 drop    28-32 outro
///
/// The riser was first written to overlap the end of the groove (an explicit
/// start at cycle 14). Playback admission refused the whole song with
/// "playback arrangement exceeds the query expansion limit", while every
/// section alone and the song without the overlap were admitted.
let song_source : String =
  #|let kick = s("bd*4");
  #|let kick_e = s("bd(3,8)");
  #|let snare = s("~ sd ~ sd").room(0.15);
  #|let clap = s("~ cp ~ [cp cp?]").gain(0.8).room(0.3);
  #|let hats = s("hh*8").gain("0.9 0.35 0.7 0.35").pan(sine.range(-0.4, 0.4));
  #|let opens = s("~ oh ~ oh").gain(0.5).pan(0.3);
  #|let ghosts = s("hh*16?").degradeBy(0.4).gain(0.3).jux(rev);
  #|let bass = note("A1 A1 [~ A2] A1 F1 F1 [~ F2] G1").slow(2).s("bass")
  #|  .gate(0.7).lpf(saw.range(300, 1400).slow(2), 4).hpf(35);
  #|let pad = chord("Am9 Fmaj7 C G7sus4").slow(8).s("pad")
  #|  .attack(1.2).release(2).lpf(tri.range(700, 2600).slow(8), 1.5).room(0.6);
  #|let arp = note("A3 C4 E4 A4 E4 C4 [G4 E4] C4").s("pluck")
  #|  .gate(0.5).pan(square.range(-0.6, 0.6).fast(2)).room(0.25).gain(0.7);
  #|let lead = note("E5@3 D5 C5@2 [B4 A4] ~ A4@2 G4 A4 C5@3 ~").slow(2)
  #|  .s("sawtooth").attack(0.01).release(0.25).lpf(3200, 2).room(0.35)
  #|  .gain(0.55).every(4, rev);
  #|let bells = chord("{69,76,81} ~ ~ {72,76,79} ~ ~ {67,74,79} ~").slow(2)
  #|  .attack(0.005).hold(0.05).release(0.6).room(0.7).gain(0.35)
  #|  .pan(cosine.range(-0.7, 0.7));
  #|let pings = s("ping ~ [~ ping] ~").gain(0.5).room(0.5).pan(-0.4);
  #|let tune = note("A5 E5 C6 B5").s("ping").gate(0.5).gain(0.35).room(0.6).pan(0.4);
  #|let bursts = s("burst(3,8,2)").begin(0.1).end(0.6).hpf(1200).gain(0.5);
  #|
  #|song(
  #|  bpm(124),
  #|  section("intro", 4, pad.fadeIn(4) + pings + bells),
  #|  section("build", 4, pad + kick_e + hats + arp.lpf(ramp.range(300, 5000).slow(4), 2)),
  #|  section("groove", 8, kick + snare + hats + opens + bass + arp + pad),
  #|  section("break", 2, pad + tune + bursts),
  #|  section("riser", 2, s("sd*8").gain(ramp.range(0.2, 1).slow(2)) + s("sd*16").gain(0.25)),
  #|  section("drop", 8, kick + clap + snare + hats.fast(2) + ghosts + bass + arp.jux(rev) + lead + bells + pad),
  #|  section("outro", 4, (pad + lead.slow(2) + pings).fadeOut(4)),
  #|  part("p1", "intro"),
  #|  part("p2", "build"),
  #|  part_id("p3", "main groove", "groove"),
  #|  part("p4", "riser", 18),
  #|  part("p5", "drop"),
  #|  fill("gap", "break"),
  #|  part("p6", "outro")
  #|)
