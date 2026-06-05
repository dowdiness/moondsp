///|
/// Audio-block frame derived from the scheduler clock.
///
/// `logical_arc` keeps the existing rational-cycle semantics; the sample range
/// gives the future song layer a stable audio-time anchor without changing the
/// current pattern scheduler behavior.
pub struct BlockFrame {
  sample_begin : Int64
  sample_end : Int64
  logical_arc : @pattern.TimeSpan
}

///|
/// Absolute performance/audio time in samples.
pub struct PerformanceTime {
  sample : Int64
}

///|
pub fn PerformanceTime::PerformanceTime(sample : Int64) -> PerformanceTime {
  { sample, }
}

///|
/// Optional authoring provenance for one scheduled event.
///
/// This intentionally lives in `scheduler/` instead of `pattern.Event` so the
/// pattern engine stays payload-polymorphic and independent of authoring IDs.
pub struct EventSource {
  priv pattern_node : @identity.PatternNodeId?
  priv pattern_nodes : Array[@identity.PatternNodeId]
  priv section : @identity.SectionId?
  priv layer : @identity.SectionLayerId?
  priv occurrence : @identity.OccurrenceId?
} derive(Eq, Debug)

///|
fn pattern_node_path_from_primary(
  pattern_node : @identity.PatternNodeId?,
) -> Array[@identity.PatternNodeId] {
  match pattern_node {
    Some(id) => [id]
    None => []
  }
}

///|
fn primary_pattern_node(
  pattern_nodes : Array[@identity.PatternNodeId],
) -> @identity.PatternNodeId? {
  if pattern_nodes.length() == 0 {
    None
  } else {
    Some(pattern_nodes[pattern_nodes.length() - 1])
  }
}

///|
pub fn EventSource::EventSource(
  pattern_node~ : @identity.PatternNodeId?,
  section~ : @identity.SectionId?,
  layer~ : @identity.SectionLayerId?,
  occurrence~ : @identity.OccurrenceId?,
) -> EventSource {
  {
    pattern_node,
    pattern_nodes: pattern_node_path_from_primary(pattern_node),
    section,
    layer,
    occurrence,
  }
}

///|
pub fn EventSource::from_pattern_nodes(
  pattern_nodes~ : Array[@identity.PatternNodeId],
  section~ : @identity.SectionId?,
  layer~ : @identity.SectionLayerId?,
  occurrence~ : @identity.OccurrenceId?,
) -> EventSource {
  let nodes = pattern_nodes.copy()
  {
    pattern_node: primary_pattern_node(nodes),
    pattern_nodes: nodes,
    section,
    layer,
    occurrence,
  }
}

///|
pub fn EventSource::none() -> EventSource {
  {
    pattern_node: None,
    pattern_nodes: [],
    section: None,
    layer: None,
    occurrence: None,
  }
}

///|
pub fn EventSource::pattern_node(
  self : EventSource,
) -> @identity.PatternNodeId? {
  self.pattern_node
}

///|
pub fn EventSource::pattern_nodes(
  self : EventSource,
) -> Array[@identity.PatternNodeId] {
  self.pattern_nodes.copy()
}

///|
pub fn EventSource::section(self : EventSource) -> @identity.SectionId? {
  self.section
}

///|
pub fn EventSource::layer(self : EventSource) -> @identity.SectionLayerId? {
  self.layer
}

///|
pub fn EventSource::occurrence(self : EventSource) -> @identity.OccurrenceId? {
  self.occurrence
}

///|
pub fn EventSource::is_empty(self : EventSource) -> Bool {
  self.pattern_node is None &&
  self.pattern_nodes.length() == 0 &&
  self.section is None &&
  self.layer is None &&
  self.occurrence is None
}

///|
/// Scheduler-local event wrapper that keeps provenance out of `pattern.Event`.
pub struct PlaybackEvent {
  priv event : @pattern.Event[@pattern.ControlMap]
  priv source : EventSource
}

///|
pub fn PlaybackEvent::PlaybackEvent(
  event~ : @pattern.Event[@pattern.ControlMap],
  source~ : EventSource,
) -> PlaybackEvent {
  { event, source }
}

