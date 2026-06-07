# CLAP real-host coverage checklist

Date: 2026-06-07
Issue: #180

This file tracks real CLAP host/DAW tests for the native prototype. It does not
track MoonBit/native bridge-symbol rechecks or browser AudioWorklet ABI work.

A passing row proves only that the tested artifact worked in that host. It is
not a DAW-ready claim.

## Retest preflight

Use this checklist for each host row.

### 1. Identify the build

Record the source commit:

```bash
git rev-parse --short HEAD
```

### 2. Build a fresh artifact

Build the artifact for the target host OS:

```bash
scripts/build-clap-prototype.sh         # Linux ELF .clap
scripts/build-clap-prototype-windows.sh # Windows x86_64 PE .clap
```

### 3. Stop host and helper processes

Stop the host and any plugin helper or scanner that could lock or cache the
installed `.clap`.

Linux example:

```bash
pgrep -af '<host-or-plugin-helper-name>'
```

Windows example:

```powershell
Get-Process -Name '<HostProcessName>*' -ErrorAction SilentlyContinue |
  Select-Object Id,ProcessName
```

### 4. Install and verify the artifact

Copy the fresh build into the host's CLAP search path. Confirm that the copy
succeeded.

Then compare the build hash and installed hash. They must match before any host
behavior is interpreted.

Linux example:

```bash
sha256sum _build/native/release/clap/moondsp-synth.clap \
  /path/to/installed/moondsp-synth.clap
```

Windows example:

```powershell
Get-FileHash -Algorithm SHA256 _build/windows/release/clap/moondsp-synth.clap
Get-FileHash -Algorithm SHA256 C:\path\to\installed\moondsp-synth.clap
```

### 5. Run the host test

Clear or refresh the host plugin scan cache if the host requires it. Then record:

- scan/load result;
- activation or start-processing result;
- basic note/audio behavior: note-on makes sound, note-off releases sound, and
  transport stop does not leave stuck sound;
- host logs, screenshots, or the dated note that contains them.

### 6. File follow-up issues for failures

If a host-specific failure occurs, open a dedicated issue. Include the host
version, OS, artifact hashes, logs or screenshots, and repro steps. Link that
issue in the matrix.

## Historical baseline

The current baseline is Bitwig Studio 6.0.6 on Windows 11. This row predates
#180, so it does not count toward the two new host-coverage entries.

- Date: 2026-06-06
- Host/DAW: Bitwig Studio 6.0.6 (`Bitwig Studio.exe` 6.0.6.30345)
- OS: Windows 11 Pro 10.0.26200, x86_64
- Commit: PR #176 result (`d22e2c2`)
- Installed artifact SHA-256:
  `ebe976a0b3652111cbada071e2d525396d5b82dcc09793364ef8b0fe5b831e23`
- Result: scan/load pass, activation/process pass, audible synth output
- Note behavior: stuck-note behavior fixed after wildcard note-off, MIDI
  note-off, all-notes-off, transport-stop, and stop-processing cleanup
- Evidence: `docs/development/2026-06-06-clap-bitwig-windows-host-load.md`
- Follow-up: fixed in PR #176; no open host-specific follow-up from this row

## Coverage matrix

A row counts for #180 only when it uses a fresh build and verifies that the
installed artifact hash matches the build artifact hash.

| Date | Counts for #180? | Host / version | OS | Commit / artifact hash | Installed hash verified? | Scan / load | Activation / process | Note / audio behavior | Logs / screenshots / source | Failure follow-up |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-06-06 | No — historical baseline before #180 | Bitwig Studio 6.0.6 | Windows 11 Pro 10.0.26200, x86_64 | `d22e2c2`; full SHA-256 in historical baseline | Captured in dated note | Pass | Pass | Produced sound; stuck-note fix verified | `docs/development/2026-06-06-clap-bitwig-windows-host-load.md` | None open |
| TBD | Pending | Additional host/DAW #1 | TBD | Fresh commit and full SHA-256 | Required | Not tested | Not tested | Not tested | Add logs/screenshots or dated note path | Open issue if fail/blocker |
| TBD | Pending | Additional host/DAW #2 or meaningfully different host/OS combination | TBD | Fresh commit and full SHA-256 | Required | Not tested | Not tested | Not tested | Add logs/screenshots or dated note path | Open issue if fail/blocker |

## Production-status reminder

Do not describe the CLAP prototype as DAW-ready until bridge/toolchain guard,
broader real-host coverage, and audio-callback allocation gates are all green for
the relevant build.
