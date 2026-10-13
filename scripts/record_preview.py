#!/usr/bin/env python3
"""
Record a silent, looping preview GIF showing note dragging and shared undo.

Requirements:
- Python 3.8+
- agent-browser (pre-installed or npm i -g agent-browser)
- ffmpeg
"""

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS_DIR = os.path.join(REPO_ROOT, "docs", "assets")
GIF_OUT = os.path.join(ASSETS_DIR, "preview.gif")
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


def main():
    os.makedirs(ASSETS_DIR, exist_ok=True)
    temp_dir = tempfile.mkdtemp(prefix="moondsp_preview_")

    try:
        wrapper_path = create_browser_pointer_wrapper(temp_dir)
        raw_mp4 = os.path.join(temp_dir, "preview_raw.mp4")

        # Cleanup existing session if any
        run_cmd(["agent-browser", "--session", "record", "close"], optional=True)

        # Launch browser with desktop pointer emulation
        run_cmd([
            "agent-browser", "--session", "record",
            "--executable-path", wrapper_path,
            "open", "https://moondsp.koji-ishimoto.workers.dev/"
        ])
        run_cmd(["agent-browser", "--session", "record", "set", "viewport", "960", "720", "2"])
        time.sleep(1.0)

        # Cleanly replace score using text selection & delete
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

        # Position mouse over note area before starting record
        run_cmd(["agent-browser", "--session", "record", "mouse", "move", "300", "250"])
        time.sleep(0.4)

        # Start recording
        run_cmd(["agent-browser", "--session", "record", "record", "start", raw_mp4, "--cursor"])
        time.sleep(0.5)

        # Move smoothly to C3 note in the pitch grid
        run_cmd(["agent-browser", "--session", "record", "mouse", "move", "195", "487", "--human"])
        time.sleep(0.2)

        # Drag upwards to G3
        run_cmd(["agent-browser", "--session", "record", "mouse", "down", "left"])
        time.sleep(0.1)
        run_cmd(["agent-browser", "--session", "record", "mouse", "move", "195", "350", "--human"])
        time.sleep(0.1)
        run_cmd(["agent-browser", "--session", "record", "mouse", "up", "left"])
        time.sleep(0.9)

        # Verify score changed
        updated_text = run_cmd(["agent-browser", "--session", "record", "eval", "document.querySelector('.cm-content').innerText"])
        assert "G3 C3 Eb3 G3" in updated_text, f"Drag did not update score to G3: {updated_text}"

        # Move to Undo button
        run_cmd(["agent-browser", "--session", "record", "mouse", "move", "386", "26", "--human"])
        time.sleep(0.2)

        # Click Undo
        run_cmd(["agent-browser", "--session", "record", "click", "#undo"])
        time.sleep(1.1)

        # Verify score restored
        restored_text = run_cmd(["agent-browser", "--session", "record", "eval", "document.querySelector('.cm-content').innerText"])
        assert "C3 C3 Eb3 G3" in restored_text, f"Undo did not restore score to C3: {restored_text}"

        # Stop recording and close browser
        run_cmd(["agent-browser", "--session", "record", "record", "stop"])
        time.sleep(0.4)
        run_cmd(["agent-browser", "--session", "record", "close"], optional=True)

        print(f"Generating GIF from {raw_mp4}...")
        cmd_gif = [
            "ffmpeg", "-y", "-i", raw_mp4, "-vf",
            "fps=15,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer",
            GIF_OUT
        ]
        subprocess.run(cmd_gif, check=True)

        if os.path.isdir(AMP_ARTIFACTS_DIR):
            artifact_gif = os.path.join(AMP_ARTIFACTS_DIR, "preview.gif")
            shutil.copyfile(GIF_OUT, artifact_gif)

        print(f"Done! Saved preview GIF to {GIF_OUT} ({os.path.getsize(GIF_OUT)} bytes)")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