///|
pub fn PlaybackEvent::event(
  self : PlaybackEvent,
) -> @pattern.Event[@pattern.ControlMap] {
  self.event
}

///|
pub fn PlaybackEvent::source(self : PlaybackEvent) -> EventSource {
  self.source
}

///|
fn copy_control_events(
  events : Array[@pattern.Event[@pattern.ControlMap]],
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  @voice_runtime.copy_control_events(events)
}

///|
fn copy_playback_events(events : Array[PlaybackEvent]) -> Array[PlaybackEvent] {
  let result : Array[PlaybackEvent] = []
  for event in events {
    result.push(event)
  }
  result
}

///|
fn EventSource::to_voice_runtime(
  self : EventSource,
) -> @voice_runtime.EventSource {
  @voice_runtime.EventSource(
    pattern_nodes=self.pattern_nodes,
    section=self.section,
    layer=self.layer,
    occurrence=self.occurrence,
  )
}

///|
fn event_source_from_voice_runtime(
  source : @voice_runtime.EventSource,
) -> EventSource {
  EventSource::from_pattern_nodes(
    pattern_nodes=source.pattern_nodes(),
    section=source.section(),
    layer=source.layer(),
    occurrence=source.occurrence(),
  )
}

///|
/// Tracks a sounding voice for gate-off scheduling.
struct ActiveNote {
  raw : @voice_runtime.ActiveNote
}

///|
fn ActiveNote::ActiveNote(
  handle~ : @moondsp.VoiceHandle,
  source~ : EventSource,
  end_sample~ : Int64,
) -> ActiveNote {
  // WHY end_sample from whole.end_: In the Strudel/Tidal model, `whole` is the
  // event's full intended duration in cycle time, while `part` is just the
  // fragment visible within the queried arc. The scheduler converts
  // `whole.end_` to performance time at note-on so future groove/rubato layers
  // can expire voices against audio time rather than logical time.
  {
    raw: @voice_runtime.ActiveNote(
      handle~,
      source=source.to_voice_runtime(),
      end_sample~,
    ),
  }
}

///|
fn ActiveNote::handle(self : ActiveNote) -> @moondsp.VoiceHandle {
  self.raw.handle()
}

///|
fn ActiveNote::source(self : ActiveNote) -> EventSource {
  event_source_from_voice_runtime(self.raw.source())
}

///|
fn ActiveNote::matches_edit_policy(
  self : ActiveNote,
  target : @edit_policy.AffectedVoiceTarget,
) -> Bool {
  let source = self.raw.source()
  @edit_policy.source_parts_match_target(
    pattern_nodes=source.borrow_pattern_nodes(),
    section=source.section(),
    layer=source.layer(),
    occurrence=source.occurrence(),
    target,
  )
}

///|
fn ActiveNote::expires_at(self : ActiveNote, sample : Int64) -> Bool {
  self.raw.expires_at(sample)
}

///|
fn ActiveNote::note_off(
  self : ActiveNote,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  self.raw.note_off(pool)
}

///|
fn ActiveNote::kill(self : ActiveNote, pool : @moondsp.BoundVoicePool) -> Unit {
  self.raw.kill(pool)
}

///|
/// Per-voice side-effect extracted from a control map entry.
/// The scheduler applies these after note-on, outside the control binding path.
pub enum VoiceAction {
  SetPan(Double)
}

///|
/// Decouples control key routing from the scheduler's event loop.
///
/// `transform` maps a raw (key, value) pair to an optional (key, value) for the
/// control binding map. Return `None` to drop the entry (e.g. "pan" is consumed
/// as a side-effect, not a DSP control). Return `Some((key, transformed_value))`
/// to include it.
///
/// `voice_action` inspects a raw (key, value) pair and optionally returns a
/// `VoiceAction` to apply after note-on (e.g. `SetPan`).
pub struct ControlMapper {
  transform : (String, Double) -> (String, Double)?
  voice_action : (String, Double) -> VoiceAction?
}

///|
#alias(new)
pub fn ControlMapper::ControlMapper(
  transform~ : (String, Double) -> (String, Double)?,
  voice_action~ : (String, Double) -> VoiceAction?,
) -> ControlMapper {
  { transform, voice_action }
}

