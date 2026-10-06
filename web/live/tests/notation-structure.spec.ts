import { expect, test } from "@playwright/test";
import {
  boundaryInfo,
  duplicateRange,
  extendSourceRange,
  leafNodes,
  layoutNodes,
  moveBoundary,
  moveRange,
  projectNotation,
  relocateNode,
  relocationTarget,
  repeatNode,
  sourceRangeNodes,
  splitNode,
  transposeRange,
  weightNode,
} from "../src/notation-structure";
function apply(content: string, changes: readonly { from: number; to: number; insert: string }[]): string {
  return [...changes].sort((a, b) => b.from - a.from).reduce(
    (source, change) => source.slice(0, change.from) + change.insert + source.slice(change.to), content,
  );
}

test("nested split and postfix edits preserve the original modifier suffix", () => {
  const content = "[C4 D4]*2@3  E4";
  const projection = projectNotation("note", content);
  expect(projection.error).toBeNull();
  const atom = leafNodes(projection).find(index => projection.nodes[index].value === "C4");
  expect(atom).toBeDefined();
  expect(apply(content, splitNode(content, projection, atom!))).toBe("[[C4 C4] D4]*2@3  E4");
  const repeat = apply(content, repeatNode(content, projection, atom!, 4));
  expect(repeat).toContain("C4*4");
  expect(repeat).toContain("@3  E4");
});

test("repeated source remains one editable atom with linked projected events", () => {
  const content = "[C4 D4]*3";
  const projection = projectNotation("note", content);
  expect(projection.error).toBeNull();
  const c = leafNodes(projection).find(index => projection.nodes[index].value === "C4");
  expect(c).toBeDefined();
  expect(projection.events.filter(event => event.node === c).length).toBeGreaterThan(1);
  expect(repeatNode(content, projection, c!, 1)).toEqual([]);
});

test("adjacent boundary edits preserve outer sibling boundaries and expose the shared split", () => {
  const content = "C4 D4 E4";
  const projection = projectNotation("note", content);
  expect(projection.error).toBeNull();
  const atoms = leafNodes(projection);
  const before = layoutNodes(projection).filter(item => atoms.includes(item.node));
  expect(boundaryInfo(projection, atoms[0])?.right).toBe(atoms[1]);
  const edited = apply(content, moveBoundary(content, projection, atoms[0], 0.75));
  const next = projectNotation("note", edited);
  expect(next.error).toBeNull();
  const afterAtoms = leafNodes(next);
  const after = layoutNodes(next).filter(item => afterAtoms.includes(item.node));
  expect(boundaryInfo(next, afterAtoms[0])?.ratio).toBeCloseTo(0.75, 2);
  expect(after[0].start).toBe(before[0].start);
  expect(after[2].start).toBe(before[2].start);
  expect(after.at(-1)?.end).toBe(before.at(-1)?.end);
});

test("saturated sibling weights are reduced before finding a representable boundary", () => {
  const content = "C4@16 D4@16 E4@16";
  const projection = projectNotation("note", content);
  expect(projection.error).toBeNull();
  const atoms = leafNodes(projection);
  const before = layoutNodes(projection).filter(item => atoms.includes(item.node));
  const edited = apply(content, moveBoundary(content, projection, atoms[0], 0.75));
  expect(edited).toBe("C4@3 D4@1 E4@2");
  const next = projectNotation("note", edited);
  const afterAtoms = leafNodes(next);
  const after = layoutNodes(next).filter(item => afterAtoms.includes(item.node));
  expect(boundaryInfo(next, afterAtoms[0])?.ratio).toBeCloseTo(0.75, 2);
  expect(after[2].start).toBe(before[2].start);
});

test("ambiguous modifiers and unusable boundary targets fail cleanly", () => {
  const content = "C4@2@3 D4";
  const projection = projectNotation("note", content);
  expect(projection.error).toBeNull();
  const atom = leafNodes(projection)[0];
  expect(() => weightNode(content, projection, atom, 4)).toThrow(/repeated weight/i);
  expect(boundaryInfo(projection, atom)).toBeNull();
  expect(() => moveBoundary(content, projection, atom, 0)).toThrow();
  expect(() => moveBoundary(content, projection, atom, 1)).toThrow();
  const slow = "C4/2";
  const slowProjection = projectNotation("note", slow);
  expect(slowProjection.error).toBeNull();
  expect(() => repeatNode(slow, slowProjection, leafNodes(slowProjection)[0], 2)).toThrow(/combined/i);
});
test("relocation rotates occupied and rest slots in either direction without changing separators", () => {
  const rightContent = " C4@2  ~\tD4*3 ";
  const rightProjection = projectNotation("note", rightContent);
  const rightAtoms = leafNodes(rightProjection);
  const c = rightAtoms.find(index => rightProjection.nodes[index].value === "C4")!;
  const d = rightAtoms.find(index => rightProjection.nodes[index].value === "D4")!;
  expect(relocationTarget(rightProjection, c, d)).toBe(d);
  const rightEdit = relocateNode(rightContent, rightProjection, c, d);
  const rightResult = apply(rightContent, rightEdit.changes);
  expect(rightResult).toBe(" ~  D4*3\tC4@2 ");
  expect(rightResult.slice(rightEdit.selection.from, rightEdit.selection.to)).toBe("C4");

  const leftContent = "C4*3  ~\tD4@2";
  const leftProjection = projectNotation("note", leftContent);
  const leftAtoms = leafNodes(leftProjection);
  const leftC = leftAtoms.find(index => leftProjection.nodes[index].value === "C4")!;
  const leftD = leftAtoms.find(index => leftProjection.nodes[index].value === "D4")!;
  const leftEdit = relocateNode(leftContent, leftProjection, leftD, leftC);
  const leftResult = apply(leftContent, leftEdit.changes);
  expect(leftResult).toBe("D4@2  C4*3\t~");
  expect(leftResult.slice(leftEdit.selection.from, leftEdit.selection.to)).toBe("D4");
});

