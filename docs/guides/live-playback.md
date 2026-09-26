# How playback works

The browser editor plays the score you write in
[Mini notation](../mini-notation.md). This guide explains what the transport
buttons do, how edits reach the audio engine, and what the preview controls
accept. For hands-on examples, read the
[Live-coding cookbook](live-coding-cookbook.md).

<!-- LIVE_PLAYBACK_GUIDE_START -->
<h2 id="playback-time">Time and cycles</h2>
<p>The scheduler counts in <strong>cycles</strong>, not bars or beats. A cycle has no fixed meter; it is just the unit the timeline advances in. Tempo sets how fast cycles pass:</p>
<ul>
  <li>Seconds per cycle = <code>60 / BPM</code>. At 60 BPM one cycle is one second; at 120 BPM it is half a second.</li>
  <li>The clock accepts 0.001–1000 BPM and rounds to the nearest 0.001 BPM. An invalid tempo edit leaves the clock unchanged.</li>
  <li>Each entry keeps its own period. Starting together, plain one-cycle patterns stretched with <code>.slow(3)</code> and <code>.slow(5)</code> repeat every three and five cycles; their starts meet again after 15 cycles.</li>
  <li>Song sections are measured in cycles. A <code>section("groove", 16, pattern)</code> lasts 16 cycles of whatever tempo the song chose.</li>
  <li>Normalized phase runs from 0 to 1 across each entry's period, independent of tempo. <code>.phase(transpose(2), 0.5)</code> moves onsets in the second half of that period.</li>
  <li>Envelope times (<code>.attack</code>, <code>.hold</code>, <code>.release</code>) are physical seconds. They do not change when tempo changes.</li>
</ul>
<p>Position in the status line counts cycles from the start. There is no time-signature or bar-number mapping.</p>

<h2 id="playback-edits">Draft, accepted, and sounding</h2>
<p>The editor distinguishes three things while you play:</p>
<ul>
  <li><strong>Draft</strong> — what the editor currently shows. It may still change before a reply arrives.</li>
  <li><strong>Accepted</strong> — the latest submission the audio engine acknowledged. Acceptance does not mean every part has switched yet.</li>
  <li><strong>Currently sounding</strong> — the material versions the listener hears. Each part keeps its previous content until its own next entry boundary.</li>
</ul>
<p>Once the audio session is open, valid edits are submitted automatically, including while paused. Each material updates at its own entry point, so different layers can change at different times. Pending changes wait for playback to reach those boundaries; acceptance alone does not make them audible.</p>
<p>An invalid draft does not replace the accepted score. Playback continues with the last working version. Fix the error, and the next accepted update takes over at the usual entry boundaries.</p>
<p>The status panel explains whether changes are accepted, pending, or rejected. Open <strong>Technical details</strong> for editor and engine versions and material-transition counts. Brief source highlights mark executed note onsets; they do not mean every draft change is sounding, or show how long a voice continues to ring.</p>

<h2 id="playback-transport">Play, Pause, and Restart</h2>
<ul>
  <li><strong>Play</strong> starts from the current position. If nothing is accepted yet, it submits the editor source and starts from the beginning. If playback is paused, it resumes where it stopped.</li>
  <li><strong>Pause</strong> freezes playback position, not editing. Press Play again to continue; accepted edits still wait for their playback entry boundaries.</li>
  <li><strong>Restart</strong> submits the current editor source and, if accepted, starts it from the beginning. Use it after changing a song's section and part layout. An invalid draft cannot replace the working score.</li>
</ul>
<p>Play and Pause share one button. The app recognizes patterns and songs automatically; no mode selector is needed. See <a href="../mini-notation.md#song-placement">song syntax</a> and <a href="live-coding-cookbook.md">Recipes</a> for complete examples.</p>

<h2 id="playback-preview">Preview and range controls</h2>
<p>After a song is accepted, the preview panel lists its placed sections with two buttons:</p>
<ul>
  <li><strong>Play from here</strong> seeks to that section's start cycle.</li>
  <li><strong>Loop section</strong> repeats that section's half-open cycle range.</li>
</ul>
<p>Below the section list, the range fields give finer control:</p>
<ul>
  <li><strong>From cycle</strong> and <strong>To cycle (exclusive)</strong> accept 0.001-cycle steps. Press <strong>Loop range</strong> to repeat that half-open interval, including ranges that cross section boundaries.</li>
  <li><strong>Whole song</strong> clears any active loop and resets position to zero.</li>
</ul>
<p>All preview controls use the accepted arrangement, not an invalid or pending draft. Section buttons retain exact fractional boundaries; manually entered ranges use 0.001-cycle precision. See <a href="../mini-notation.md#song-placement">section and part placement</a> to relate those positions to the score.</p>
<p>Seeking — whether to a section or a cycle number — clears active voices and room tails at the destination. A natural loop wrap at the end of a range lets voices and reverb decay instead of cutting them.</p>

<h2 id="playback-limits">What Mini does not cover</h2>
<p>The browser instruments are a small, fixed set of voices driven by Mini events. Mini owns event timing and numeric controls; it does not own DSP graph topology. For the full boundary contract, read the
<a href="https://github.com/dowdiness/moondsp/blob/main/docs/mini-graph-authoring-boundary.md">Mini pattern ↔ graph authoring boundary</a>.</p>
<ul>
  <li>You cannot describe arbitrary graph topology — node wiring, custom DSP chains, or new node kinds — from Mini notation alone.</li>
  <li>There is no dedicated meter, swing, accent, or continuous automation syntax in this composition path. Source edits remain quantized at existing material entry boundaries.</li>
  <li>Drum templates (<code>s("bd")</code>, <code>s("sd")</code>, and so on) keep their authored level and filter shape. Applying <code>.gain()</code>, <code>.lpf()</code>, or <code>.hpf()</code> to <code>s("...")</code> leaves the drum sound unchanged; those controls shape note and chord voices only.</li>
</ul>
<!-- LIVE_PLAYBACK_GUIDE_END -->
