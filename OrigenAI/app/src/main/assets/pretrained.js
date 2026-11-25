'use strict';
(()=>{
const bridge=window.OrigenPretrained,local=window.OrigenLocal;
const $=id=>document.getElementById(id);
const DEFAULT={version:1,transport:'device',localVariant:'qwen08',endpoint:'http://127.0.0.1:11434',model:'qwen3.5:0.8b',messages:[],examples:[]};
let config={...DEFAULT},pending=new Map(),lastPair=null,serial=0,busy=false;
const info=t=>{$('preStatus').textContent=t;};
window.origenPretrainedNotice=info;
window.origenPretrainedReply=(id,json)=>{const cb=pending.get(id);if(cb){pending.delete(id);try{cb(typeof json==='string'?JSON.parse(json):json);}catch(e){cb({ok:false,error:'Respuesta inválida del motor local'});}}};
function load(){if(!bridge)return;try{const raw=bridge.read();if(raw==='!ERROR')throw Error('No se pudo leer el guardado independiente');if(raw){const x=JSON.parse(raw);if(x.version===1){config={...DEFAULT,...x};config.messages=Array.isArray(x.messages)?x.messages.slice(-40):[];config.examples=Array.isArray(x.examples)?x.examples.slice(-600):[];}}}catch(e){info('Error leyendo la memoria preentrenada: '+e.message);}}
function save(){if(!bridge)return false;config.messages=config.messages.slice(-40);config.examples=config.examples.slice(-600);let ok=bridge.write(JSON.stringify(config));if(!ok)info('No se pudo guardar. No elimines los datos de la aplicación.');return ok;}
function capture(){config.transport=$('preTransport').value;config.localVariant=$('preLocalVariant').value;config.endpoint=$('preEndpoint').value.trim().replace(/\/$/,'');config.model=$('preModel').value.trim();return config;}
window.origenRemoteSettings=()=>({enabled:config.remoteEnabled===true,last:config.remoteLast||null});
window.origenRemoteSave=(changes)=>{Object.assign(config,changes);return save();};
function fill(){$('preTransport').value=config.transport;$('preLocalVariant').value=config.localVariant||'qwen08';$('preEndpoint').value=config.endpoint;$('preModel').value=config.model;render();toggleTransport();refreshLocal();}
function render(){const box=$('preMessages');box.textContent='';for(const m of config.messages){if(!m||!['user','assistant'].includes(m.role))continue;const el=document.createElement('div');el.className='message '+(m.role==='user'?'user':'ai');el.textContent=m.content;box.appendChild(el);}box.scrollTop=box.scrollHeight;$('preCount').textContent=config.examples.length+' ejemplos preparados para entrenamiento posterior (no aplicados a los pesos).';const list=$('preExampleList');list.textContent='';for(const item of config.examples.slice(-4).reverse()){const div=document.createElement('div');div.className='item';div.textContent='Pregunta: '+item.q+'\nRespuesta ideal: '+item.a;list.appendChild(div);}}
function select(mode){const pre=mode==='pre';$('selectPretrained').classList.toggle('active',pre);$('selectExperimental').classList.toggle('active',!pre);$('experimentNav').hidden=pre;tab(pre?'pretrained':'chat');}
$('selectPretrained').onclick=()=>select('pre');$('selectExperimental').onclick=()=>select('experimental');
$('preSave').onclick=()=>{capture();if(save())info('Configuración del motor local guardada.');};
$('preTransport').onchange=()=>{if($('preTransport').value==='openai'&&$('preEndpoint').value==='http://127.0.0.1:11434')$('preEndpoint').value='http://127.0.0.1:8080';else if($('preTransport').value==='ollama'&&$('preEndpoint').value==='http://127.0.0.1:8080')$('preEndpoint').value='http://127.0.0.1:11434';capture();save();toggleTransport();};
function request(messages){return new Promise((resolve,reject)=>{if(!bridge)return reject(Error('Solo disponible en Android'));const id=String(++serial);pending.set(id,r=>r.ok?resolve(r.answer):reject(Error(r.error||'Error de inferencia')));if(config.transport==='device'){if(!local){pending.delete(id);return reject(Error('Motor GGUF no integrado en esta APK'));}local.request(id,config.localVariant,JSON.stringify(messages));}else bridge.request(id,config.endpoint,config.transport,config.model,JSON.stringify(messages));setTimeout(()=>{if(pending.delete(id))reject(Error('El motor local no respondió. Comprueba la conexión.'));},125000);});}
async function send(){if(busy)return;capture();const q=$('prePrompt').value.trim();if(!q)return;busy=true;$('preSend').disabled=true;info('Generando con el motor local…');const history=config.messages.slice(-16).filter(m=>m&&['user','assistant'].includes(m.role));$('prePrompt').value='';try{const messages=[{role:'system',content:'Eres Origen AI, un asistente que responde en español claro, natural y preciso. Reconoce tus límites y evita inventar datos.'},...history,{role:'user',content:q}];const answer=await request(messages);config.messages.push({role:'user',content:q},{role:'assistant',content:answer});lastPair={q,a:answer};$('preIdeal').value=answer;save();render();info(config.transport==='device'?'Respuesta generada sin internet con '+config.localVariant:'Respuesta generada con '+config.model+' · motor '+config.transport);}catch(e){$('prePrompt').value=q;info('No se pudo generar: '+e.message);}finally{busy=false;$('preSend').disabled=false;}}
$('preSend').onclick=send;
function toggleTransport(){const device=$('preTransport').value==='device';$('preLocalControls').style.display=device?'block':'none';$('preServerControls').style.display=device?'none':'block';}
function parseLocal(raw){try{return JSON.parse(raw);}catch(e){return {ok:false,error:'Estado del motor no válido'};}}
function refreshLocal(){if(!local){$('preLocalProgress').textContent='Esta APK no incluye el motor GGUF integrado.';return;}const variant=$('preLocalVariant').value;const s=parseLocal(local.status(variant));if(s.error){$('preLocalProgress').textContent=s.error;return;}
let state=s.loaded?'Cargado en RAM':s.installed?'Descargado · se verificará antes del primer uso':s.downloading?'Descargando GGUF…':s.downloadFailed?'Descarga fallida: cancela e intenta nuevamente':'No descargado';
if(!s.engine)state='Motor ARM64 no disponible: '+(s.engineError||'sin biblioteca nativa');
const b=s.downloaded||0,t=s.total||0;
if(s.downloading&&t>0)state+=' '+(100*b/t).toFixed(1)+' %';
$('preDownloadBar').style.width=s.downloading&&t>0?Math.min(100,100*b/t)+'%':s.installed?'100%':'0%';
$('preLocalProgress').textContent=state+' · '+(s.installed?(s.bytes/1e6).toFixed(0)+' MB':s.downloading?(b/1e6).toFixed(0)+' MB recibidos':'');
$('preDownload').disabled=!!s.downloading||!!s.installed;
$('preCancelDownload').disabled=!s.downloading;
}
$('preLocalVariant').onchange=()=>{capture();save();refreshLocal();};
$('preDownload').onclick=()=>{if(!local)return info('Instala la APK con motor GGUF');capture();const r=parseLocal(local.download(config.localVariant,$('preMobileData').checked));info(r.ok?r.message:r.error);refreshLocal();};
$('preCancelDownload').onclick=()=>{if(!local)return;capture();const r=parseLocal(local.cancel(config.localVariant));info(r.ok?r.message:r.error);refreshLocal();};
$('preDelete').onclick=()=>{if(!local)return;capture();if(!window.confirm('¿Borrar el archivo GGUF de este modelo? Se necesitará otra descarga para usarlo.'))return;const r=parseLocal(local.delete(config.localVariant));info(r.ok?r.message:r.error);refreshLocal();};
$('preUnload').onclick=()=>{if(!local)return;local.unload();info('Liberando memoria RAM…');};
$('preStop').onclick=()=>{if(!local||config.transport!=='device')return;local.stop();info('Solicitada interrupción de la respuesta local.');};
setInterval(refreshLocal,2500);
$('prePrompt').onkeydown=e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();send();}};
$('preCheck').onclick=async()=>{capture();info('Comprobando motor…');try{const answer=await request([{role:'user',content:'Responde solo con un saludo breve en español.'}]);info('Motor disponible · ejemplo: '+answer.slice(0,150));if(save())render();}catch(e){info('No hay motor accesible: '+e.message);}};
$('preClear').onclick=()=>{if(!window.confirm('¿Limpiar únicamente el chat de Origen AI 2.0?'))return;config.messages=[];lastPair=null;$('preIdeal').value='';save();render();info('Chat preentrenado limpio. Se conservaron los ejemplos.');};
$('preAddExample').onclick=()=>{let a=$('preIdeal').value.trim();if(!lastPair||!a||a.length>3500){info('Primero genera una respuesta y edita su versión ideal.');return;}if(config.examples.length>=600){info('Exporta el conjunto antes de añadir más ejemplos.');return;}config.examples.push({q:lastPair.q,a});if(save()){render();info('Ejemplo guardado, todavía sin modificar los pesos neuronales.');}};
$('preExport').onclick=()=>{if(!config.examples.length)return info('Guarda al menos un ejemplo antes de exportar.');if(!bridge)return info('Exportación disponible en Android.');const jsonl=config.examples.map(e=>JSON.stringify({messages:[{role:'user',content:e.q},{role:'assistant',content:e.a}]})).join('\n')+'\n';bridge.exportExamples(jsonl);};
function remoteLocalRequest(variant,messages){
  return new Promise((resolve,reject)=>{
    if(!local)return reject(Error('El motor GGUF integrado no está disponible'));
    const id=String(++serial);
    pending.set(id,r=>r.ok?resolve(r.answer):reject(Error(r.error||'Error neuronal local')));
    local.request(id,variant,JSON.stringify(messages));
    setTimeout(()=>{if(pending.delete(id))reject(Error('La generación local superó el tiempo permitido'));},180000);
  });
}
window.origenRemoteInfer=async(variant,question)=>{
  if(busy)throw Error('Hay una conversación o evaluación en curso');
  if(!local)throw Error('El motor local no está instalado');
  if(!['qwen08','qwen2'].includes(variant)||typeof question!=='string'||question.length>300)
    throw Error('Pregunta remota inválida');
  busy=true;
  try{
    return await remoteLocalRequest(variant,[
      {role:'system',content:'Eres Origen AI. Contesta en español de forma natural, breve, útil y honesta. No uses conversaciones anteriores.'},
      {role:'user',content:question}
    ]);
  }finally{busy=false;}
};
const EVAL=[
'Una compañera de trabajo está preocupada por una reunión importante. ¿Qué le dirías?',
'Explícame por qué una cuchara de metal se siente fría en una habitación templada.',
'Tengo tres tareas urgentes y solo una hora. ¿Cómo decidirías por cuál empezar?',
'¿Qué dato te faltaría antes de recomendar una compra que cuesta mucho dinero?',
'Escribe dos oraciones distintas usando correctamente la palabra aunque.'
];
$('preEval').onclick=async()=>{if(busy)return;capture();busy=true;$('preEval').disabled=true;const rows=[];$('preEvalResults').textContent='Evaluando…';try{for(let i=0;i<EVAL.length;i++){info('Evaluación '+(i+1)+' de '+EVAL.length);let a;try{a=await request([{role:'system',content:'Responde en español con claridad y precisión.'},{role:'user',content:EVAL[i]}]);}catch(e){a='ERROR: '+e.message;rows.push({q:EVAL[i],a});break;}rows.push({q:EVAL[i],a});$('preEvalResults').textContent=rows.map((r,j)=>(j+1)+'. '+r.q+'\nRespuesta: '+r.a).join('\n\n');}config.lastEvaluation={model:config.model,at:new Date().toISOString(),results:rows};save();info('Evaluación terminada: '+rows.length+' de '+EVAL.length+'. Revisa pertinencia, coherencia y naturalidad.');}finally{busy=false;$('preEval').disabled=false;}};
load();fill();if(!bridge)info('Instala la APK Android para conectar el motor local.');
})();
