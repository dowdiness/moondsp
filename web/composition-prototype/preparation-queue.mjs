// Thin Worker shell: at most one executing and one latest queued preparation.
// Cancelling retires a result; synchronous compilation can finish and warm cache.
export function preparationQueue(worker) {
  let flight=null, queued=null, desired=0, closed=false;
  const send=job=>{flight=job;worker.postMessage({doc:job.doc,revision:job.revision,timing:{submittedMs:job.submittedMs,dispatchedMs:Date.now()}});};
  const retire=job=>job?.resolve({kind:'retired',revision:job.revision});
  worker.onmessage=({data})=>{
    if(closed || !flight || data.revision!==flight.revision)return;
    const job=flight;flight=null;
    if(job.revision===desired) {
      if(data.kind==='prepared' && data.bundle?.revision===job.revision) job.resolve({...data,timing:{...data.timing,mainReceivedMs:Date.now()}});
      else job.reject(Error(data.error??'invalid preparation response'));
    } else retire(job);
    if(queued){const next=queued;queued=null;send(next);}
  };
  return {
    submit(doc,revision){
      if(closed)return Promise.reject(Error('停止しました'));
      desired=revision;retire(flight);retire(queued);
      return new Promise((resolve,reject)=>{const job={doc,revision,resolve,reject,submittedMs:Date.now()};if(flight)queued=job;else send(job);});
    },
    cancel(){desired=0;retire(flight);retire(queued);queued=null;},
    close(){closed=true;desired=0;retire(flight);retire(queued);queued=null;}
  };
}
