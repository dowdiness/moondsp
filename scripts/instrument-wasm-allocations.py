"""Count executed Wasm GC constructors in folded WAT, grouped by function.

Usage: python3 scripts/instrument-wasm-allocations.py input.wat output.wat
First disassemble release Wasm with moon-wasm-opt --all-features -S.
Moon compiler WAT mixes stack operands with folded syntax; do not use it directly.
Assemble output with moon-wasm-opt --all-features (without optimization).
The pinned Binaryen emits exact reference types; Node execution requires
--experimental-wasm-custom-descriptors for this audit artifact only.
Counters measure instructions, not heap bytes; never time the instrumented build.
"""
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
assert source.lstrip().startswith('(module'), 'expected normalized Binaryen WAT'
# Tokenize strings/comments as units so parentheses inside them are ignored.
tokens = re.finditer(r'"(?:\\.|[^"\\])*"|;;[^\n]*|\(;.*?;\)|[()]|[^\s()]+', source, re.S)
stack = []
pairs = {}
for token in tokens:
    if token[0] == '(':
        stack.append(token.start())
    elif token[0] == ')':
        pairs[stack.pop()] = token.end()
assert not stack

edits = []
globals_ = []
for number, function in enumerate(re.finditer(r'\(func (\$[^\s()]+)', source)):
    start, end = function.start(), pairs[function.start()]
    sites = list(re.finditer(r'\((?:struct\.new(?:_default)?|array\.new(?:_default|_fixed|_data|_elem)?) (\$[^\s()]+)', source[start:end]))
    if not sites:
        continue
    counter = f'$audit{number}'
    globals_.append(f'(global {counter} (export "alloc:{function[1]}") (mut i64) (i64.const 0))')
    for site in sites:
        position = start + site.start()
        prefix = f'(block (result (ref (exact {site[1]}))) (global.set {counter} (i64.add (global.get {counter}) (i64.const 1))) '
        edits.append((position, prefix))
        edits.append((pairs[position], ')'))

module = re.search(r'\(module(?:\s+\$[^\s()]+)?', source)
edits.append((module.end(), '\n' + '\n'.join(globals_) + '\n'))
for position, text in sorted(edits, reverse=True):
    source = source[:position] + text + source[position:]
Path(sys.argv[2]).write_text(source)
print(f'Instrumented {len(globals_)} functions, {(len(edits) - 1) // 2} construction sites')
