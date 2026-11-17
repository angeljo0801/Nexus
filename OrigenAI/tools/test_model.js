const assert=require('node:assert/strict');const {Transformer,example,encode,decode}=require('../app/src/main/assets/model.js');
let m=new Transformer(), e=example(m,{kind:'dialog',q:'Hola',a:'Hola, ¿cómo estás?'});assert.equal(decode(encode('¡Hola, español!')), '¡Hola, español!');let initial=m.train(...e);for(let i=0;i<180;i++)m.train(...e);let reply=m.reply('Hola',30,.15);assert.equal(reply,'Hola, ¿cómo estás?');assert(m.loss<initial);let saved=Transformer.restore(m.export());assert.equal(saved.step,m.step);assert.equal(saved.reply('Hola',30,.15),reply);console.log({parameters:m.count(),initialLoss:initial,finalLoss:m.loss,reply,steps:saved.step});

const {BOS,SEP,V}=require('../app/src/main/assets/model.js');
const ids=[BOS,...encode('Hola'),SEP];
for(const [width,context,count] of [[128,96,307840],[256,128,885376]]){
  const original=saved.forward(ids).logits, big=saved.widen(width,context,77);
  assert.equal(big.count(),count);assert.equal(big.step,saved.step);assert.equal(big.optStep,0);
  const widened=big.forward(ids).logits;let err=0;
  for(let i=0;i<original.length;i++)err=Math.max(err,Math.abs(original[i]-widened[i]));
  assert(err<0.0002,'Widened logits differ: '+err);
  const before=big.p.W.slice();big.train(...example(big,{kind:'dialog',q:'Hola',a:'Hola, ¿cómo estás?'}),.001);
  assert.equal(big.step,saved.step+1);assert.equal(big.optStep,1);
  assert(big.p.W.subarray(saved.d*V).some((v,i)=>v!==before[saved.d*V+i]));
  let restored=Transformer.restore(big.export());assert.equal(restored.count(),count);assert.equal(restored.step,big.step);assert.equal(restored.optStep,1);
  console.log({width,context,count,maxLogitError:err,loss:big.loss});
}
