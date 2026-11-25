'use strict';
(()=>{
const bridge=window.OrigenSync, pending=new Map();let serial=0, remote=null, syncing=false, auto=false, latest=nativeCompletion, pauseRequested=false;
window.origenRemoteCall=call;
window.origenSyncRepo=()=>bridge?.repository()||'';
window.origenSyncReply=(id,json)=>{const cb=pending.get(id);if(cb){pending.delete(id);cb(JSON.parse(json));}};
function call(op,a='',b=''){return new Promise((resolve,reject)=>{if(!bridge)return reject(Error('Disponible solo en Android.'));const id=String(++serial);pending.set(id,r=>r.ok?resolve(r):reject(Error(r.error)));bridge.request(id,op,a,b);setTimeout(()=>{if(pending.delete(id))reject(Error('Tiempo de espera agotado.'));},65000);});}
window.origenNativeCompleted=completion=>{if(completion)latest=completion;preview();};
window.origenPauseForUpgrade=()=>{pauseRequested=true;setAuto(false);if(running)running=false;if(nativeRunning&&window.OrigenStore)OrigenStore.pauseNative();status(syncBusy?'Pausando y guardando el lote…':'Modo automático desactivado para migrar.');update();};
function info(t){$('syncInfo').textContent=t;}
window.origenNativeStopped=p=>{if(p.error){setAuto(false);info('Entrenamiento detenido por error: '+p.error);}else if(p.phase&&p.phase!=='Completado'&&refreshAuto()){info('Sesión pausada por seguridad. La autorización sigue guardada y se reanudará cuando el teléfono lo permita.');}};
function refreshAuto(){auto=!!(bridge&&bridge.repository()&&bridge.autoEnabled());$('syncAuto').checked=auto;return auto;}
function setAuto(enabled){auto=!!(bridge&&bridge.repository()&&enabled);if(bridge&&!bridge.setAutoEnabled(auto)){auto=false;info('No se pudo guardar la autorización automática.');}$('syncAuto').checked=auto;return auto;}
function controls(){for(const id of ['syncConnect','syncDisconnect','syncPull','syncPush'])$(id).disabled=syncing||running||busy||fileBusy||nativeRunning;$('syncApply').disabled=syncing||running||busy||fileBusy||nativeRunning||(!remote&&!syncJob);}
function validate(o){
if(!o||o.version!==1||typeof o.id!=='string'||!/^[-_A-Za-z0-9.]{1,100}$/.test(o.id))throw Error('Lote inválido');
const examples=validData(o.examples||[]);if(examples.length>500)throw Error('Máximo 500 ejemplos por lote');
if(!Number.isInteger(o.steps)||o.steps<0||o.steps>10000||![.003,.001,.0003].includes(o.lr))throw Error('Parámetros de entrenamiento inválidos');
const tests=o.tests||[];if(!Array.isArray(tests)||tests.length>5||tests.some(x=>typeof x!=='string'||!x.trim()||x.length>300))throw Error('Pruebas inválidas');
return {id:o.id,examples,steps:o.steps,lr:o.lr,tests};
}
function preview(){const j=syncJob;if(j){$('syncPreview').textContent='Lote activo: '+j.id+' · '+Math.max(0,j.target-model.step)+' pasos restantes';}else if(remote){$('syncPreview').textContent='Lote: '+remote.id+' · '+remote.examples.length+' ejemplos · '+remote.steps+' pasos · '+remote.tests.length+' pruebas';}else $('syncPreview').textContent='No hay lote nuevo.';controls();}
async function push(state='idle',extra={}){
if(syncJob?.repo&&syncJob.repo!==bridge.repository())throw Error('Conecta el repositorio original del lote activo.');
const obj={version:1,updatedAt:new Date().toISOString(),state,modelSteps:model.step,loss:Number.isFinite(model.loss)?model.loss:null,exampleCount:data.length,parameters:model.count(),context:model.ctx,width:model.d,layers:model.layers||1,heads:model.heads||1,vocab:model.vocab||Origen.V,optimizerSteps:model.optStep,jobId:syncJob?.id||latest?.id||null,appliedIds:syncApplied.slice(-100),...extra};
await call('push',JSON.stringify(obj,null,2));}
async function pull(){if(syncing||running||busy||fileBusy||nativeRunning)return;syncing=true;controls();let received=false;try{const r=await call('pull');if(r.payload){const x=validate(JSON.parse(r.payload));remote=syncApplied.includes(x.id)?null:x;}else remote=null;received=true;info('Conexión correcta.');}catch(e){info('No se pudo recibir el lote: '+e.message);}finally{syncing=false;preview();}if(received&&refreshAuto()&&!document.hidden&&(remote||syncJob))await apply();}
async function apply(){
if(syncing||running||busy||fileBusy||nativeRunning||document.hidden||(!remote&&!syncJob))return;pauseRequested=false;syncing=true;syncBusy=true;update();controls();
try{
if(storageLocked)throw Error('Recupera el respaldo antes de entrenar');
if(!syncJob){
const x=remote;if(syncApplied.includes(x.id))return;if(data.length+x.examples.length>5000)throw Error('Corpus lleno');
const before=data.slice(),beforeIds=syncApplied.slice();data=data.concat(x.examples);syncApplied.push(x.id);syncApplied=syncApplied.slice(-1000);
syncJob={id:x.id,repo:bridge.repository(),target:model.step+x.steps,lr:x.lr,tests:x.tests};if(!save()){data=before;syncApplied=beforeIds;syncJob=null;throw Error('No se pudo guardar lote');}
remote=null;update();renderData();
}
const job=syncJob;if(job.repo&&job.repo!==bridge.repository())throw Error('Conecta el repositorio original del lote activo.');info('Entrenamiento remoto: '+job.id);if($('nativeMode').checked&&window.OrigenStore){let count=Math.max(0,job.target-model.step);let r=startNativeSession(count,job.lr,true);if(!r.started)throw Error(r.error||'No se pudo iniciar la sesión nativa');return;}try{await push('training',{targetSteps:job.target});}catch(e){info('Lote local guardado; no se pudo enviar estado inicial.');}
let remain=Math.max(0,job.target-model.step),trainResult=null;
if(remain&&!pauseRequested){tab('train');trainResult=await train({steps:remain,lr:job.lr,progress:async()=>{try{await push('training',{targetSteps:job.target});}catch(e){info('Entrenando localmente; estado remoto no actualizado.');}}});}
if(pauseRequested||model.step<job.target||document.hidden||!storageOK){const error=trainResult?.error;if(error){setAuto(false);}await push('paused',{targetSteps:job.target,...(error?{error:String(error).slice(0,300)}:{})});info(error?'Error de entrenamiento: '+error:'Pausado. Puedes activar las tres capas o continuar el lote.');return;}
let results=[];if(job.tests.length){setBusy(true);try{for(const q of job.tests){if(document.hidden||pauseRequested)break;results.push({q,a:await generate(q,40,0)});}}finally{setBusy(false);}}
if(pauseRequested||results.length!==job.tests.length){await push('paused',{targetSteps:job.target});return;}
let evaluation=null;try{evaluation=evaluateReference();}catch(e){}latest={id:job.id,results,evaluation};await push('completed',{jobId:job.id,results,evaluation});syncJob=null;if(!save())throw Error('No se pudo guardar el cierre del lote');info('Lote completado y resultados enviados.');
}catch(e){info(e.message);}finally{syncing=false;syncBusy=false;update();preview();}
}
$('syncConnect').onclick=async()=>{if(syncing||running||busy||fileBusy||nativeRunning)return;syncing=true;controls();try{const r=$('syncRepo').value.trim(),t=$('syncToken').value.trim();$('syncToken').value='';if(syncJob?.repo&&syncJob.repo!==r)throw Error('Finaliza primero el lote activo en su repositorio original.');latest=null;remote=null;await call('configure',r,t);refreshAuto();info('Repositorio privado conectado. Pulsa Recibir instrucciones o activa el modo automático.');}catch(e){info(e.message);}finally{syncing=false;controls();}};
$('syncDisconnect').onclick=async()=>{if(syncing||running||busy||fileBusy||nativeRunning)return;syncing=true;controls();try{await call('clear');refreshAuto();$('syncRepo').value='';remote=null;latest=null;info('Desconectado. El modelo permanece en el teléfono.');}catch(e){info(e.message);}finally{syncing=false;preview();}};
$('syncPull').onclick=pull;$('syncApply').onclick=apply;
$('syncPush').onclick=async()=>{if(syncing||running||busy||fileBusy||nativeRunning)return;syncing=true;controls();try{if(!syncJob&&!latest)throw Error('No hay sesión nueva que informar; se conserva el último resultado remoto.');await push(syncJob?'paused':'completed',syncJob?{targetSteps:syncJob.target}:latest?{jobId:latest.id,results:latest.results,evaluation:latest.evaluation}:{});info('Estado enviado.');}catch(e){info(e.message);}finally{syncing=false;controls();}};
$('syncAuto').onchange=()=>{if(setAuto($('syncAuto').checked)){pauseRequested=false;pull();}else if(!bridge?.repository())info('Conecta el repositorio antes de activar el modo automático.');};
if(bridge){$('syncRepo').value=bridge.repository();info($('syncRepo').value?'Conexión guardada.':'Configura un repositorio privado.');}else info('Disponible en Android.');
function resumeAuto(){if(refreshAuto()&&!document.hidden&&!storageLocked&&!running&&!busy&&!syncing&&!fileBusy&&!nativeRunning&&(!window.OrigenStore||OrigenStore.nativeSafeToResume()))pull();}
window.origenResumeSync=resumeAuto;
setInterval(()=>{controls();resumeAuto();},60000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden)resumeAuto();});
preview();refreshAuto();setTimeout(resumeAuto,500);
})();
