import {lowerNamedSong, beats} from './named.mjs';
export const RATE = 48000, BEAT = 24000, Q = 128, BAR = 96000;
export function compileRows(compiler, source) {
  if (!compiler.prepare(source)) throw Error(compiler.error_text());
  const rows = [];
  for (let i = 0; i < compiler.length(); i += 8) {
    const [bn, bd, en, ed, note, sound, gain, pan] = Array.from({length: 8}, (_, j) => compiler.value(i + j));
    const at = bn * BEAT / bd, end = en * BEAT / ed;
    const hz = note < 0 ? 0 : 440 * 2 ** ((note - 69) / 12), route = [36,38,42,39,46].indexOf(sound);
    if (route >= 0) rows.push({at, end, route, hz, gain, pan});
    if (note >= 0) rows.push({at, end, route: 5, hz, gain, pan});
    if (route < 0 && note < 0) throw Error('unsupported sound');
  }
  return rows.sort((a,b) => a.at - b.at);
}
export function prepare(compiler, doc, revision) {
  const source = lowerNamedSong(doc);
  const score = compileRows(compiler, source), scenes = {};
  let offset = 0;
  const arrangement = doc.song.map(([name, duration]) => {
    const length = beats(duration) * BEAT, row = {name, from: offset, length}; offset += length;
    if (!Object.hasOwn(scenes, name)) scenes[name] = {length, rows: compileRows(compiler, lowerNamedSong({...doc, song: [[name, duration]]}))};
    return row;
  });
  return {revision, length: offset, score, scenes, arrangement};
}

// Pure cache transition: retain only the current document's scene sources.
// The source includes the scene's duration and expressions; the prefix fixes
// parser-query coordinates and synthesis lowering assumptions for this process.
export function prepareIncremental(compiler, doc, revision, previous = []) {
  lowerNamedSong(doc); // validate the complete document before using any cache
  const next = [], scenes = {}, arrangement = [];
  let offset = 0, compiled = 0, reused = 0;
  for (const [name, duration] of doc.song) {
    const length = beats(duration) * BEAT;
    arrangement.push({name, from: offset, length}); offset += length;
    if (Object.hasOwn(scenes, name)) continue;
    const source = lowerNamedSong({...doc, song: [[name, duration]]});
    const key = 'composition-v1:48000:24000:128:' + source;
    const found = previous.find(entry => entry.key === key);
    const rows = found?.rows ?? Object.freeze(compileRows(compiler, source).map(e => Object.freeze(e)));
    if (found) reused++; else compiled++;
    next.push(Object.freeze({key, rows}));
    Object.defineProperty(scenes, name, {value: {length, rows}, enumerable: true});
  }
  const score = arrangement.flatMap(r => scenes[r.name].rows.map(e => ({...e, at: e.at+r.from, end: e.end+r.from}))).sort((a,b)=>a.at-b.at);
  return {bundle: {revision,length:offset,score,scenes,arrangement}, cache:Object.freeze(next), stats:{compiled,reused}};
}

// Local definition queries are reusable only under identical time coordinates.
// Layer order is preserved before the stable onset sort (including duplicates).
export function prepareDefinitions(compiler, doc, revision, previous = []) {
  lowerNamedSong(doc);
  const next = [], scenes = {}, arrangement = [];
  let offset=0, compiled=0, reused=0, shared=0;
  for(const [name,duration] of doc.song){
    const length=beats(duration)*BEAT;
    arrangement.push({name,from:offset,length});offset+=length;
    if(Object.hasOwn(scenes,name))continue;
    const layers=doc.scenes[name].map(ref=>{
      const key=JSON.stringify(['definition-v1',48000,24000,128,0,length,ref,doc.patterns[ref]]);
      const current=next.find(entry=>entry.key===key);if(current){shared++;return current.rows;}
      const found=previous.find(entry=>entry.key===key);
      const source=lowerNamedSong({...doc,scenes:{material:[ref]},song:[['material',duration]]});
      const rows=found?.rows??Object.freeze(compileRows(compiler,source).map(e=>Object.freeze(e)));
      if(found)reused++;else compiled++;
      next.push(Object.freeze({key,rows}));return rows;
    });
    Object.defineProperty(scenes,name,{value:{length,rows:layers.flat().sort((a,b)=>a.at-b.at)},enumerable:true});
  }
  const score=arrangement.flatMap(r=>scenes[r.name].rows.map(e=>({...e,at:e.at+r.from,end:e.end+r.from}))).sort((a,b)=>a.at-b.at);
  return {bundle:{revision,length:offset,score,scenes,arrangement},cache:Object.freeze(next),stats:{compiled,reused,shared,unit:'definition-window'}};
}
