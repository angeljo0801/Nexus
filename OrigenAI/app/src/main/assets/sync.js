'use strict';
(()=>{
const bridge=window.OrigenSync, pending=new Map();let serial=0, remote=null, syncing=false, auto=false, latest=null;
window.origenSyncReply=(id,json)=>{const cb=pending.get(id);if(cb){pending.delete(id);cb(JSON.parse(json));}};
function call(op,a='',b=''){return new Promise((resolve,reject)=>{if(!bridge)return reject(Error('Disponible solo en Android.'));const id=String(++serial);pending.set(id,r=>r.ok?resolve(r):reject(Error(r.error)));bridge.request(id,op,a,b);setTimeout(()=>{if(pending.delete(id))reject(Error('Tiempo de espera agotado.'));},65000);});}
function info(t){$('syncInfo').textContent=t;}
function controls(){for(const id of ['syncConnect','syncDisconnect','syncPull','syncPush'])$(id).disabled=syncing||running||busy||fileBusy;$('syncApply').disabled=syncing||running||busy||fileBusy||(!remote&&!syncJob);}
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
const obj={version:1,updatedAt:new Date().toISOString(),state,modelSteps:model.step,loss:Number.isFinite(model.loss)?model.loss:null,exampleCount:data.length,parameters:model.count(),context:model.ctx,width:model.d,jobId:syncJob?.id||latest?.id||null,appliedIds:syncApplied.slice(-100),...extra};
await call('push',JSON.stringify(obj,null,2));}
async function pull(){if(syncing||running||busy||fileBusy)return;syncing=true;controls();try{const r=await call('pull');if(r.payload){const x=validate(JSON.parse(r.payload));remote=syncApplied.includes(x.id)?null:x;}else remote=null;info('Conexión correcta.');}catch(e){info(e.message);}finally{syncing=false;preview();}if(auto&&!document.hidden&&(remote||syncJob))await apply();}
async function apply(){
if(syncing||running||busy||fileBusy||document.hidden||(!remote&&!syncJob))return;syncing=true;syncBusy=true;update();controls();
try{
if(storageLocked)throw Error('Recupera el respaldo antes de entrenar');
if(!syncJob){
const x=remote;if(syncApplied.includes(x.id))return;if(data.length+x.examples.length>5000)throw Error('Corpus lleno');
const before=data.slice(),beforeIds=syncApplied.slice();data=data.concat(x.examples);syncApplied.push(x.id);syncApplied=syncApplied.slice(-1000);
syncJob={id:x.id,repo:bridge.repository(),target:model.step+x.steps,lr:x.lr,tests:x.tests};if(!save()){data=before;syncApplied=beforeIds;syncJob=null;throw Error('No se pudo guardar lote');}
remote=null;update();renderData();
}
const job=syncJob;if(job.repo&&job.repo!==bridge.repository())throw Error('Conecta el repositorio original del lote activo.');info('Entrenamiento remoto: '+job.id);try{await push('training',{targetSteps:job.target});}catch(e){info('Lote local guardado; no se pudo enviar estado inicial.');}
let remain=Math.max(0,job.target-model.step);
if(remain){tab('train');await train({steps:remain,lr:job.lr,progress:async()=>{try{await push('training',{targetSteps:job.target});}catch(e){info('Entrenando localmente; estado remoto no actualizado.');}}});}
if(model.step<job.target||document.hidden||!storageOK){await push('paused',{targetSteps:job.target});info('Pausado. Abre la aplicación para continuar.');return;}
let results=[];if(job.tests.length){setBusy(true);try{for(const q of job.tests){if(document.hidden)break;results.push({q,a:await generate(q,40,0)});}}finally{setBusy(false);}}
if(results.length!==job.tests.length){await push('paused');return;}
latest={id:job.id,results};await push('completed',{jobId:job.id,results});syncJob=null;if(!save())throw Error('No se pudo guardar el cierre del lote');info('Lote completado y resultados enviados.');
}catch(e){info(e.message);}finally{syncing=false;syncBusy=false;update();preview();}
}
$('syncConnect').onclick=async()=>{if(syncing||running||busy||fileBusy)return;syncing=true;controls();try{const r=$('syncRepo').value.trim(),t=$('syncToken').value.trim();$('syncToken').value='';if(syncJob?.repo&&syncJob.repo!==r)throw Error('Finaliza primero el lote activo en su repositorio original.');latest=null;remote=null;await call('configure',r,t);info('Repositorio privado conectado.');}catch(e){info(e.message);}finally{syncing=false;controls();}};
$('syncDisconnect').onclick=async()=>{if(syncing||running||busy||fileBusy)return;syncing=true;controls();try{await call('clear');auto=false;$('syncAuto').checked=false;$('syncRepo').value='';remote=null;latest=null;info('Desconectado. El modelo permanece en el teléfono.');}catch(e){info(e.message);}finally{syncing=false;preview();}};
$('syncPull').onclick=pull;$('syncApply').onclick=apply;
$('syncPush').onclick=async()=>{if(syncing||running||busy||fileBusy)return;syncing=true;controls();try{if(!syncJob&&!latest)throw Error('No hay sesión nueva que informar; se conserva el último resultado remoto.');await push(syncJob?'paused':'completed',syncJob?{targetSteps:syncJob.target}:latest?{jobId:latest.id,results:latest.results}:{});info('Estado enviado.');}catch(e){info(e.message);}finally{syncing=false;controls();}};
$('syncAuto').onchange=()=>{auto=$('syncAuto').checked;if(auto)pull();};
if(bridge){$('syncRepo').value=bridge.repository();info($('syncRepo').value?'Conexión guardada.':'Configura un repositorio privado.');}else info('Disponible en Android.');
setInterval(()=>{controls();if(auto&&!document.hidden&&!running&&!busy&&!syncing&&!fileBusy)pull();},60000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&auto)pull();});
preview();
})();
