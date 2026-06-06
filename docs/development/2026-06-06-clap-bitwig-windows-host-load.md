# CLAP host load note: Bitwig Studio on Windows

Date: 2026-06-06

## Environment

- Host/DAW: Bitwig Studio 6.0.6 (`Bitwig Studio.exe` file version 6.0.6.30345)
- OS: Microsoft Windows 11 Pro 10.0.26200, x86_64
- Plugin path: `C:\Users\antisatori\AppData\Local\Programs\Common\CLAP\moondsp-synth.clap`
- Build path: `_build/windows/release/clap/moondsp-synth.clap`
- Build artifact kind: Windows x86_64 PE DLL exporting `clap_entry`
- Installed artifact SHA-256 at test time: `ebe976a0b3652111cbada071e2d525396d5b82dcc09793364ef8b0fe5b831e23`

## Result

Bitwig Studio recognized and loaded the Windows CLAP prototype. The synth
produced sound in Bitwig.

Initial host testing exposed stuck notes: sound continued after releasing or
stopping playback. The fix in this session adds CLAP wildcard note-off/choke
handling, raw MIDI note-off handling, MIDI all-notes-off/all-sound-off handling,
transport-stop cleanup, and `stop_processing` cleanup. After copying the rebuilt
Windows `.clap` over the installed plugin, Bitwig testing confirmed that sound
now stops correctly.

## Remaining gate

This is real host-load evidence for the Windows prototype, not a DAW-readiness
claim. The audio-thread allocation audit remains open before production use.
