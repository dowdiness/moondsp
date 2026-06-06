#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/generate-clap-moonbit-header.sh [--check] <payload.c> <output.h>

Generate or verify clap_plugin/moondsp_clap_moonbit.h from the MoonBit native
payload C emitted by:

  moon build --target native --release clap_plugin

The generated header maps the C shim's stable mb_engine_* aliases to the
MoonBit native backend's current package-mangled clap_host symbols.
EOF
}

mode=write
case ${1:-} in
  --check)
    mode=check
    shift
    ;;
  -h|--help)
    usage
    exit 0
    ;;
esac

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

payload_c=$1
output_h=$2
repo_root=$(cd "$(dirname "$0")/.." && pwd)
python=${PYTHON:-python3}

if ! command -v "$python" >/dev/null 2>&1; then
  echo "Python interpreter not found: $python" >&2
  echo "Set PYTHON=/path/to/python3 or install python3." >&2
  exit 1
fi

if [[ ! -f "$payload_c" ]]; then
  echo "MoonBit payload C not found: $payload_c" >&2
  echo "Run: moon build --target native --release clap_plugin" >&2
  exit 1
fi

if [[ "$mode" == "check" && ! -f "$output_h" ]]; then
  echo "Header to verify not found: $output_h" >&2
  exit 1
fi

"$python" - "$mode" "$payload_c" "$output_h" "$repo_root" <<'PY'
import difflib
import re
import sys
from pathlib import Path

mode = sys.argv[1]
payload_path = Path(sys.argv[2]).resolve()
output_path = Path(sys.argv[3]).resolve()
repo_root = Path(sys.argv[4]).resolve()


class Param:
    def __init__(self, c_type, name):
        self.c_type = c_type
        self.name = name

    def render(self):
        return "%s %s" % (self.c_type, self.name)


class BridgeFunction:
    def __init__(self, alias, moonbit, return_type, params):
        self.alias = alias
        self.moonbit = moonbit
        self.return_type = return_type
        self.params = params

    @property
    def encoded_len(self):
        return len(self.moonbit)

    @property
    def param_types(self):
        return [param.c_type for param in self.params]

    @property
    def signature(self):
        return "%s(%s)" % (self.return_type, ", ".join(self.param_types))


def bridge(alias, moonbit, return_type, *params):
    return BridgeFunction(
        alias=alias,
        moonbit=moonbit,
        return_type=return_type,
        params=tuple(Param(c_type, name) for c_type, name in params),
    )


# Stable C aliases consumed by clap_plugin/moondsp_clap.c, paired with the
# MoonBit source names as they appear in generated native C symbols. MoonBit Bool
# crosses this primitive boundary as int32_t.
BRIDGE_FUNCTIONS = (
    bridge(
        "mb_engine_create",
        "engine__create",
        "int32_t",
        ("double", "sample_rate"),
        ("int32_t", "max_block_size"),
        ("int32_t", "max_voices"),
    ),
    bridge("mb_engine_destroy", "engine__destroy", "int32_t", ("int32_t", "handle")),
    bridge(
        "mb_engine_note_on",
        "engine__note__on",
        "int32_t",
        ("int32_t", "handle"),
        ("int32_t", "note_id"),
        ("int32_t", "key"),
        ("double", "velocity"),
    ),
    bridge(
        "mb_engine_note_off",
        "engine__note__off",
        "int32_t",
        ("int32_t", "handle"),
        ("int32_t", "note_id"),
        ("int32_t", "key"),
    ),
    bridge(
        "mb_engine_all_notes_off",
        "engine__all__notes__off",
        "int32_t",
        ("int32_t", "handle"),
    ),
    bridge(
        "mb_engine_set_param",
        "engine__set__param",
        "int32_t",
        ("int32_t", "handle"),
        ("int32_t", "param_id"),
        ("double", "value"),
    ),
    bridge(
        "mb_engine_process",
        "engine__process",
        "int32_t",
        ("int32_t", "handle"),
        ("int32_t", "frame_count"),
    ),
    bridge(
        "mb_engine_left_sample",
        "engine__left__sample",
        "double",
        ("int32_t", "handle"),
        ("int32_t", "index"),
    ),
    bridge(
        "mb_engine_right_sample",
        "engine__right__sample",
        "double",
        ("int32_t", "handle"),
        ("int32_t", "index"),
    ),
    bridge(
        "mb_engine_master_gain",
        "engine__master__gain",
        "double",
        ("int32_t", "handle"),
    ),
    bridge(
        "mb_engine_voice_gain",
        "engine__voice__gain",
        "double",
        ("int32_t", "handle"),
    ),
    bridge(
        "mb_engine_cutoff_hz",
        "engine__cutoff__hz",
        "double",
        ("int32_t", "handle"),
    ),
    bridge(
        "mb_engine_resonance",
        "engine__resonance",
        "double",
        ("int32_t", "handle"),
    ),
    bridge("mb_engine_pan", "engine__pan", "double", ("int32_t", "handle")),
)


def rel(path):
    try:
        return path.relative_to(repo_root).as_posix()
    except ValueError:
        return path.as_posix()


def normalize_params(params):
    params = params.strip()
    if not params or params == "void":
        return []
    return [" ".join(part.strip().split()) for part in params.split(",")]


