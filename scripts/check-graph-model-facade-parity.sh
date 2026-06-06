#!/usr/bin/env bash
#
# Ensures the public graph facade stays in lockstep with graph/internal/model
# for the deliberately duplicated authoring model surface.
#
# Policy for issue #162:
# - Keep DspNode and GraphControl as graph-owned facade wrappers over the
#   internal model instead of re-exporting raw internal types. This preserves a
#   stable public origin path for the authoring exchange type while keeping
#   graph/internal/model hidden as implementation detail.
# - Keep DspNodeKind, GraphParamSlot, GraphControlKind, and Node* traits as
#   facade-visible duplicates that mirror model semantics. The conversion code
#   and wbtests cover behavior; this script covers public surface parity.
# - Internal-only model helpers such as node_with_value0/remap_node_inputs are
#   intentionally not part of the facade parity set.
#
# The check parses generated .mbti files rather than source so it validates the
# public contract reviewers actually see after `moon info`.

set -euo pipefail

facade="graph/pkg.generated.mbti"
model="graph/internal/model/pkg.generated.mbti"

moon info --quiet

if [[ ! -f "$facade" || ! -f "$model" ]]; then
  echo "ERROR: generated graph interfaces missing after moon info" >&2
  exit 1
fi

violations=()
diffs=()

extract_enum_variants() {
  local file=$1
  local type=$2
  awk -v type="$type" '
    $0 ~ "^pub(\\([^)]*\\))? enum " type " \\{" { in_enum = 1; next }
    in_enum && $0 ~ /^}/ { exit }
    in_enum {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/\(.*/, "", line)
      sub(/[[:space:]].*/, "", line)
      if (line != "") print line
    }
  ' "$file"
}

extract_type_methods() {
  local file=$1
  local type=$2
  awk -v type="$type" '$0 ~ "^pub fn " type "::" { print $0 }' "$file"
}

extract_value_fn() {
  local file=$1
  local name=$2
  awk -v name="$name" '$0 ~ "^pub fn(\\[[^]]+\\])? " name "\\(" { print $0 }' "$file"
}

extract_trait_block() {
  local file=$1
  local trait=$2
  awk -v trait="$trait" '
    function normalize(line) {
      sub(/^pub\(open\) trait/, "pub trait", line)
      return line
    }
    $0 ~ "^pub(\\([^)]*\\))? trait " trait "( |:)" {
      in_trait = 1
      print normalize($0)
      next
    }
    in_trait {
      print $0
      if ($0 ~ /^}/) exit
    }
  ' "$file"
}

compare_blocks() {
  local label=$1
  local left=$2
  local right=$3

  if [[ -z "$left" || -z "$right" ]]; then
    violations+=("$label could not be parsed from generated interfaces")
    return 0
  fi

  local left_file right_file diff_file
  left_file=$(mktemp)
  right_file=$(mktemp)
  diff_file=$(mktemp)
  printf '%s\n' "$left" >"$left_file"
  printf '%s\n' "$right" >"$right_file"

  if ! diff -u --label "graph facade $label" --label "internal model $label" "$left_file" "$right_file" >"$diff_file"; then
    violations+=("$label drifted between graph facade and internal model")
    diffs+=("$(cat "$diff_file")")
  fi

  rm -f "$left_file" "$right_file" "$diff_file"
}

for enum_name in DspNodeKind GraphParamSlot GraphControlKind; do
  compare_blocks \
    "$enum_name variants" \
    "$(extract_enum_variants "$facade" "$enum_name")" \
    "$(extract_enum_variants "$model" "$enum_name")"
done

for type_name in DspNode GraphControl; do
  compare_blocks \
    "$type_name public methods" \
    "$(extract_type_methods "$facade" "$type_name")" \
    "$(extract_type_methods "$model" "$type_name")"
done

compare_blocks \
  "node_accepts_slot facade function" \
  "$(extract_value_fn "$facade" node_accepts_slot)" \
  "$(extract_value_fn "$model" node_accepts_slot)"

for trait_name in NodeSpanning NodeFoldable NodeStateful NodeEditable; do
  compare_blocks \
    "$trait_name trait shape" \
    "$(extract_trait_block "$facade" "$trait_name")" \
    "$(extract_trait_block "$model" "$trait_name")"
done

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "ERROR: graph facade/internal model parity violations:" >&2
  printf '  %s\n' "${violations[@]}" >&2
  if [[ ${#diffs[@]} -gt 0 ]]; then
    echo "" >&2
    printf '%s\n\n' "${diffs[@]}" >&2
  fi
  echo "Either update graph/ facade wrappers and parity tests, or document an intentional policy change." >&2
  exit 1
fi

echo "OK: graph facade/internal model parity matches."