///|
/// Default mapper that preserves the original hardcoded behavior:
/// - "note" values are converted from MIDI note numbers to Hz
/// - "pan" values are extracted as `SetPan` voice actions (not passed to controls)
/// - All other keys pass through unchanged
pub fn default_control_mapper() -> ControlMapper {
  ControlMapper(
    transform=fn(k, v) {
      if k == "pan" {
        None
      } else if k == "note" {
        Some(("note", midi_to_hz(v)))
      } else {
        Some((k, v))
      }
    },
    voice_action=fn(k, v) { if k == "pan" { Some(SetPan(v)) } else { None } },
  )
}

///|
/// Prepared scheduler input for the next authoring snapshot commit.
///
/// Pattern and song snapshots share the same pending slot so callers have one
/// coherent staging boundary when higher-level live orchestration prepares the
/// next playback state.
pub enum PlaybackSnapshot {
  Pattern(@pattern.PatternSnapshot[@pattern.ControlMap])
  Song(@song.SongSnapshot[@pattern.ControlMap])
}

///|
pub fn PlaybackSnapshot::pattern(
  snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
) -> PlaybackSnapshot {
  Pattern(snapshot)
}

///|
pub fn PlaybackSnapshot::song(
  snapshot : @song.SongSnapshot[@pattern.ControlMap],
) -> PlaybackSnapshot {
  Song(snapshot)
}

///|
fn PlaybackSnapshot::raw(self : PlaybackSnapshot) -> @playback.PlaybackSnapshot {
  match self {
    Pattern(snapshot) => @playback.PlaybackSnapshot::pattern(snapshot)
    Song(snapshot) => @playback.PlaybackSnapshot::song(snapshot)
  }
}

///|
pub fn PlaybackSnapshot::revision(
  self : PlaybackSnapshot,
) -> @identity.Revision {
  self.raw().revision()
}

///|
pub fn PlaybackSnapshot::song_layout_revision(
  self : PlaybackSnapshot,
) -> @identity.Revision? {
  self.raw().song_layout_revision()
}

///|
pub fn PlaybackSnapshot::query(
  self : PlaybackSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  self.raw().query_events(arc)
}

///|
fn event_source_from_playback_source(
  source : @playback.PlaybackEventSource,
) -> EventSource {
  EventSource::from_pattern_nodes(
    pattern_nodes=source.pattern_nodes(),
    section=source.section(),
    layer=source.layer(),
    occurrence=source.occurrence(),
  )
}

///|
fn playback_event_from_record(
  record : @playback.PlaybackEventRecord,
) -> PlaybackEvent {
  PlaybackEvent(
    event=record.event(),
    source=event_source_from_playback_source(record.source()),
  )
}

///|
/// Compatibility helper for consumers that want sourced scheduler events.
///
/// This allocates a wrapper array and is intentionally not used by the
/// audio-block processing path. Pattern snapshots tag queried events with their
/// root pattern node. Song snapshots tag queried events with occurrence,
/// section, and section-layer IDs when the snapshot was lowered from the
/// authoring layer.
pub fn PlaybackSnapshot::query_playback_events(
  self : PlaybackSnapshot,
  arc : @pattern.TimeSpan,
) -> Array[PlaybackEvent] {
  let result : Array[PlaybackEvent] = []
  let events = self.raw().query_playback_events(arc)
  for event in events {
    result.push(playback_event_from_record(event))
  }
  result
}

///|
pub struct PatternScheduler {
  priv mut bpm : Double
  priv mut sample_counter : Int64
  priv ctx : @moondsp.DspContext
  priv active_notes : Array[ActiveNote]
  priv mapper : ControlMapper
  priv playback_state : @playback.PlaybackState
}

///|
/// Reject NaN/Inf and clamp to minimum 1.0 BPM.
fn sanitize_bpm(bpm : Double) -> Double {
  @transport.sanitize_bpm(bpm)
}

///|
#alias(new)
pub fn PatternScheduler::PatternScheduler(
  bpm~ : Double,
  ctx~ : @moondsp.DspContext,
  mapper? : ControlMapper,
) -> PatternScheduler {
  {
    bpm: sanitize_bpm(bpm),
    sample_counter: 0L,
    ctx,
    active_notes: [],
    mapper: mapper.unwrap_or(default_control_mapper()),
    playback_state: @playback.PlaybackState(),
  }
}

