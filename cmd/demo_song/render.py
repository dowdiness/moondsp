#!/usr/bin/env python3
"""Turn the demo's stdout (hex PCM lines and `#` diagnostics) into a WAV.

Usage: NEW_MOON_MOD=0 moon run cmd/demo_song | python3 cmd/demo_song/render.py out.wav
"""
import sys
import wave

out_path = sys.argv[1] if len(sys.argv) > 1 else "demo_song.wav"
frames = bytearray()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    if line.startswith("#"):
        print(line, file=sys.stderr)
        continue
    frames += bytes.fromhex(line)
with wave.open(out_path, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(48000)
    w.writeframes(bytes(frames))
print(f"wrote {out_path}: {len(frames) // 4} frames, {len(frames) / 4 / 48000:.2f} s", file=sys.stderr)