def symbol_pattern(spec):
    # The package path segment is intentionally part of the match: the C shim is
    # allowed to depend only on clap_host's primitive bridge, not deeper engine,
    # graph, or voice implementation symbols.
    return re.compile(
        r"\b"
        + re.escape(spec.return_type)
        + r"\s+"
        + r"([A-Za-z_][A-Za-z0-9_$]*clap__host"
        + str(spec.encoded_len)
        + re.escape(spec.moonbit)
        + r")\s*\((.*?)\)\s*;",
        re.DOTALL,
    )


def find_symbol(payload, spec):
    matching_symbols = set()
    mismatched_signatures = []
    for match in symbol_pattern(spec).finditer(payload):
        symbol = match.group(1)
        actual_params = normalize_params(match.group(2))
        if actual_params == spec.param_types:
            matching_symbols.add(symbol)
        else:
            mismatched_signatures.append(
                "%s %s(%s)" % (spec.return_type, symbol, ", ".join(actual_params))
            )
    if not matching_symbols:
        detail = ""
        if mismatched_signatures:
            detail = (
                "\nFound candidate(s) with unexpected signatures:\n  "
                + "\n  ".join(mismatched_signatures)
            )
        raise SystemExit(
            "Could not find MoonBit clap_host bridge symbol for %s "
            "with signature %s in %s.%s"
            % (spec.moonbit, spec.signature, rel(payload_path), detail)
        )
    if len(matching_symbols) != 1:
        raise SystemExit(
            "Expected one MoonBit clap_host symbol for %s, found %d: %s"
            % (spec.moonbit, len(matching_symbols), ", ".join(sorted(matching_symbols)))
        )
    return next(iter(matching_symbols))


def format_prototype(return_type, symbol, params):
    rendered_params = [param.render() for param in params]
    one_line = "%s %s(%s);" % (return_type, symbol, ", ".join(rendered_params))
    if len(one_line) <= 88:
        return one_line
    lines = ["%s %s(" % (return_type, symbol)]
    for index, param in enumerate(rendered_params):
        suffix = "," if index + 1 < len(rendered_params) else ""
        lines.append("    %s%s" % (param, suffix))
    lines.append(");")
    return "\n".join(lines)


def generate_header(payload):
    resolved = [(spec, find_symbol(payload, spec)) for spec in BRIDGE_FUNCTIONS]

    source_label = rel(payload_path)
    output_label = rel(output_path)
    lines = [
        "#ifndef MOONDSP_CLAP_MOONBIT_H",
        "#define MOONDSP_CLAP_MOONBIT_H",
        "",
        "/*",
        " * Generated by scripts/generate-clap-moonbit-header.sh.",
        " * Source: %s" % source_label,
        " * Output: %s" % output_label,
        " *",
        " * Do not edit by hand. Rebuild the native payload, then run:",
        " *   scripts/generate-clap-moonbit-header.sh \\",
        " *     _build/native/release/build/clap_plugin/clap_plugin.c \\",
        " *     clap_plugin/moondsp_clap_moonbit.h",
        " */",
        "",
        "#include <stdint.h>",
        "",
        "#ifdef __cplusplus",
        'extern "C" {',
        "#endif",
        "",
        "// MoonBit runtime entrypoints emitted/linked by the native backend.",
        "void moonbit_runtime_init(int argc, char **argv);",
        "void moonbit_init(void);",
        "",
        "// Primitive bridge symbols discovered in the generated MoonBit payload.",
        "// The CLAP shim calls the stable mb_engine_* aliases below; the right-hand",
        "// side remains generated because MoonBit native currently emits package-",
        "// mangled C names for MoonBit functions.",
        "// MoonBit Bool return values cross this primitive C boundary as int32_t.",
    ]
    for spec, symbol in resolved:
        lines.append(format_prototype(spec.return_type, symbol, spec.params))
    lines.append("")
    for spec, symbol in resolved:
        lines.append("#define %s %s" % (spec.alias, symbol))
    lines.extend(
        [
            "",
            "#ifdef __cplusplus",
            "}",
            "#endif",
            "",
            "#endif",
            "",
        ]
    )
    return "\n".join(lines)


payload = payload_path.read_text(encoding="utf-8")
generated = generate_header(payload)

if mode == "check":
    existing = output_path.read_text(encoding="utf-8")
    if existing != generated:
        diff = difflib.unified_diff(
            existing.splitlines(),
            generated.splitlines(),
            fromfile=rel(output_path),
            tofile="%s (generated from %s)" % (rel(output_path), rel(payload_path)),
            lineterm="",
        )
        command = "scripts/generate-clap-moonbit-header.sh %s %s" % (
            rel(payload_path),
            rel(output_path),
        )
        sys.stderr.write(
            "MoonBit CLAP bridge header is stale. Regenerate it with:\n"
            "  %s\n\n" % command
        )
        sys.stderr.write("\n".join(diff))
        sys.stderr.write("\n")
        raise SystemExit(1)
    print("Verified %s against %s" % (rel(output_path), rel(payload_path)))
elif mode == "write":
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(generated, encoding="utf-8")
    print("Generated %s from %s" % (rel(output_path), rel(payload_path)))
else:
    raise SystemExit("unknown mode: %s" % mode)
PY