///|
pub fn PatternScheduler::sample_counter(self : PatternScheduler) -> Int64 {
  self.sample_counter
}

///|
/// Current tempo in beats per minute. The value is always sanitized:
/// construction and `set_bpm` reject NaN/Inf and clamp to a minimum of 1.0.
pub fn PatternScheduler::bpm(self : PatternScheduler) -> Double {
  self.bpm
}

///|
pub fn PatternScheduler::active_note_count(self : PatternScheduler) -> Int {
  self.active_notes.length()
}

///|
pub fn PatternScheduler::active_note_source(
  self : PatternScheduler,
  index : Int,
) -> EventSource? {
  match self.active_notes.get(index) {
    Some(note) => Some(note.source())
    None => None
  }
}

///|
/// Current block frame without advancing the scheduler clock.
pub fn PatternScheduler::current_block(self : PatternScheduler) -> BlockFrame {
  let sample_begin = self.sample_counter
  let sample_end = @transport.block_sample_end(sample_begin, self.ctx)
  {
    sample_begin,
    sample_end,
    logical_arc: compute_arc(sample_begin, self.bpm, self.ctx),
  }
}

///|
fn PatternScheduler::advance_block(self : PatternScheduler) -> Unit {
  self.sample_counter = @transport.advance_block_sample(
    self.sample_counter,
    self.ctx,
  )
}

///|
/// Update tempo in-place. Newly scheduled notes use the updated tempo. Active
/// notes keep their already-computed performance-time gate-off sample.
pub fn PatternScheduler::set_bpm(self : PatternScheduler, bpm : Double) -> Unit {
  self.bpm = sanitize_bpm(bpm)
}

///|
/// Reset the transport to the beginning and forget tracked active notes.
pub fn PatternScheduler::reset_transport(self : PatternScheduler) -> Unit {
  self.sample_counter = 0L
  self.active_notes.clear()
}

///|
/// Reset the transport and immediately kill tracked active voices in `pool`.
pub fn PatternScheduler::reset_transport_and_kill_notes(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  for note in self.active_notes {
    note.kill(pool)
  }
  self.reset_transport()
}

///|
/// Stage a lowered authoring snapshot for playback. The staged snapshot becomes
/// active at the start of the next `process_snapshot_block` call, giving callers
/// a stable block boundary for pattern edits during playback.
pub fn PatternScheduler::queue_pattern_snapshot(
  self : PatternScheduler,
  snapshot : @pattern.PatternSnapshot[@pattern.ControlMap],
) -> Unit {
  self.queue_playback_snapshot(PlaybackSnapshot::pattern(snapshot))
}

///|
/// Stage a lowered song snapshot for playback. The snapshot carries both the
/// authoring revision and the narrower layout revision; both become observable
/// only when the snapshot commits at the next song snapshot block boundary.
pub fn PatternScheduler::queue_song_snapshot(
  self : PatternScheduler,
  snapshot : @song.SongSnapshot[@pattern.ControlMap],
) -> Unit {
  self.queue_playback_snapshot(PlaybackSnapshot::song(snapshot))
}

///|
/// Stage the next prepared playback snapshot. Pattern and song snapshots use
/// the same pending slot; if several edits arrive before the next audio block,
/// only the latest successfully prepared snapshot commits.
pub fn PatternScheduler::queue_playback_snapshot(
  self : PatternScheduler,
  snapshot : PlaybackSnapshot,
) -> Unit {
  self.playback_state.queue(snapshot.raw())
}

///|
pub fn PatternScheduler::has_active_pattern_snapshot(
  self : PatternScheduler,
) -> Bool {
  self.playback_state.has_active_pattern()
}

///|
pub fn PatternScheduler::has_pending_pattern_snapshot(
  self : PatternScheduler,
) -> Bool {
  self.playback_state.has_pending_pattern()
}

///|
pub fn PatternScheduler::has_active_song_snapshot(
  self : PatternScheduler,
) -> Bool {
  self.playback_state.has_active_song()
}

