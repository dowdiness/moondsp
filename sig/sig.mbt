///|
/// PROTOTYPE v3: a value-style graph builder.
///
/// `Synth[K]` owns one node array; a `Sig[K]` is an index into it, so a
/// `let`-bound signal used twice stays one node. `K` is the host's control
/// key type. The result is the canonical `Array[DspNode]` plus a
/// `ControlBindingBuilder[K]`.
pub struct Synth[K] {
  priv nodes : Array[@moondsp.DspNode]
  priv keys : Array[K]
  priv gates : Map[String, Int32]
  priv token : Token
  priv mut bindings : @moondsp.ControlBindingBuilder[K]
  priv mut foreign : Int32
  priv mut closed : Bool
}

///|
/// Identity of one builder, shared with the params it hands out.
priv struct Token {
  mut uses : Int32
}

///|
/// A signal: one node of one `Synth`.
pub struct Sig[K] {
  priv owner : Synth[K]
  priv index : Int32
}

///|
/// A named control declared with `Synth::param`, with its default value.
pub struct Param {
  priv token : Token
  priv id : Int32
  priv default : Double
}

///|
/// A resolved node parameter.
pub enum Scalar {
  Fixed(Double)
  Bound(Param)
}

///|
/// Anything usable where a node parameter is expected: a number or a `Param`.
pub trait ToScalar {
  fn to_scalar(Self) -> Scalar
}

///|
pub impl ToScalar for Double with fn to_scalar(self) {
  Fixed(self)
}

///|
pub impl ToScalar for Int32 with fn to_scalar(self) {
  Fixed(self.to_double())
}

///|
pub impl ToScalar for Param with fn to_scalar(self) {
  Bound(self)
}

///|
/// What `Synth::build` returns. `nodes` is a private copy.
pub struct Template[K] {
  nodes : Array[@moondsp.DspNode]
  bindings : @moondsp.ControlBindingBuilder[K]
  priv gates : Map[String, Int32]
}

///|
/// Node index of a signal named with `Synth::gate`.
pub fn[K] Template::gate(self : Template[K], name : String) -> Int32? {
  self.gates.get(name)
}

///|
pub(all) suberror SigError {
  /// A signal or param made by another `Synth` was used. Carries how many
  /// times.
  ForeignSignal(Int32)
}

///|
/// Describe a graph with named controls. The callback returns the signal to
/// send to the output.
pub fn[K] Synth::build(f : (Synth[K]) -> Sig[K]) -> Template[K] raise SigError {
  let g : Synth[K] = {
    nodes: [],
    keys: [],
    gates: {},
    token: { uses: 0, },
    bindings: @moondsp.ControlBindingBuilder(),
    foreign: 0,
    closed: false,
  }
  let out = f(g)
  let index = g.own(out)
  g.nodes.push(@moondsp.DspNode::output(index))
  g.closed = true
  if g.foreign > 0 {
    raise ForeignSignal(g.foreign)
  }
  { nodes: g.nodes.copy(), bindings: g.bindings, gates: g.gates, }
}

///|
/// Describe a graph that has no named controls and get its nodes.
pub fn nodes(
  f : (Synth[Unit]) -> Sig[Unit],
) -> Array[@moondsp.DspNode] raise SigError {
  Synth::build(f).nodes
}

///|
fn[K] Synth::push(self : Synth[K], node : @moondsp.DspNode) -> Sig[K] {
  if self.closed {
    return { owner: self, index: -1, }
  }
  let index = self.nodes.length()
  self.nodes.push(node)
  { owner: self, index, }
}

///|
fn[K] Synth::own(self : Synth[K], sig : Sig[K]) -> Int32 {
  if !physical_equal(self, sig.owner) {
    self.foreign += 1
  }
  sig.index
}

///|
/// Resolve a scalar for the node about to be pushed at the current length.
fn[K] Synth::scalar(
  self : Synth[K],
  value : &ToScalar,
  slot : @moondsp.GraphParamSlot,
) -> Double {
  match value.to_scalar() {
    Fixed(v) => v
    Bound(param) => {
      if !physical_equal(self.token, param.token) {
        self.foreign += 1
      } else if !self.closed {
        self.bindings = self.bindings.bind(
          key=self.keys[param.id],
          node_index=self.nodes.length(),
          slot~,
        )
      }
      param.default
    }
  }
}

///|
/// Declare a named control with its default value.
pub fn[K] Synth::param(self : Synth[K], key : K, default~ : Double) -> Param {
  let id = self.keys.length()
  self.keys.push(key)
  self.token.uses += 1
  { token: self.token, id, default, }
}

