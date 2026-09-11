///|
priv struct PlaybackLayoutRow {
  id : String
  name : String
  section : String
  start : @pattern.Rational
  length : @pattern.Rational
  rate : @pattern.Rational
} derive(Eq)

///|
priv enum PlaybackLayout {
  PatternLayout
  SongLayout(Array[PlaybackLayoutRow])
} derive(Eq)

///|
priv struct PreparedPlayback {
  snapshots : Array[@scheduler.PlaybackSnapshot]
  layout : PlaybackLayout
  bpm : Double?
}

///|
fn song_layout(song : @song.Song[@pattern.ControlMap]) -> PlaybackLayout {
  SongLayout(
    song
    .occurrences()
    .map(o => {
      id: o.id().value(),
      name: o.name(),
      section: o.section().name(),
      start: o.start(),
      length: o.section().length_cycles(),
      rate: o.section().scope().rate(),
    }),
  )
}

///|
fn song_update_snapshot(
  song : @song.Song[@pattern.ControlMap],
) -> @song.SongSnapshot[@pattern.ControlMap] raise {
  let parts = song
    .occurrences()
    .map(o => {
      let section = @song.SectionDoc::single(
        id=@identity.SectionId::from_string("live:" + o.id().value()),
        name=o.section().name(),
        length_cycles=o.section().length_cycles(),
        scope=o.section().scope(),
        layer_id=@identity.SectionLayerId::from_string("live:body"),
        body=o.section().body(),
      )
      @song.SongOccurrenceDoc::at(
        id=o.id(),
        start=o.start(),
        name=o.name(),
        section~,
      )
    })
  @song.SongDoc(parts~).lower()
}

///|
fn prepare_pattern(
  text : String,
  selectors : Array[SchedulerRouteSelector],
) -> Result[PreparedPlayback, String] {
  match @mini.parse(text) {
    Err(msg) => Err(msg)
    Ok(pat) => {
      let snapshots = route_patterns(pat, selectors).map(pat => {
        @scheduler.PlaybackSnapshot::pattern(
          @pattern.PatternDoc::from_pattern(
            id=@identity.PatternNodeId::from_string("live:pattern"),
            pat~,
          ).lower(),
        )
      }) catch {
        _ => return Err("could not prepare pattern update")
      }
      Ok({ snapshots, layout: PatternLayout, bpm: None })
    }
  }
}

///|
fn prepare_song(
  text : String,
  selectors : Array[SchedulerRouteSelector],
) -> Result[PreparedPlayback, String] {
  match @mini.parse_song_with_bpm(text) {
    Err(msg) => Err(msg)
    Ok(parsed) => {
      if parsed.bpm() is Some(bpm) {
        if @scheduler.normalize_bpm(bpm) is Err(_) {
          return Err("tempo must be 0.001..1000 BPM")
        }
      }
      match route_songs(parsed.song(), selectors) {
        Err(msg) => Err(msg)
        Ok(songs) => {
          let snapshots = songs.map(song => {
            @scheduler.PlaybackSnapshot::song(song_update_snapshot(song))
          }) catch {
            _ => return Err("could not prepare song update")
          }
          Ok({
            snapshots,
            layout: song_layout(parsed.song()),
            bpm: parsed.bpm(),
          })
        }
      }
    }
  }
}

///|
priv enum ApplyPolicy {
  Continue
  Restart
}

///|
priv struct PendingPlayback {
  playback : PreparedPlayback
  policy : ApplyPolicy
  tempo : Double?
}

///|
priv struct PlaybackState {
  active : PreparedPlayback?
  pending : PendingPlayback?
}

///|
/// Pure admission and transition; transport/voices are changed only by commit.
fn queue_playback(
  state : PlaybackState,
  next : PreparedPlayback,
  policy : ApplyPolicy,
) -> Result[PlaybackState, String] {
  match policy {
    Continue =>
      match state.active {
        None => return Err("start playback before updating")
        Some(active) if active.layout != next.layout =>
          return Err("playback mode or song layout changed; restart required")
        Some(_) => ()
      }
    Restart => ()
  }
  Ok({
    active: state.active,
    pending: Some({ playback: next, policy, tempo: next.bpm }),
  })
}

///|
/// Restart uses the applied score, cancelling any pending replacement.
fn restart_current(state : PlaybackState) -> Result[PlaybackState, String] {
  match state.active {
    None => Err("no applied playback to restart")
    Some(active) =>
      Ok({
        active: state.active,
        pending: Some({ playback: active, policy: Restart, tempo: None }),
      })
  }
}

///|
/// Audio-owner shell. Prepared tokens never cross the audio owner as objects.
let playback_state : @ref.Ref[PlaybackState] = @ref.new({
  active: None,
  pending: None,
})

///|
let prepared_slot : @ref.Ref[(Int, PreparedPlayback)?] = @ref.new(None)

///|
let prepared_sequence : @ref.Ref[Int] = @ref.new(0)