test("relocation selection follows the moved token across changed slot lengths and pitch", () => {
  const content = "C4@2 D#5*2 E4";
  const projection = projectNotation("note", content);
  const atoms = leafNodes(projection);
  const source = atoms.find(index => projection.nodes[index].value === "C4")!;
  const target = atoms.find(index => projection.nodes[index].value === "E4")!;
  const edit = relocateNode(content, projection, source, target, "D#5");
  const result = apply(content, edit.changes);
  expect(result).toBe("D#5*2 E4 D#5@2");
  expect(result.slice(edit.selection.from, edit.selection.to)).toBe("D#5");
  expect(edit.selection.from).toBe(result.lastIndexOf("D#5"));
});

test("nested repeated scopes remain intact and relocation rejects parent crossings", () => {
  const content = "[C4@2 D4*3]*2 E4";
  const projection = projectNotation("note", content);
  const atoms = leafNodes(projection);
  const c = atoms.find(index => projection.nodes[index].value === "C4")!;
  const d = atoms.find(index => projection.nodes[index].value === "D4")!;
  const e = atoms.find(index => projection.nodes[index].value === "E4")!;
  expect(relocationTarget(projection, c, d)).toBe(d);
  expect(relocationTarget(projection, c, e)).toBeNull();
  expect(apply(content, relocateNode(content, projection, c, d).changes)).toBe("[D4*3 C4@2]*2 E4");
  expect(() => relocateNode(content, projection, c, e)).toThrow(/same sequence/i);
  const beforeGroup = relocateNode(content, projection, e, c);
  const beforeGroupSource = apply(content, beforeGroup.changes);
  expect(beforeGroupSource).toBe("E4 [C4@2 D4*3]*2");
  expect(beforeGroupSource.slice(beforeGroup.selection.from, beforeGroup.selection.to)).toBe("E4");
});

test("source intervals resolve complete contiguous siblings and reject partial group crossings", () => {
  const content = "[C4 D4]*2  E4";
  const projection = projectNotation("note", content);
  const group = projection.nodes.findIndex(node => node.kind === "group");
  const e = leafNodes(projection).find(index => projection.nodes[index].value === "E4")!;
  expect(sourceRangeNodes(projection, 0, 7)).toEqual([group]);
  expect(sourceRangeNodes(projection, 2, 4)).toEqual([]);
  expect(extendSourceRange(projection, group, e)).toEqual([group, e]);
  const suffixed = projectNotation("note", "C4@2 E4");
  const c = leafNodes(suffixed).find(index => suffixed.nodes[index].value === "C4")!;
  expect(sourceRangeNodes(suffixed, 0, 2)).toEqual([c]);
  const inner = leafNodes(projection).filter(index => projection.nodes[index].value !== "E4");
  expect(sourceRangeNodes(projection, 1, 6)).toEqual(inner);
  const edited = transposeRange(content, projection, inner, 1);
  expect(apply(content, edited.changes)).toBe("[C#4 D#4]*2  E4");
  const singleContent = "[C4]*2";
  const single = projectNotation("note", singleContent);
  const innerNote = leafNodes(single)[0];
  expect(sourceRangeNodes(single, 1, 3)).toEqual([innerNote]);
  expect(apply(singleContent, duplicateRange(singleContent, single, [innerNote]).changes)).toBe("[C4 C4]*2");
});

test("range movement rotates separators and selection tracks a repeated block", () => {
  const content = "C4@2  E4\t~ D4";
  const projection = projectNotation("note", content);
  const nodes = leafNodes(projection).slice(0, 2);
  const edit = moveRange(content, projection, nodes, 1);
  const result = apply(content, edit.changes);
  expect(result).toBe("~  C4@2\tE4 D4");
  expect(result.slice(edit.selection.from, edit.selection.to)).toBe("C4@2\tE4");
  const left = moveRange(result, projectNotation("note", result), [leafNodes(projectNotation("note", result))[1]], -1);
  expect(apply(result, left.changes)).toBe("C4@2  ~\tE4 D4");
});

test("range transpose is atomic at MIDI limits and duplicate keeps independent repeated groups", () => {
  const content = "[C4@2 D4*3]*2  E4";
  const projection = projectNotation("note", content);
  const group = projection.nodes.findIndex(node => node.kind === "group");
  const duplicate = duplicateRange(content, projection, [group]);
  const copied = apply(content, duplicate.changes);
  expect(copied).toBe("[C4@2 D4*3]*2 [C4@2 D4*3]*2  E4");
  expect(copied.slice(duplicate.selection.from, duplicate.selection.to)).toBe("[C4@2 D4*3]*2");
  const copyProjection = projectNotation("note", copied);
  const groups = copyProjection.nodes.flatMap((node, index) => node.kind === "group" ? [index] : []);
  const transposed = transposeRange(copied, copyProjection, [groups[1]], 1);
  expect(apply(copied, transposed.changes)).toContain("[C#4@2 D#4*3]*2");
  const high = "G9";
  const highProjection = projectNotation("note", high);
  expect(() => transposeRange(high, highProjection, [leafNodes(highProjection)[0]], 1)).toThrow();
});
