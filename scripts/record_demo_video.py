#!/usr/bin/env python3
"""
Record an MP4 video with high-fidelity AAC audio demonstrating pattern playback
and seamless loop-boundary edit application at 96 BPM.

Requirements:
- Python 3.8+
- agent-browser (pre-installed or npm i -g agent-browser)
- ffmpeg
"""

import base64
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS_DIR = os.path.join(REPO_ROOT, "docs", "assets")
FINAL_MP4 = os.path.join(ASSETS_DIR, "demo.mp4")
AMP_ARTIFACTS_DIR = os.path.join(REPO_ROOT, ".amp", "in", "artifacts")


def run_cmd(args, optional=False):
    res = subprocess.run(args, capture_output=True, text=True)
    if res.returncode != 0:
        if optional:
            return ""
        raise RuntimeError(f"Command failed ({res.returncode}): {' '.join(args)}\n{res.stderr}")
    return res.stdout.strip()


def create_browser_pointer_wrapper(temp_dir):
    """Create a wrapper script that forces desktop hover and pointer emulation in Chromium."""
    wrapper_path = os.path.join(temp_dir, "chrome-desktop-pointer.sh")
    script = """#!/usr/bin/env bash
set -euo pipefail
chrome=""
if [ -d "$HOME/.agent-browser/browsers" ]; then
    chrome=$(ls -d "$HOME"/.agent-browser/browsers/chrome-*/chrome 2>/dev/null | sort -V | tail -n 1)
fi
if [ -z "$chrome" ]; then
    chrome=$(which chromium || which google-chrome || which chrome || true)
fi
if [ -z "$chrome" ]; then
    echo "No Chromium binary found" >&2
    exit 1
fi
exec "$chrome" \\
    '--blink-settings=primaryHoverType=2,availableHoverTypes=2,primaryPointerType=4,availablePointerTypes=4' \\
    "$@"
"""
    with open(wrapper_path, "w") as f:
        f.write(script)
    os.chmod(wrapper_path, os.stat(wrapper_path).st_mode | stat.S_IEXEC)
    return wrapper_path


def create_audio_tap_script(temp_dir):
    """Create a WebAudio hook script that intercepts all AudioDestination connections into a MediaRecorder."""
    tap_path = os.path.join(temp_dir, "audio-tap.js")
    script = """(() => {
  window.__audioChunks = [];
  window.__mediaRecorder = null;
  window.__streamDest = null;

  const originalConnect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function(destinationNode, ...args) {
    if (destinationNode instanceof AudioDestinationNode) {
      const ctx = destinationNode.context;
      if (!window.__streamDest || window.__streamDest.context !== ctx) {
        window.__streamDest = ctx.createMediaStreamDestination();
        window.__mediaRecorder = new MediaRecorder(window.__streamDest.stream, {
          mimeType: 'audio/webm;codecs=opus'
        });
        window.__mediaRecorder.ondataavailable = (e) => {
          if (e.data.size > 0) window.__audioChunks.push(e.data);
        };
      }
      originalConnect.call(this, window.__streamDest, ...args);
    }
    return originalConnect.call(this, destinationNode, ...args);
  };

  window.__startAudioRecording = () => {
    window.__audioChunks = [];
    if (window.__mediaRecorder && window.__mediaRecorder.state !== 'recording') {
      window.__mediaRecorder.start(100);
    }
  };

  window.__stopAudioRecording = () => {
    return new Promise((resolve) => {
      if (window.__mediaRecorder && window.__mediaRecorder.state === 'recording') {
        window.__mediaRecorder.onstop = async () => {
          const blob = new Blob(window.__audioChunks, { type: 'audio/webm' });
          const reader = new FileReader();
          reader.onloadend = () => {
            resolve(reader.result);
          };
          reader.readAsDataURL(blob);
        };
        window.__mediaRecorder.stop();
      } else {
        resolve(null);
      }
    });
  };
})();
"""
    with open(tap_path, "w") as f:
        f.write(script)
    return tap_path