///|
pub fn PatternScheduler::has_pending_song_snapshot(
  self : PatternScheduler,
) -> Bool {
  self.playback_state.has_pending_song()
}

///|
pub fn PatternScheduler::has_active_playback_snapshot(
  self : PatternScheduler,
) -> Bool {
  self.playback_state.has_active()
}

///|
pub fn PatternScheduler::has_pending_playback_snapshot(
  self : PatternScheduler,
) -> Bool {
  self.playback_state.has_pending()
}

///|
pub fn PatternScheduler::active_playback_revision(
  self : PatternScheduler,
) -> @identity.Revision? {
  self.playback_state.active_revision()
}

///|
pub fn PatternScheduler::active_song_revision(
  self : PatternScheduler,
) -> @identity.Revision? {
  self.playback_state.active_song_revision()
}

///|
pub fn PatternScheduler::active_playback_song_layout_revision(
  self : PatternScheduler,
) -> @identity.Revision? {
  self.playback_state.active_song_layout_revision()
}

///|
pub fn PatternScheduler::active_song_layout_revision(
  self : PatternScheduler,
) -> @identity.Revision? {
  self.active_playback_song_layout_revision()
}

///|
fn PatternScheduler::commit_pending_playback_snapshot(
  self : PatternScheduler,
) -> Unit {
  self.playback_state.commit_pending()
}

///|
/// Convert MIDI note number to frequency in Hz.
/// Uses equal temperament: A4 (MIDI 69) = 440 Hz, each semitone is 2^(1/12).
pub fn midi_to_hz(midi : Double) -> Double {
  @voice_runtime.midi_to_hz(midi)
}

///|
/// Test helper: inject an active note for testing gate-off logic.
/// The caller must ensure the VoiceHandle is currently active in the pool,
/// or gate-off at expiry will silently no-op (note_off returns false).
pub fn PatternScheduler::push_active_note(
  self : PatternScheduler,
  handle : @moondsp.VoiceHandle,
  end_time : @pattern.Rational,
) -> Unit {
  self.push_active_note_with_source(handle, end_time, EventSource::none())
}

///|
/// Future-policy helper: inject an active note with explicit provenance.
fn PatternScheduler::push_active_note_with_source(
  self : PatternScheduler,
  handle : @moondsp.VoiceHandle,
  end_time : @pattern.Rational,
  source : EventSource,
) -> Unit {
  self.active_notes.push(
    ActiveNote(
      handle~,
      source~,
      end_sample=cycle_to_sample(end_time, self.bpm, self.ctx),
    ),
  )
}

///|
/// Gate-off all notes whose end sample has been reached, then remove them.
/// Block-quantized: notes ending mid-block stay active until the next block
/// (~2.7ms at 48kHz/128 samples — inaudible for musical purposes).
pub fn PatternScheduler::expire_notes_at(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  time : PerformanceTime,
) -> Unit {
  let mut i = 0
  while i < self.active_notes.length() {
    if self.active_notes[i].expires_at(time.sample) {
      self.active_notes[i].note_off(pool)
      // WHY swap-remove: Array::remove shifts all later elements O(n).
      // Swap with last + pop is O(1). Order of active_notes doesn't matter
      // because gate-off correctness depends only on end_sample, not position.
      let last = self.active_notes.length() - 1
      if i < last {
        self.active_notes[i] = self.active_notes[last]
      }
      ignore(self.active_notes.pop())
    } else {
      i = i + 1
    }
  }
}

///|
/// Compatibility wrapper for callers that still expire against a logical arc.
pub fn PatternScheduler::expire_notes(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  arc : @pattern.TimeSpan,
) -> Unit {
  self.expire_notes_at(
    pool,
    PerformanceTime(cycle_to_sample(arc.begin, self.bpm, self.ctx)),
  )
}

///|
/// Process pattern events: sort by onset, trigger note-ons, handle pan.
///
/// In the Strudel/Tidal model, each event has a `whole` span (the note's full
/// intended duration) and a `part` span (the fragment within the query arc).
/// Onset detection uses `whole.begin` — an event fires when its musical start
/// time falls within the current block. Events with `whole = None` are
/// continuous signals (no onset) and are skipped.
pub fn PatternScheduler::process_events(
  self : PatternScheduler,
  events : Array[@pattern.Event[@pattern.ControlMap]],
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  self.process_events_with_source(
    copy_control_events(events),
    arc,
    pool,
    EventSource::none(),
  )
}

