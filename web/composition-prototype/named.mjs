export function beats(length){
 if(typeof length==='number'){if(Number.isInteger(length)&&length>0&&length<=64)return length*4;}
 else if(length&&typeof length==='object'&&Object.keys(length).length===1){
  if(Number.isInteger(length.bars)&&length.bars>0&&length.bars<=64)return length.bars*4;
  if(Number.isInteger(length.beats)&&length.beats>0&&length.beats<=256)return length.beats;
 }
 throw new Error('duration requires positive bars or beats (4/4)');
}
// This authoring adapter lowers names to existing mini syntax; it does not eval JS.
export function lowerNamedSong(doc){
 if(doc?.meter!=='4/4')throw new Error('4/4 required');
 const defs=doc.patterns,scenes=doc.scenes,rows=doc.song;
 if(!defs||!scenes||!Array.isArray(rows)||!rows.length||rows.length>32)throw new Error('invalid song');
 const names=Object.keys(scenes);
 if(!names.length||names.length>32||Object.keys(defs).length>64||[...names,...Object.keys(defs)].some(n=>!/^\w{1,32}$/.test(n)))throw new Error('invalid names or capacity');
 const durations=new Map();
 for(const row of rows){if(!Array.isArray(row)||row.length!==2||!Object.hasOwn(scenes,row[0]))throw new Error('unknown scene');const n=beats(row[1]);if(durations.has(row[0])&&durations.get(row[0])!==n)throw new Error('same section needs the same duration');durations.set(row[0],n);}
 const sections=[...durations].map(([name,n])=>{
  const refs=scenes[name];if(!Array.isArray(refs)||!refs.length||refs.length>16)throw new Error('invalid layers');
  const expressions=refs.map(ref=>{if(!Object.hasOwn(defs,ref)||typeof defs[ref]!=='string'||defs[ref].length>512)throw new Error('unknown or invalid pattern');return defs[ref];});
  return `section(${JSON.stringify(name)}, ${n}, stack(\n    ${expressions.join(',\n    ')}\n  ))`;
 });
 return `song(\n  ${sections.concat(rows.map(([name],i)=>`part("r${i+1}", ${JSON.stringify(name)})`)).join(',\n  ')}\n)\n`;
}
