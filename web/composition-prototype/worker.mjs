import * as compiler from '../../_build/js/release/build/cmd/composition_prepare/composition_prepare.js';
import {prepareDefinitions} from './prepare.mjs';
let cache = Object.freeze([]);
self.onmessage = ({data}) => {
  const receivedMs=Date.now(),start=performance.now();let queryMs=0;
  const timedCompiler={...compiler,prepare:source=>{const begin=performance.now();try{return compiler.prepare(source);}finally{queryMs+=performance.now()-begin;}}};
  try {
    const result=prepareDefinitions(timedCompiler,data.doc,data.revision,cache);cache=result.cache;
    self.postMessage({kind:'prepared',revision:data.revision,bundle:result.bundle,cacheStats:result.stats,prepareMs:performance.now()-start,timing:{...data.timing,workerReceivedMs:receivedMs,workerSentMs:Date.now(),queryMs}});
  } catch(error) {self.postMessage({kind:'error',revision:data.revision,error:String(error)});}
};
