'use strict';
(()=>{
const $=id=>document.getElementById(id);
const auto=$('preRemoteAuto'),state=$('preRemoteState'),answers=$('preRemoteAnswers');
let working=false;
const report=t=>{state.textContent=t;};
const read=()=>window.origenRemoteSettings?.()||{enabled:false,last:null};
const store=(updates)=>window.origenRemoteSave?.(updates)===true;
const connected=()=>Boolean(window.origenSyncRepo?.());
function validate(job){
  if(!job||job.version!==1||typeof job.id!=='string'||
    !/^[A-Za-z0-9._-]{1,90}$/.test(job.id)||!['qwen08','qwen2'].includes(job.model)||
    !Array.isArray(job.questions)||job.questions.length<1||job.questions.length>5||
    job.questions.some(q=>typeof q!=='string'||!q.trim()||q.length>300)||
    new Set(job.questions).size!==job.questions.length)
    throw Error('La solicitud no cumple el formato permitido (máximo cinco preguntas)');
  return {id:job.id,model:job.model,questions:job.questions};
}
function show(cache){
  answers.textContent='';
  for(const item of cache?.results||[]){
    const el=document.createElement('div');el.className='item';
    el.textContent='Pregunta: '+item.q+'\nRespuesta: '+item.a;
    answers.appendChild(el);
  }
}
async function check(manual=false){
  if(working||document.hidden)return;
  if(!manual&&!read().enabled)return;
  if(!connected()){report('Primero conecta el repositorio privado en Modelo experimental → Conexión.');return;}
  if(!window.origenRemoteCall||!window.origenRemoteInfer){report('Necesitas actualizar Origen AI para activar el canal.');return;}
  if(window.OrigenStore?.nativeActive()){report('El modelo experimental está entrenando. Las pruebas de Qwen siguen pendientes.');return;}
  working=true;$('preRemoteCheck').disabled=true;
  try{
    report('Consultando el repositorio privado…');
    const response=await window.origenRemoteCall('pre_pull');
    if(!response.payload){report('Sin solicitudes de evaluación nuevas.');return;}
    const job=validate(JSON.parse(response.payload));
    if(response.lastId===job.id){report('Lote '+job.id+' respondido anteriormente.');return;}
    const status=JSON.parse(window.OrigenLocal?.status(job.model)||'{}');
    if(!status.engine){report('Motor GGUF no disponible: '+(status.engineError||'abre una APK ARM64 compatible'));return;}
    if(!status.installed){report('Solicitud '+job.id+' pendiente. Descarga primero el modelo '+job.model+'.');return;}
    if(status.generating){report('El teléfono está ocupado generando otra respuesta.');return;}
    let cache=read().last;
    if(cache?.id!==job.id||cache?.model!==job.model||
      !Array.isArray(cache.results)||cache.results.some((r,i)=>r.q!==job.questions[i])){
      cache={id:job.id,model:job.model,results:[],state:'pending'};
      if(!store({remoteLast:cache}))throw Error('No se pudo guardar el progreso de evaluación');
    }
    show(cache);
    if(cache.state==='pending'){
      for(let i=cache.results.length;i<job.questions.length;i++){
        if(document.hidden){report('La aplicación se ocultó; las respuestas parciales están guardadas.');return;}
        report('Evaluando '+(i+1)+' de '+job.questions.length+' · '+job.id);
        try{
          const text=await window.origenRemoteInfer(job.model,job.questions[i]);
          if(typeof text!=='string'||!text.trim())throw Error('Respuesta vacía');
          cache.results.push({q:job.questions[i],a:text.slice(0,4000)});
        }catch(e){
          cache.state='error';cache.error=String(e.message||e).slice(0,250);
          if(!store({remoteLast:cache}))throw Error('No se pudo guardar el error');
          break;
        }
        if(!store({remoteLast:cache}))throw Error('No se pudo guardar una respuesta de evaluación');
        show(cache);
      }
      if(cache.state==='pending'&&cache.results.length===job.questions.length)cache.state='completed';
      if(!store({remoteLast:cache}))throw Error('No se pudo guardar el resultado antes de sincronizar');
    }
    if(cache.state==='pending')return;
    report('Publicando únicamente las preguntas de prueba y sus respuestas…');
    const body={version:1,id:job.id,model:job.model,state:cache.state,
      updatedAt:new Date().toISOString(),results:cache.results};
    if(cache.state==='error')body.error=cache.error||'Error al generar una respuesta';
    await window.origenRemoteCall('pre_push',JSON.stringify(body));
    report(cache.state==='completed'?'Evaluación '+job.id+' completada. Las respuestas ya están en GitHub.':
      'Error de evaluación registrado en GitHub. '+(cache.error||''));
  }catch(e){report('No se pudo sincronizar: '+String(e.message||e));}
  finally{working=false;$('preRemoteCheck').disabled=false;}
}
auto.checked=read().enabled;
auto.onchange=()=>{
  const enabled=auto.checked;
  if(!store({remoteEnabled:enabled})){auto.checked=!enabled;report('No se pudo guardar la autorización');return;}
  if(enabled){report('Autorizado. Se revisarán pruebas cuando Origen AI esté visible y Qwen descargado.');check();}
  else report('Pruebas remotas automáticas desactivadas. El chat local sigue privado.');
};
$('preRemoteCheck').onclick=()=>check(true);
$('preRemoteOpenSync').onclick=()=>{
  $('selectExperimental').click();
  if(typeof tab==='function')tab('sync');
};
setInterval(()=>{if(!document.hidden&&read().enabled)check();},60000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&read().enabled)check();});
show(read().last);
if(auto.checked)setTimeout(()=>check(),1800);
window.origenPretrainedRemoteCheck=()=>check(true);
})();
