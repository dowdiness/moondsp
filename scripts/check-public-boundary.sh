#!/usr/bin/env bash
#
# Audits public .mbti files for Array[DspNode] entries. Asserts only
# documented boundary exceptions and allowed authoring APIs appear.
# New entries fail the script.
#
# See docs/decisions/0010-compiled-template-runtime-boundary.md for
# the complete carve-out list.

set -euo pipefail

# Regenerate .mbti files
moon info >/dev/null

# Allowed patterns (extended regex, matched against the full line).
# The optional `@graph\.` prefix handles cross-package references
# (root pkg.generated.mbti uses `Array[@graph.DspNode]`).
# Update this list when ADR-0010 carve-outs change.
DSPN='Array\[(@graph\.)?DspNode\]'

ALLOWED_PATTERNS=(
  # Boundary exceptions
  "^pub fn\[T : .*\] replay\(${DSPN}\)"
  "^pub fn CompiledDspTopologyController::from_nodes\(${DSPN}"
  "^pub fn CompiledStereoDspTopologyController::from_nodes\(${DSPN}"
  # Allowed authoring APIs
  "^pub fn CompiledTemplate::analyze\(${DSPN}\)"
  "^pub fn GraphBuilder::nodes\(Self\) -> ${DSPN}"
  "^pub fn GraphTemplateDoc::nodes\(Self\) -> ${DSPN}"
  "^pub fn GraphTemplateDoc::from_nodes\("
  "^pub fn GraphTemplateDoc::insert_chain\("
  "^pub fn GraphIndexMap::insert_chain\("
  "^pub fn GraphTopologyEdit::insert_chain\("
  "^  InsertChain\(Int, GraphTopologyInputSlot, ${DSPN}\)"
)

FILES=(
  "graph/pkg.generated.mbti"
  "voice/pkg.generated.mbti"
  "pkg.generated.mbti"
)

violations=()
for file in "${FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    continue
  fi
  while IFS= read -r line; do
    # Skip lines without Array[DspNode] reference
    if ! echo "$line" | grep -qE "${DSPN}"; then
      continue
    fi
    matched=0
    for pat in "${ALLOWED_PATTERNS[@]}"; do
      if echo "$line" | grep -qE "$pat"; then
        matched=1
        break
      fi
    done
    if [[ $matched -eq 0 ]]; then
      violations+=("$file: $line")
    fi
  done < "$file"
done

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "ERROR: Public Array[DspNode] entries not in ADR-0010 carve-out list:"
  printf '  %s\n' "${violations[@]}"
  echo ""
  echo "Either:"
  echo "  1. Migrate the entry to CompiledTemplate (preferred), or"
  echo "  2. Update ALLOWED_PATTERNS in scripts/check-public-boundary.sh"
  echo "     AND add the new exception to ADR-0010 with rationale."
  exit 1
fi

echo "OK: all public Array[DspNode] entries match ADR-0010 carve-outs."
