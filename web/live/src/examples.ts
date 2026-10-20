// Functional core for Help's music: the starting sounds, which play at once,
// and the examples, which replace the score without playing. Help draws its
// cards and buttons from these lists, so each entry is written once.
import envelopeComparison from "../../../examples/envelope-comparison.mini?raw";
import roomOfLight from "../../../examples/room-of-light.mini?raw";
import lightOrbit from "../../../examples/light-orbit.mini?raw";
import sharedRoomComparison from "../../../examples/shared-room-comparison.mini?raw";
import sharedRoomAfterglow from "../../../examples/shared-room-afterglow.mini?raw";
import overlayGroove from "../../../examples/overlay-groove.mini?raw";
import overlayGrouping from "../../../examples/overlay-grouping.mini?raw";
import restsAndGates from "../../../examples/rests-and-gates.mini?raw";

export type StartingSound = Readonly<{
  title: string;
  /** The card's drawing: SVG elements in a 100 × 64 box, coloured by `artClass`. */
  art: string;
  artClass: string;
  source: string;
}>;

export type Example = Readonly<{
  label: string;
  /** A sentence shown under the button. */
  note?: string;
  /** Listed under More examples rather than with the featured examples. */
  more?: true;
  source: string;
}>;

export const STARTING_SOUNDS: readonly StartingSound[] = [
  { title: "First light", artClass: "scene-art-light", art: '<circle cx="34" cy="32" r="25"/><path d="M55 7h10a25 25 0 0 1 0 50H55Z"/>',
    source: `bpm(96);

$: s("bd ~ sd ~ bd bd sd ~").slow(4)
$: s("hh hh hh hh hh hh hh hh").slow(4)
$: note("C4 ~ Eb4 G4 Bb4 ~ G4 Eb4").slow(4).gain(0.25).lpf(1800)` },
  { title: "Offbeat", artClass: "scene-art-offbeat", art: '<path d="M8 39h23V14h23v25h23V14h15v39H8Z"/>',
    source: `bpm(112);

$: s("bd ~ ~ bd sd ~ bd ~").slow(4)
$: s("~ hh ~ hh ~ hh ~ oh").slow(4)
$: note("C3 ~ C3 Eb3 ~ G3 Bb3 ~").slow(4).gain(0.3).lpf(1200)` },
  { title: "Slow drift", artClass: "scene-art-drift", art: '<ellipse cx="50" cy="32" rx="42" ry="23"/><ellipse cx="50" cy="32" rx="27" ry="23"/><ellipse cx="50" cy="32" rx="10" ry="23"/>',
    source: `bpm(72);

$: s("bd ~ ~ ~ sd ~ ~ ~").slow(4)
$: note("C4 ~ G4 ~ Eb4 ~ Bb4 ~").slow(4).gain(0.2).lpf(2400)
$: chord("Cm7 Abmaj7").slow(8).gain(0.12).lpf(900)` },
  { title: "Moonrise", artClass: "scene-art-rise", art: '<path d="M14 50a36 36 0 0 1 72 0Z"/><path d="M6 50h88"/>',
    source: `bpm(104);

$: s("bd ~ ~ bd sd ~ bd ~, hh*8").slow(4)
$: note("A2 ~ A2 C3 ~ E3 G2 ~").slow(4).gain(0.3).lpf(900)
$: chord("Am7 Fmaj7 Cmaj7 G").slow(16).gain(0.12).lpf(1400)
$: note("E5 ~ C5 D5 ~ B4 G4 A4").slow(8).gain(0.16).lpf(3200)` },
];