def main():
    os.makedirs(ASSETS_DIR, exist_ok=True)
    temp_dir = tempfile.mkdtemp(prefix="moondsp_demo_")

    try:
        wrapper_path = create_browser_pointer_wrapper(temp_dir)
        audio_tap_path = create_audio_tap_script(temp_dir)
        video_raw = os.path.join(temp_dir, "demo_raw.mp4")
        audio_raw = os.path.join(temp_dir, "demo_raw.webm")

        # Cleanup existing sessions
        run_cmd(["agent-browser", "--session", "record", "close"], optional=True)

        # Launch browser with desktop pointer emulation and audio tap
        run_cmd([
            "agent-browser", "--session", "record",
            "--executable-path", wrapper_path,
            "--init-script", audio_tap_path,
            "open", "https://moondsp.koji-ishimoto.workers.dev/"
        ])
        run_cmd(["agent-browser", "--session", "record", "set", "viewport", "960", "720", "2"])
        time.sleep(1.0)

        # Replace score cleanly
        run_cmd(["agent-browser", "--session", "record", "click", ".cm-content"])
        run_cmd(["agent-browser", "--session", "record", "eval", """(() => {
          const content = document.querySelector(".cm-content");
          const sel = window.getSelection();
          const range = document.createRange();
          range.selectNodeContents(content);
          sel.removeAllRanges();
          sel.addRange(range);
          document.execCommand("delete");
        })()"""])
        time.sleep(0.4)

        score = '''bpm(96);

$: s("bd [~ sd] [~ bd] sd").slow(4).gain(0.7)
$: s("hh*8").degradeBy(0.2).slow(4).gain(0.25)
$: chord("Cm7 Fm7 Gm7 Cm7").slow(4).gain(0.18)
$: note("C3 C3 Eb3 G3").slow(4).gain(0.52).lpf(3000)'''

        run_cmd(["agent-browser", "--session", "record", "keyboard", "inserttext", score])
        time.sleep(1.0)

        # Verify initial score
        current_text = run_cmd(["agent-browser", "--session", "record", "eval", "document.querySelector('.cm-content').innerText"])
        assert "C3 C3 Eb3 G3" in current_text, f"Initial score not set correctly: {current_text}"

        # Move mouse over Play button
        run_cmd(["agent-browser", "--session", "record", "mouse", "move", "50", "26"])
        time.sleep(0.3)

        # Start video capture
        run_cmd(["agent-browser", "--session", "record", "record", "start", video_raw, "--cursor"])

        # Click Play button (starts playback)
        run_cmd(["agent-browser", "--session", "record", "click", "#start"])

        # Start audio tap recording
        run_cmd(["agent-browser", "--session", "record", "eval", "window.__startAudioRecording()"])

        print("Recording initial groove (0.0s - 3.0s)...")
        time.sleep(3.0)

        # Move mouse to C3 note in the pitch grid
        run_cmd(["agent-browser", "--session", "record", "mouse", "move", "195", "487", "--human"])
        time.sleep(0.2)

        # Drag note up to G3
        run_cmd(["agent-browser", "--session", "record", "mouse", "down", "left"])
        time.sleep(0.1)
        run_cmd(["agent-browser", "--session", "record", "mouse", "move", "195", "350", "--human"])
        time.sleep(0.1)
        run_cmd(["agent-browser", "--session", "record", "mouse", "up", "left"])

        # Verify score changed in editor
        updated_text = run_cmd(["agent-browser", "--session", "record", "eval", "document.querySelector('.cm-content').innerText"])
        assert "G3 C3 Eb3 G3" in updated_text, f"Drag did not update editor text: {updated_text}"

        # Move mouse aside
        run_cmd(["agent-browser", "--session", "record", "mouse", "move", "320", "350", "--human"])

        print("Recording loop boundary transition (3.5s - 9.0s)...")
        time.sleep(5.0)

        # Stop recording
        run_cmd(["agent-browser", "--session", "record", "record", "stop"])
        b64_audio = run_cmd(["agent-browser", "--session", "record", "eval", "window.__stopAudioRecording()"])
        run_cmd(["agent-browser", "--session", "record", "close"], optional=True)

        if not b64_audio or "base64," not in b64_audio:
            raise RuntimeError("Audio recording failed: received empty or invalid audio data from browser tap")

        b64_data = b64_audio.split("base64,")[1]
        with open(audio_raw, "wb") as f:
            f.write(base64.b64decode(b64_data))

        audio_size = os.path.getsize(audio_raw)
        print(f"Captured lossless WebAudio stream ({audio_size} bytes)")
        if audio_size < 1000:
            raise RuntimeError(f"Audio file is suspiciously small ({audio_size} bytes)")

        # Multiplex video and audio with ffmpeg
        print("Muxing video and audio with AAC encoding...")
        cmd_mux = [
            "ffmpeg", "-y", "-i", video_raw, "-i", audio_raw,
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-profile:v", "baseline", "-level", "3.0", "-crf", "20", "-preset", "medium",
            "-c:a", "aac", "-b:a", "192k", "-shortest",
            FINAL_MP4
        ]
        subprocess.run(cmd_mux, check=True)

        if os.path.isdir(AMP_ARTIFACTS_DIR):
            artifact_mp4 = os.path.join(AMP_ARTIFACTS_DIR, "demo.mp4")
            shutil.copyfile(FINAL_MP4, artifact_mp4)

        print(f"Done! Final video saved to {FINAL_MP4} ({os.path.getsize(FINAL_MP4)} bytes)")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