///|
fn reset_playback_state() -> Unit {
  playback_state.val = { active: None, pending: None }
  prepared_slot.val = None
  playback_input_chars.clear()
}

///|
/// Retain at most one prepared result. Tokens prevent stale/failed preparation
/// from applying an unrelated score. Zero signals preparation failure.
fn retain_prepared(result : Result[PreparedPlayback, String]) -> Int {
  prepared_slot.val = None
  match result {
    Err(message) => {
      ignore(set_scheduler_parse_error(message))
      0
    }
    Ok(prepared) => {
      if prepared_sequence.val == 2147483647 {
        ignore(set_scheduler_parse_error("prepared token space exhausted"))
        return 0
      }
      prepared_sequence.val = prepared_sequence.val + 1
      prepared_slot.val = Some((prepared_sequence.val, prepared))
      ignore(set_scheduler_parse_success())
      prepared_sequence.val
    }
  }
}

///|
pub fn prepare_pattern_input() -> Int {
  let text = input_chars_to_string(playback_input_chars)
  playback_input_chars.clear()
  if sched_routes.val.is_empty() {
    return retain_prepared(Err("initialize playback before preparing"))
  }
  retain_prepared(
    prepare_pattern(text, sched_routes.val.map(route => route.selector)),
  )
}

///|
pub fn prepare_song_input() -> Int {
  let text = input_chars_to_string(playback_input_chars)
  playback_input_chars.clear()
  if sched_routes.val.is_empty() {
    return retain_prepared(Err("initialize playback before preparing"))
  }
  retain_prepared(
    prepare_song(text, sched_routes.val.map(route => route.selector)),
  )
}

///|
/// Successful application consumes the token and queues an atomic operation.
pub fn apply_prepared_playback(token : Int, restart : Bool) -> Int {
  match prepared_slot.val {
    Some((id, prepared)) if id == token => {
      let policy = if restart { Restart } else { Continue }
      match queue_playback(playback_state.val, prepared, policy) {
        Err(message) => set_scheduler_parse_error(message)
        Ok(next) => {
          // Admission owns the representability check. Until commit, no public
          // host operation advances the clock or adds musical note endpoints.
          // Direct BPM edits preserve those inputs; reset clears this request.
          if policy is Continue && prepared.bpm is Some(bpm) {
            for route in sched_routes.val {
              if route.pool.scheduler.validate_bpm(bpm) is Err(_) {
                return set_scheduler_parse_error(
                  "tempo change exceeds transport range",
                )
              }
            }
          }
          playback_state.val = next
          prepared_slot.val = None
          set_scheduler_parse_success()
        }
      }
    }
    _ =>
      set_scheduler_parse_error("invalid or consumed prepared playback token")
  }
}

///|
pub fn discard_prepared_playback(token : Int) -> Bool {
  match prepared_slot.val {
    Some((id, _)) if id == token => {
      prepared_slot.val = None
      true
    }
    _ => false
  }
}

///|
pub fn restart_playback() -> Int {
  match restart_current(playback_state.val) {
    Err(message) => set_scheduler_parse_error(message)
    Ok(next) => {
      playback_state.val = next
      set_scheduler_parse_success()
    }
  }
}

///|
/// The only playback commit/render entry. Reset and replacement precede
/// every route's query, so no block can observe a partly reset score.
fn commit_playback_request() -> Unit {
  match playback_state.val.pending {
    None => ()
    Some(request) => {
      match request.policy {
        Restart =>
          for route in sched_routes.val {
            route.pool.scheduler.reset_transport_and_kill_notes(route.pool.pool)
          }
        Continue => ()
      }
      match request.tempo {
        Some(bpm) =>
          for route in sched_routes.val {
            // Admission proved this for the unchanged anchor and endpoints.
            // Restart instead uses a fresh clock with no active notes.
            route.pool.scheduler.set_bpm(bpm).unwrap()
          }
        None => ()
      }
      for i in 0..<sched_routes.val.length() {
        sched_routes.val[i].pool.scheduler.queue_playback_snapshot(
          request.playback.snapshots[i],
        )
      }
      playback_state.val = { active: Some(request.playback), pending: None }
    }
  }
}

///|
fn process_snapshot_routes(
  left : @moondsp.AudioBuffer,
  right : @moondsp.AudioBuffer,
) -> Unit {
  for route in sched_routes.val {
    let sp = route.pool
    sp.tmp_left.fill(0.0)
    sp.tmp_right.fill(0.0)
    sp.scheduler.process_playback_snapshot_block(
      sp.pool,
      sp.tmp_left,
      sp.tmp_right,
    )
    accumulate_sub_pool(sp, left, right)
  }
}

///|
/// Position of the next block, also used in application acknowledgements.
pub fn scheduler_sample_position() -> Double {
  match sched_routes.val.get(0) {
    Some(route) => route.pool.scheduler.sample_counter().to_double()
    None => 0.0
  }
}