export const EXAMPLES: readonly Example[] = [
  { label: "Overlay groove: + layers", note: "Drums, bass, and a stereo melody loop. The final .slow(2) slows both melodies inside parentheses.",
    source: `bpm(96);\n${overlayGroove}` },
  { label: "Space in the groove: rests + gate", note: "Rests keep every step in place; gate(0.35) shortens the bass without moving its attacks.",
    source: `bpm(96);\n${restsAndGates}` },
  { label: "Grouping A/B: hear the parentheses", note: "20 seconds: fast hats first, then fast kick and hats. Compare kick + hats.fast(2) with (kick + hats).fast(2).",
    source: overlayGrouping },
  { label: "One note, three envelopes", note: "Same E4: short → swell → drift. 23 seconds.",
    source: envelopeComparison },
  { label: "Carve the mix: cutoff + resonance", note: "LPF warms the chords; HPF clears lows from the lead. The second argument adds emphasis at each cutoff.",
    source: `bpm(84);
let warm = chord("Cmaj7 Fmaj7").slow(4).gain(0.45).lpf(900, 2.5).hpf(60);
let air = note("G5 E5 D5 B4").slow(4).gain(0.2).lpf(5000).hpf(1200, 1.4);
stack(warm, air)` },
  { label: "Room of Light — pop sketch", note: "Short bass, soft chords, and a singing lead. 39 seconds.",
    source: roomOfLight },
  { label: "Dry → shared room comparison", note: "Same groove dry, then drums and chords send into one room. 16 seconds.",
    source: sharedRoomComparison },
  { label: "Shared Room Afterglow", note: "Dry low end, drifting polyrhythms, a sparse room break, and one shared tail. 60 seconds.",
    source: sharedRoomAfterglow },
  { label: "Drifting notes — long envelopes", note: "Each note lasts 13 seconds. Try changing release(8).",
    source: `note("E4 G4 D4").slow(21).attack(2).hold(3).release(8)` },
  { label: "Independent entries — 3 and 4 cycles", note: "Change E4 to F4 and D5 to C5 while playing.", more: true,
    source: `let melody = note("E4 G4 A4").slow(3).gain(0.12);
let response = note("D5 A4 G4 E5").slow(4).gain(0.08);
stack(melody, response)` },
  { label: "Shared melody + live tempo", note: "Change bpm(60) to bpm(72) while playing.", more: true,
    source: `let melody = note("E4 G4 A4").slow(3).gain(0.12);
let beat = s("bd hh sd hh").slow(4).gain(0.2);
song(
  bpm(60),
  section("opening", 12, melody),
  section("groove", 24, stack(melody, beat)),
  part("first", "opening"),
  part("second", "groove")
)` },
  { label: "Light Orbit — full song, sets BPM 120", note: "Edit motif or orbit near the top.", more: true,
    source: `bpm(120);\n${lightOrbit}` },
  { label: "Named motif + groove", more: true,
    source: `let motif = note("E4 G4 A4").slow(3);
let groove = stack(motif, s("bd").gain(0.3));
groove` },
  { label: 'song("ode" — multiline melody + kick, sets BPM 72)', more: true,
    source: `bpm(72);
song(
  section(
    "ode",
    256,
    stack(
      s("bd").slow(4),
      note("64 64 65 67
67 65 64 62
60 60 62 64
64 62 62 62").slow(16)
    )
  ),
  part("ode1", "ode")
)` },
  { label: 'chord("C") — C major triad', more: true,
    source: `chord("C")` },
  { label: 'chord("C Dm G7 C").slow(2) — chord progression', more: true,
    source: `chord("C Dm G7 C").slow(2)` },
  { label: 'chord("Cmaj7").gain(0.4) — major 7th chord', more: true,
    source: `chord("Cmaj7").gain(0.4)` },
  { label: 'note("C4 E4 G4 C5").slow(2) — note names instead of numbers', more: true,
    source: `note("C4 E4 G4 C5").slow(2)` },
  { label: 'note("C D E F G A B C5").slow(2) — C major scale with note names', more: true,
    source: `note("C D E F G A B C5").slow(2)` },
  { label: 's("bd sd hh sd")', more: true,
    source: `s("bd sd hh sd")` },
  { label: 's("bd(3,8), hh*16?, sd(2,8,2)").jux(rev)', more: true,
    source: `s("bd(3,8), hh*16?, sd(2,8,2)").jux(rev)` },
  { label: 's("bd*4").every(3, fast(2))', more: true,
    source: `s("bd*4").every(3, fast(2))` },
  { label: 'note("C4 E4 G4").jux(rev)', more: true,
    source: `note("C4 E4 G4").jux(rev)` },
  { label: 's("[bd sd, hh*8]").degradeBy(0.3)', more: true,
    source: `s("[bd sd, hh*8]").degradeBy(0.3)` },
  { label: '$: s("bd sd hh sd") / $: chord("C Dm G7")', more: true,
    source: `$: s("bd sd hh sd")
$: chord("C Dm G7")` },
  { label: 'note("60(3,8) 64(2,8,2) 67(3,8) 64(2,8) 60(3,8) 62(2,8,3) 64(3,8) 67(2,8)").slow(4).every(4, rev)', more: true,
    source: `note("60(3,8) 64(2,8,2) 67(3,8) 64(2,8) 60(3,8) 62(2,8,3) 64(3,8) 67(2,8)").slow(4).every(4, rev)` },
  { label: '$: s("bd(3,8), hh(5,16)?, sd(2,8,4)").slow(2) / $: note("C4…").slow(3)', more: true,
    source: `$: s("bd(3,8), hh(5,16)?, sd(2,8,4)").slow(2)
$: note("C4(3,8) E4(2,8,2) G4(3,8) E4(2,8,3) C4(3,8)").slow(3)` },
  { label: 'note("48(3,8) 55(2,8,2) 60(3,8) 64(2,8) 67(3,8) 72(1,8)? 67(2,8,2) 60(3,8)").slow(4).jux(rev)', more: true,
    source: `note("48(3,8) 55(2,8,2) 60(3,8) 64(2,8) 67(3,8) 72(1,8)? 67(2,8,2) 60(3,8)").slow(4).jux(rev)` },
  { label: '$: s("bd…").slow(2).jux(slow(2)) / $: note("46…").slow(2).jux(slow(2))', more: true,
    source: `$: s("bd(1,4), sd(1,4,2)").slow(2).jux(slow(2))
$: note("46*4 60*8, 40*16 192(1,16)?").slow(2).jux(slow(2))` },
];

/** The score a first visit opens with. */
export const FIRST_SCORE = STARTING_SOUNDS[0].source;