///|
/// Bind a control to a per-voice parameter (applied outside the graph).
pub fn[K] Synth::voice(
  self : Synth[K],
  key : K,
  param : @moondsp.VoiceParam,
) -> Unit {
  self.bindings = self.bindings.bind_voice(key~, param~)
}

///|
/// Name a signal so the host can find its node index after `build`.
pub fn[K] Synth::gate(self : Synth[K], name : String, sig : Sig[K]) -> Sig[K] {
  self.gates[name] = self.own(sig)
  sig
}

///|
pub fn[K] Synth::constant(self : Synth[K], value : &ToScalar) -> Sig[K] {
  let v = self.scalar(value, Value0)
  self.push(@moondsp.DspNode::constant(v))
}

///|
/// An oscillator. A named frequency becomes a bound constant feeding it.
pub fn[K] Synth::osc(
  self : Synth[K],
  waveform : @moondsp.Waveform,
  freq : &ToScalar,
) -> Sig[K] {
  match freq.to_scalar() {
    Fixed(hz) => self.push(@moondsp.DspNode::oscillator(waveform, hz))
    Bound(_) => self.constant(freq).osc(waveform)
  }
}

///|
pub fn[K] Synth::saw(self : Synth[K], freq : &ToScalar) -> Sig[K] {
  self.osc(Saw, freq)
}

///|
pub fn[K] Synth::sine(self : Synth[K], freq : &ToScalar) -> Sig[K] {
  self.osc(Sine, freq)
}

///|
pub fn[K] Synth::noise(self : Synth[K], seed~ : UInt32) -> Sig[K] {
  self.push(@moondsp.DspNode::noise(seed))
}

///|
pub fn[K] Synth::adsr(
  self : Synth[K],
  attack_ms~ : Double,
  decay_ms~ : Double,
  sustain~ : Double,
  release_ms~ : Double,
) -> Sig[K] {
  self.push(
    @moondsp.DspNode::adsr(attack_ms~, decay_ms~, sustain~, release_ms~),
  )
}

///|
/// An oscillator whose frequency is this signal.
pub fn[K] Sig::osc(self : Sig[K], waveform : @moondsp.Waveform) -> Sig[K] {
  self.owner.push(@moondsp.DspNode::oscillator_from(self.index, waveform))
}

///|
fn[K] Sig::biquad(
  self : Sig[K],
  mode : @moondsp.BiquadMode,
  cutoff : &ToScalar,
  q : &ToScalar?,
) -> Sig[K] {
  let g = self.owner
  let cutoff_hz = g.scalar(cutoff, Value0)
  let q = match q {
    Some(q) => g.scalar(q, Value1)
    None => 0.707
  }
  g.push(@moondsp.DspNode::biquad(input=self.index, mode~, cutoff_hz~, q~))
}

///|
/// Low-pass filter. `q` defaults to 0.707.
pub fn[K] Sig::lpf(self : Sig[K], cutoff : &ToScalar, q? : &ToScalar) -> Sig[K] {
  self.biquad(LowPass, cutoff, q)
}

///|
/// High-pass filter. `q` defaults to 0.707.
pub fn[K] Sig::hpf(self : Sig[K], cutoff : &ToScalar, q? : &ToScalar) -> Sig[K] {
  self.biquad(HighPass, cutoff, q)
}

///|
pub fn[K] Sig::gain(self : Sig[K], amount : &ToScalar) -> Sig[K] {
  let g = self.owner
  let amount = g.scalar(amount, Value0)
  g.push(@moondsp.DspNode::gain(self.index, amount))
}

///|
/// Multiply by an envelope signal.
pub fn[K] Sig::envelope(
  self : Sig[K],
  env : Sig[K],
  amount~ : Double = 1.0,
) -> Sig[K] {
  let g = self.owner
  let envelope = g.own(env)
  g.push(@moondsp.DspNode::envelope_gain(input=self.index, envelope~, amount~))
}

///|
pub fn[K] Sig::clip(self : Sig[K], threshold : Double) -> Sig[K] {
  self.owner.push(@moondsp.DspNode::clip(self.index, threshold))
}

///|
/// `a + b` mixes two signals.
pub impl[K] Add for Sig[K] with fn add(self : Sig[K], other : Sig[K]) -> Sig[K] {
  let g = self.owner
  let right = g.own(other)
  g.push(@moondsp.DspNode::mix(self.index, right))
}

///|
/// `a * b` multiplies two signals.
pub impl[K] Mul for Sig[K] with fn mul(self : Sig[K], other : Sig[K]) -> Sig[K] {
  let g = self.owner
  let right = g.own(other)
  g.push(@moondsp.DspNode::mul(self.index, right))
}