///|
fn PatternScheduler::process_single_event(
  self : PatternScheduler,
  event : @pattern.Event[@pattern.ControlMap],
  source : EventSource,
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  match event.whole {
    None => ()
    Some(whole) =>
      if !arc.contains(whole.begin) {
        ()
      } else {
        // WHY fresh map: process_events takes Array[Event] so callers may
        // reuse event arrays across calls. Building a fresh map avoids
        // mutating the original ControlMap. The ControlMapper transforms
        // values (e.g. MIDI→Hz) and extracts per-voice actions (e.g. pan).
        let map : Map[String, Double] = {}
        let actions : Array[VoiceAction] = []
        let mapper = self.mapper
        event.value.each(fn(k, v) {
          match (mapper.voice_action)(k, v) {
            Some(action) => actions.push(action)
            None => ()
          }
          match (mapper.transform)(k, v) {
            Some((tk, tv)) => map[tk] = tv
            None => ()
          }
        })
        match pool.note_on_controls(map) {
          None => ()
          Some(handle) => {
            self.active_notes.push(
              ActiveNote(
                handle~,
                source~,
                end_sample=cycle_to_sample(whole.end_, self.bpm, self.ctx),
              ),
            )
            for action in actions {
              match action {
                SetPan(pan) => ignore(pool.set_voice_pan(handle, pan))
              }
            }
          }
        }
      }
  }
}

///|
fn PatternScheduler::process_events_with_source(
  self : PatternScheduler,
  events : Array[@pattern.Event[@pattern.ControlMap]],
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
  source : EventSource,
) -> Unit {
  // Sort by onset for deterministic voice allocation.
  // None-whole events sort last but are always skipped below.
  if events.length() > 1 {
    events.sort_by(fn(a, b) { @voice_runtime.compare_event_onset(a, b) })
  }
  for i in 0..<events.length() {
    self.process_single_event(events[i], source, arc, pool)
  }
}

///|
pub fn PatternScheduler::process_playback_events(
  self : PatternScheduler,
  events : Array[PlaybackEvent],
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  self.process_owned_playback_events(copy_playback_events(events), arc, pool)
}

///|
fn PatternScheduler::process_owned_playback_events(
  self : PatternScheduler,
  events : Array[PlaybackEvent],
  arc : @pattern.TimeSpan,
  pool : @moondsp.BoundVoicePool,
) -> Unit {
  // Sort by onset for deterministic voice allocation.
  // None-whole events sort last but are always skipped below.
  if events.length() > 1 {
    events.sort_by(fn(a, b) {
      @voice_runtime.compare_event_onset(a.event(), b.event())
    })
  }
  for i in 0..<events.length() {
    let playback_event = events[i]
    self.process_single_event(
      playback_event.event(),
      playback_event.source(),
      arc,
      pool,
    )
  }
}

///|
fn PatternScheduler::query_pattern_block(
  self : PatternScheduler,
  pat : @pattern.Pat[@pattern.ControlMap],
  frame : BlockFrame,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  ignore(self)
  pat.query(frame.logical_arc)
}

///|
fn PatternScheduler::query_snapshot_block(
  self : PatternScheduler,
  frame : BlockFrame,
) -> Array[@pattern.Event[@pattern.ControlMap]] {
  self.playback_state.query_active_events(frame.logical_arc)
}

///|
fn PatternScheduler::render_block(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  left.fill(0.0)
  right.fill(0.0)
  pool.process(self.ctx, left, right)
}

///|
fn PatternScheduler::process_block_events(
  self : PatternScheduler,
  events : Array[@pattern.Event[@pattern.ControlMap]],
  source : EventSource,
  frame : BlockFrame,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  self.process_events_with_source(events, frame.logical_arc, pool, source)
  self.advance_block()
  self.render_block(pool, left, right)
}

