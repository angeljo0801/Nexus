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

const {DeepTransformer,referenceLoss}=require('../app/src/main/assets/model.js');
const corpusDeep=[{kind:'dialog',q:'Hola, ¿qué tal?',a:'Muy bien, gracias.'},{kind:'text',text:'conversación conversación conversación conversación conversación.'}];
const deepOld=new Transformer({d:48,ctx:64});deepOld.train(...example(deepOld,corpusDeep[0]),.001);
const identity=DeepTransformer.upgrade(deepOld,corpusDeep,640,42);
const input=[256,...encode('Hola'),258],l0=deepOld.forward(input).logits,l1=identity.forward(input).logits;
for(let i=0;i<l0.length;i++)assert(Math.abs(l0[i]-l1[i])<0.0002);
const deep=DeepTransformer.upgrade(deepOld,corpusDeep,1024,42);
assert.equal(deep.layers,3);assert.equal(deep.heads,4);assert(deep.vocab>640);
assert.equal(deep.decode(deep.encode('¡Hola, conversación!')),'¡Hola, conversación!');
let long=example(deep,{kind:'dialog',q:'hola '.repeat(100),a:'adiós '.repeat(100)});assert(long[0].length<=deep.ctx);
const initialDeep=referenceLoss(deep,[corpusDeep[0]]);
for(let i=0;i<5;i++)deep.train(...example(deep,corpusDeep[0]),.001);
assert(referenceLoss(deep,[corpusDeep[0]])<initialDeep);
assert(deep.p.L1_O.some(x=>x!==0));assert(deep.p.L2_B.some(x=>x!==0));
const restoredDeep=Transformer.restore(deep.export());assert.equal(restoredDeep.step,deep.step);assert.equal(restoredDeep.vocab,deep.vocab);
assert.equal(restoredDeep.count(),deep.count());assert.equal(restoredDeep.reply('Hola',12,0),deep.reply('Hola',12,0));
console.log({deepParameters:deep.count(),vocab:deep.vocab,layers:deep.layers,referenceLoss:referenceLoss(deep,[corpusDeep[0]])});