///|
/// Main entry point: called once per audio block (128 samples at 48kHz).
/// Computes the cycle-time arc, expires old notes, queries the pattern for
/// new events, triggers voices, advances the sample counter, and renders.
pub fn PatternScheduler::process_block(
  self : PatternScheduler,
  pat : @pattern.Pat[@pattern.ControlMap],
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let frame = self.current_block()
  self.expire_notes_at(pool, PerformanceTime(frame.sample_begin))
  let events = self.query_pattern_block(pat, frame)
  self.process_block_events(
    events,
    EventSource::none(),
    frame,
    pool,
    left,
    right,
  )
}

///|
/// Snapshot entry point kept for existing pattern-snapshot callers. It now
/// processes the unified prepared playback snapshot slot, so song snapshots
/// staged through `queue_song_snapshot` observe the same block-boundary
/// semantics.
pub fn PatternScheduler::process_snapshot_block(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  self.process_playback_snapshot_block(pool, left, right)
}

///|
/// Unified snapshot entry point for prepared pattern or song playback edits.
/// Pending snapshots are swapped in once at block start; note expiry and event
/// queries then observe the same committed playback state for the whole block.
pub fn PatternScheduler::process_playback_snapshot_block(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let frame = self.current_block()
  self.commit_pending_playback_snapshot()
  self.expire_notes_at(pool, PerformanceTime(frame.sample_begin))
  let events = self.query_snapshot_block(frame)
  self.process_block_events(
    events,
    EventSource::none(),
    frame,
    pool,
    left,
    right,
  )
}

///|
/// Song snapshot entry point for authoring-time song edits. Pending snapshots
/// are swapped in at the start of the audio block, so layout revisions become
/// visible on the same stable boundary as pattern snapshots.
pub fn PatternScheduler::process_song_snapshot_block(
  self : PatternScheduler,
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  self.process_playback_snapshot_block(pool, left, right)
}

///|
/// Section entry point with section-local timing semantics.
///
/// This intentionally routes through `Section::query` rather than the raw
/// `Section::body()` pattern so non-identity `TimeScope`s affect event timing
/// while keeping the scheduler's logical frame unchanged.
pub fn PatternScheduler::process_section_block(
  self : PatternScheduler,
  section : @song.Section[@pattern.ControlMap],
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let frame = self.current_block()
  self.expire_notes_at(pool, PerformanceTime(frame.sample_begin))
  let events = section.query(frame.logical_arc)
  self.process_block_events(
    events,
    EventSource::none(),
    frame,
    pool,
    left,
    right,
  )
}

///|
/// Song entry point with song-global layout timing semantics.
///
/// The song layer returns events in song-global logical time, matching the
/// scheduler frame's logical arc.
pub fn PatternScheduler::process_song_block(
  self : PatternScheduler,
  song : @song.Song[@pattern.ControlMap],
  pool : @moondsp.BoundVoicePool,
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  let frame = self.current_block()
  self.expire_notes_at(pool, PerformanceTime(frame.sample_begin))
  let events = song.query(frame.logical_arc)
  self.process_block_events(
    events,
    EventSource::none(),
    frame,
    pool,
    left,
    right,
  )
}

///|
/// Derive the cycle-time arc for a block from the integer sample counter.
///
/// At BPM, one cycle lasts 60/BPM seconds. The formula
/// `sample_counter * bpm / (sample_rate * 60)` gives the cycle position —
/// how many cycles have elapsed since playback started. Using Rational
/// arithmetic keeps this exact (no floating-point drift). Denominators are
/// bounded by `sample_rate * 60` (e.g. 2,880,000 for 48kHz).
pub fn compute_arc(
  sample_counter : Int64,
  bpm : Double,
  ctx : @moondsp.DspContext,
) -> @pattern.TimeSpan {
  @transport.compute_arc(sample_counter, bpm, ctx)
}

///|
/// Convert an absolute logical cycle position into the first sample at or after
/// that cycle position for the scheduler's BPM scaling convention.
pub fn cycle_to_sample(
  cycle : @pattern.Rational,
  bpm : Double,
  ctx : @moondsp.DspContext,
) -> Int64 {
  @transport.cycle_to_sample(cycle, bpm, ctx)
}
