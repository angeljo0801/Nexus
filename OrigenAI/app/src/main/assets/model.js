/* ORIGEN: decoder-only causal Transformer. No libraries, no pretrained weights. */
(function(root){
'use strict';
const MERGES=[[115,32],[101,32],[101,110],[97,32],[111,32],[97,114],[101,114],[101,115],[99,111],[194,191],[195,169],[117,110],[112,114],[117,269],[46,32],[101,259],[97,110],[272,32],[121,32],[267,110],[99,105],[111,259],[97,108],[115,116],[105,110],[195,179],[105,261],[264,32],[97,259],[113,117],[268,81],[111,114],[195,173],[111,100],[103,117],[101,109],[97,98],[97,115],[289,276],[265,32],[116,260],[97,109],[101,100],[101,108],[261,100],[270,262],[44,32],[116,105],[271,303],[97,279],[266,116],[195,161],[111,277],[101,103],[111,110],[265,115],[288,260],[100,260],[117,301],[100,263],[294,280],[284,110],[32,108],[32,109],[32,112],[278,118],[97,307],[293,282],[308,320],[77,260],[267,109],[194,161],[33,32],[117,261],[195,177],[97,99],[324,314],[100,105],[100,111],[116,114],[263,115],[101,120],[266,112],[292,319],[111,117],[116,117],[69,282],[345,311],[113,276],[105,265],[270,116],[112,108],[109,101],[115,105],[114,32],[284,109],[281,32],[111,99],[116,261],[108,264],[271,312],[359,349],[283,103],[121,343],[111,108],[97,63],[116,111],[112,264],[114,101],[275,318],[268,67],[354,263],[100,291],[290,32],[103,111],[114,105],[263,315],[117,99],[97,100],[97,121],[78,263],[262,108],[97,46],[104,295],[80,317],[97,106],[351,106],[302,32],[369,370],[98,285],[376,104],[117,100],[270,32],[110,116],[117,348],[105,99],[114,341],[98,114],[287,112],[266,99],[97,116],[278,32],[309,310],[66,332],[97,333],[116,264],[102,117],[195,186],[108,108],[97,273],[101,99],[382,108],[291,262],[261,103],[350,394],[383,274],[111,273],[300,260],[328,326],[115,101],[105,100],[306,99],[69,259],[325,298],[105,259],[117,368],[117,309],[110,361],[296,63],[378,390],[116,101],[410,286],[326,264],[431,411],[283,116],[433,265],[84,412],[304,360],[340,413],[67,272],[438,392],[439,416],[105,116],[109,310],[111,63],[269,32],[327,46],[307,298],[385,290],[301,105],[80,342],[112,342],[321,262],[297,274],[327,32],[314,313],[108,101],[112,317],[275,32],[395,425],[72,363],[459,97],[402,287],[32,371],[387,299],[405,260],[273,268],[89,32],[104,334],[262,335],[110,32],[264,46],[407,300],[114,308],[328,281],[473,312],[474,114],[428,264],[98,332],[285,337],[105,122],[285,365],[112,296],[435,263],[67,358],[109,260],[348,274],[261,116],[263,316],[111,338],[488,262],[268,414],[296,46],[278,116],[366,262],[112,101],[111,396],[495,260],[108,262],[417,262],[325,265],[398,389],[97,118],[111,115],[281,373],[116,280],[286,304],[112,454],[262,315],[116,292],[341,403],[509,363],[81,393],[511,263],[281,295],[513,114],[514,287],[271,334],[516,420],[115,261],[72,111],[519,119],[520,32],[264,260],[104,399],[523,32],[101,264],[525,426],[67,424],[401,115],[528,63],[100,266],[331,297],[116,355],[465,466],[116,406],[84,292],[97,288],[536,291],[266,63],[323,264],[79,374],[540,103],[541,261],[270,322],[292,302],[111,305],[97,277],[289,393],[547,274],[108,375],[284,63],[117,114],[434,266],[101,63],[288,485],[283,357],[555,116],[409,266],[270,323],[263,442],[559,259],[339,444],[335,264],[117,101],[317,260],[275,429],[309,117],[566,336],[275,337],[338,295],[569,384],[69,115],[112,265],[72,311],[380,262],[105,396],[102,114],[118,105],[108,32],[114,111],[115,286],[313,274],[83,291],[582,305],[116,294],[499,63],[288,105],[285,504],[283,102],[588,290],[589,109],[300,98],[419,101],[261,338],[85,110],[115,117],[456,263],[280,99],[101,106],[598,294],[599,350],[105,109],[418,333],[304,458],[339,295],[385,372],[261,293],[606,384],[101,46],[266,46],[262,329],[340,271],[611,266],[262,278],[302,108],[522,362],[71,111],[616,292],[87,524],[321,526],[489,506],[305,450],[109,105],[97,305],[261,32],[296,273],[105,279],[97,107],[330,460],[628,331],[402,280],[630,371],[631,296],[403,275],[461,404],[532,344],[635,462],[636,364],[461,110],[638,356]];
const V=259+MERGES.length, BOS=256, EOS=257, SEP=258;
const enc=new TextEncoder(), dec=new TextDecoder();
const expansion=Array.from({length:259},(_,i)=>i<256?[i]:[]), ranks=new Map();for(let i=0;i<MERGES.length;i++){let [a,b]=MERGES[i];expansion.push([...expansion[a],...expansion[b]]);ranks.set(a*V+b,i+259);}
const encode=s=>{let a=Array.from(enc.encode(s));while(a.length>1){let rank=Infinity;for(let i=0;i<a.length-1;i++){let r=ranks.get(a[i]*V+a[i+1]);if(r!==undefined&&r<rank)rank=r;}if(rank===Infinity)break;let b=[];for(let i=0;i<a.length;i++){if(i+1<a.length&&ranks.get(a[i]*V+a[i+1])===rank){b.push(rank);i++;}else b.push(a[i]);}a=b;}return a;};
const decode=a=>dec.decode(Uint8Array.from(a.flatMap(x=>expansion[x]||[])));
const pack=a=>{let bytes=new Uint8Array(a.buffer,a.byteOffset,a.byteLength),s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s);};
const unpack=s=>{let b=atob(s),a=new Uint8Array(b.length);for(let i=0;i<b.length;i++)a[i]=b.charCodeAt(i);return new Float32Array(a.buffer);};
const zeros=n=>new Float32Array(n);
function rng(seed){let x=seed>>>0||123;return()=>{x^=x<<13;x^=x>>>17;x^=x<<5;return (x>>>0)/4294967296;};}
function soft(a){let m=-Infinity;for(let x of a)m=Math.max(m,x);let z=0;for(let i=0;i<a.length;i++){a[i]=Math.exp(a[i]-m);z+=a[i];}for(let i=0;i<a.length;i++)a[i]/=z;return a;}
class Transformer {
 constructor({d=48,ctx=64,seed=12345}={}){this.d=d;this.ctx=ctx;this.f=d*2;this.r=rng(seed);this.step=0;this.optStep=0;this.loss=null;this.p={};this.m={};this.v={};this.shapes={E:[V,d],P:[ctx,d],Q:[d,d],K:[d,d],U:[d,d],O:[d,d],A:[d,this.f],B:[this.f,d],W:[d,V],b:[1,V]};for(const [k,[a,b]] of Object.entries(this.shapes)){let p=this.p[k]=zeros(a*b);this.m[k]=zeros(p.length);this.v[k]=zeros(p.length);let scale=k==='b'?0:Math.sqrt(6/(a+b));if(k==='E'||k==='P')scale=.12;for(let j=0;j<p.length;j++)p[j]=(this.r()*2-1)*scale;}}
 count(){return Object.values(this.p).reduce((a,b)=>a+b.length,0);}
 // y = x W, row-major
 mm(x,w,n,a,b){let y=zeros(n*b);for(let i=0;i<n;i++)for(let j=0;j<a;j++){let q=x[i*a+j],off=j*b;for(let k=0;k<b;k++)y[i*b+k]+=q*w[off+k];}return y;}
 // backprop for y = x W, accumulate into dw
 back(x,w,dy,dw,n,a,b){let dx=zeros(n*a);for(let i=0;i<n;i++)for(let j=0;j<a;j++){let q=x[i*a+j],off=j*b,s=0;for(let k=0;k<b;k++){let g=dy[i*b+k];dw[off+k]+=q*g;s+=w[off+k]*g;}dx[i*a+j]=s;}return dx;}
 forward(ids){let n=ids.length,d=this.d,f=this.f,p=this.p,x=zeros(n*d);for(let i=0;i<n;i++)for(let j=0;j<d;j++)x[i*d+j]=p.E[ids[i]*d+j]+p.P[i*d+j];let q=this.mm(x,p.Q,n,d,d),k=this.mm(x,p.K,n,d,d),u=this.mm(x,p.U,n,d,d),att=zeros(n*n),c=zeros(n*d),sc=1/Math.sqrt(d);for(let i=0;i<n;i++){let s=zeros(i+1);for(let j=0;j<=i;j++){let v=0;for(let h=0;h<d;h++)v+=q[i*d+h]*k[j*d+h];s[j]=v*sc;}soft(s);for(let j=0;j<=i;j++){att[i*n+j]=s[j];for(let h=0;h<d;h++)c[i*d+h]+=s[j]*u[j*d+h];}}let h=this.mm(c,p.O,n,d,d);for(let i=0;i<h.length;i++)h[i]+=x[i];let z=this.mm(h,p.A,n,d,f);for(let i=0;i<z.length;i++)z[i]=Math.tanh(z[i]);let y=this.mm(z,p.B,n,f,d);for(let i=0;i<y.length;i++)y[i]+=h[i];let logits=this.mm(y,p.W,n,d,V);for(let i=0;i<n;i++)for(let j=0;j<V;j++)logits[i*V+j]+=p.b[j];return {n,d,f,x,q,k,u,att,c,h,z,y,logits};}
 train(ids,targets,lr=.003){let s=this.forward(ids),{n,d,f,x,q,k,u,att,c,h,z,y,logits}=s,p=this.p,g={};for(let key in p)g[key]=zeros(p[key].length);let dl=zeros(n*V),loss=0,count=0;for(let i=0;i<n;i++)if(targets[i]>=0)count++;if(!count)return null;for(let i=0;i<n;i++){let t=targets[i];if(t<0)continue;let prob=soft(logits.slice(i*V,(i+1)*V));loss-=Math.log(Math.max(1e-12,prob[t]));for(let j=0;j<V;j++){let v=(prob[j]-(j===t?1:0))/count;dl[i*V+j]=v;g.b[j]+=v;}}
 let dy=this.back(y,p.W,dl,g.W,n,d,V),dz=this.back(z,p.B,dy,g.B,n,f,d);for(let i=0;i<dz.length;i++)dz[i]*=1-z[i]*z[i];let dh=this.back(h,p.A,dz,g.A,n,d,f);for(let i=0;i<dh.length;i++)dh[i]+=dy[i];let dc=this.back(c,p.O,dh,g.O,n,d,d),dq=zeros(n*d),dk=zeros(n*d),du=zeros(n*d),scale=1/Math.sqrt(d);for(let i=0;i<n;i++){let da=zeros(i+1),mean=0;for(let j=0;j<=i;j++){let v=0,a=att[i*n+j];for(let t=0;t<d;t++){v+=dc[i*d+t]*u[j*d+t];du[j*d+t]+=a*dc[i*d+t];}da[j]=v;mean+=v*a;}for(let j=0;j<=i;j++){let a=att[i*n+j]*(da[j]-mean)*scale;for(let t=0;t<d;t++){dq[i*d+t]+=a*k[j*d+t];dk[j*d+t]+=a*q[i*d+t];}}}
 let dxq=this.back(x,p.Q,dq,g.Q,n,d,d),dxk=this.back(x,p.K,dk,g.K,n,d,d),dxu=this.back(x,p.U,du,g.U,n,d,d);for(let i=0;i<n;i++)for(let j=0;j<d;j++){let ix=i*d+j,v=dh[ix]+dxq[ix]+dxk[ix]+dxu[ix];g.E[ids[i]*d+j]+=v;g.P[ix]+=v;}
 let norm=0;for(let a of Object.values(g))for(let v of a)norm+=v*v;let clip=Math.min(1,1/(Math.sqrt(norm)+1e-8));this.step++;this.optStep++;let c1=1-Math.pow(.9,this.optStep),c2=1-Math.pow(.999,this.optStep);for(let key in p){let a=p[key],m=this.m[key],v=this.v[key],b=g[key];for(let i=0;i<a.length;i++){let grad=b[i]*clip;m[i]=.9*m[i]+.1*grad;v[i]=.999*v[i]+.001*grad*grad;a[i]-=lr*(m[i]/c1)/(Math.sqrt(v[i]/c2)+1e-8);}}loss/=count;this.loss=this.loss===null?loss:.96*this.loss+.04*loss;return loss;}
 sample(history,{temperature=.75,topK=12}={}){let ids=history.slice(-this.ctx),a=this.forward(ids).logits.slice((ids.length-1)*V);a[BOS]=-Infinity;a[SEP]=-Infinity;let candidates=Array.from(a.keys()).sort((i,j)=>a[j]-a[i]).slice(0,topK);if(temperature===0)return candidates[0];let p=soft(Float32Array.from(candidates.map(i=>a[i]/temperature))),r=this.r();for(let i=0;i<p.length;i++){r-=p[i];if(r<=0)return candidates[i];}return candidates.at(-1);}
 reply(prompt,max=140,temp=.75){let h=[BOS,...encode(prompt),SEP],out=[];for(let i=0;i<max;i++){let t=this.sample(h,{temperature:temp});if(t===EOS)break;out.push(t);h.push(t);}return decode(out).trim();}
 // Function-preserving widening: keep old features isolated initially; new features can learn.
 widen(d,ctx,seed=Date.now()){
  if(![128,256].includes(d)||d<=this.d||![96,128].includes(ctx)||ctx<this.ctx)throw Error('Ampliación inválida');
  const next=new Transformer({d,ctx,seed}), old=this.d, f=this.f, nf=next.f;
  function copyRows(src,dst,rows,cols,oldStride,newStride,scale=1){for(let i=0;i<rows;i++)for(let j=0;j<cols;j++)dst[i*newStride+j]=src[i*oldStride+j]*scale;}
  copyRows(this.p.E,next.p.E,V,old,old,d);copyRows(this.p.P,next.p.P,this.ctx,old,old,d);
  // Q/K scaling compensates for attention's 1/sqrt(d). New Q block starts at zero.
  const s=Math.pow(d/old,.25);
  for(const k of ['Q','K','U','O']){
   const p=next.p[k];for(let i=0;i<d;i++)for(let j=0;j<d;j++)if((i<old)!==(j<old)||k==='Q')p[i*d+j]=0;
   copyRows(this.p[k],p,old,old,old,d,k==='Q'||k==='K'?s:1);
  }
  for(let i=0;i<d;i++)for(let j=0;j<nf;j++)if((i<old)!==(j<f))next.p.A[i*nf+j]=0;
  for(let i=0;i<nf;i++)for(let j=0;j<d;j++)if((i<f)!==(j<old))next.p.B[i*d+j]=0;
  copyRows(this.p.A,next.p.A,old,f,f,nf);copyRows(this.p.B,next.p.B,f,old,old,d);
  next.p.W.fill(0);copyRows(this.p.W,next.p.W,old,V,V,V);next.p.b.set(this.p.b);
  next.step=this.step;next.optStep=0;next.loss=this.loss;return next;
 }
 export(){let o={format:'origen-transformer-bpe-1',d:this.d,ctx:this.ctx,step:this.step,optStep:this.optStep,loss:this.loss,p:{},m:{},v:{}};for(let k in this.p)for(let q of ['p','m','v'])o[q][k]=pack(this[q][k]);return o;}
 static restore(o){if(o&&o.format==='origen-deep-bpe-2')return DeepTransformer.restore(o);if(o.format!=='origen-transformer-bpe-1'||![32,48,64,128,256].includes(o.d)||![32,64,96,128].includes(o.ctx))throw Error('Formato incompatible');let a=new Transformer(o);for(let k in a.p)for(let q of ['p','m','v']){let b=unpack(o[q]?.[k]);if(b.length!==a[q][k].length||!b.every(Number.isFinite))throw Error('Pesos dañados');a[q][k].set(b);}if(!Number.isSafeInteger(o.step)||o.step<0||!(o.loss===null||Number.isFinite(o.loss)))throw Error('Estado inválido');a.step=o.step;a.optStep=o.optStep===undefined?o.step:o.optStep;if(!Number.isSafeInteger(a.optStep)||a.optStep<0||a.optStep>a.step)throw Error('Optimizador inválido');a.loss=o.loss;return a;}
}

 // Extend the existing BPE dictionary without renumbering any learned token.
 function extendedCodec(extra=[]){
  if(!Array.isArray(extra)||extra.length>384)throw Error('Tokenizador inválido');
  const merges=MERGES.concat(extra),ex=Array.from({length:259},(_,i)=>i<256?[i]:[]),rank=new Map(),v=259+merges.length;
  for(let i=0;i<merges.length;i++){const pair=merges[i],id=i+259;if(!Array.isArray(pair)||pair.length!==2||pair.some(x=>!Number.isInteger(x)||x<0||x>=id||[BOS,EOS,SEP].includes(x)))throw Error('Merge inválido');const [a,b]=pair,key=a*2048+b;if(rank.has(key))throw Error('Merge duplicado');const bytes=ex[a].concat(ex[b]);if(bytes.length>128)throw Error('Token demasiado largo');ex.push(bytes);rank.set(key,id);}
  return {v,extra,ex,encode(str){let a=Array.from(enc.encode(str));while(a.length>1){let best=Infinity;for(let i=0;i<a.length-1;i++){let r=rank.get(a[i]*2048+a[i+1]);if(r!==undefined&&r<best)best=r;}if(best===Infinity)break;let b=[];for(let i=0;i<a.length;i++){if(i+1<a.length&&rank.get(a[i]*2048+a[i+1])===best){b.push(best);i++;}else b.push(a[i]);}a=b;}return a;},decode(a){return dec.decode(Uint8Array.from(a.flatMap(x=>ex[x]||[])));}};
 }
 function learnMerges(corpus,maxV=1024){
  const seq=[];let chars=0;for(const item of corpus){for(const raw of item.kind==='dialog'?[item.q,item.a]:[item.text]){if(typeof raw!=='string'||chars>=180000)continue;let t=raw.slice(0,Math.min(2000,180000-chars));chars+=t.length;if(t)seq.push(encode(t));}}
  const extra=[],lengths=expansion.map(x=>x.length),known=new Set(MERGES.map(([a,b])=>a*2048+b));
  while(V+extra.length<Math.min(1024,maxV)){
   const counts=new Map();for(const a of seq)for(let j=0;j<a.length-1;j++){let l=a[j],r=a[j+1],k=l*2048+r;if(lengths[l]+lengths[r]<=24&&!known.has(k))counts.set(k,(counts.get(k)||0)+1);}
   let best=-1,n=2;for(const [k,c] of counts)if(c>n){n=c;best=k;}if(best<0)break;
   const l=Math.floor(best/2048),r=best%2048,id=V+extra.length;extra.push([l,r]);known.add(best);lengths.push(lengths[l]+lengths[r]);
   for(let i=0;i<seq.length;i++){const a=seq[i],b=[];for(let j=0;j<a.length;j++){if(a[j]===l&&a[j+1]===r){b.push(id);j++;}else b.push(a[j]);}seq[i]=b;}
  }return extra;
 }
 class DeepTransformer extends Transformer{
  constructor({d=128,ctx=128,extra=[],seed=12345}={}){
   super({d,ctx,seed});if(![48,64,128,256].includes(d)||![64,96,128].includes(ctx))throw Error('Arquitectura inválida');
   this.codec=extendedCodec(extra);this.vocab=this.codec.v;this.layers=3;this.heads=4;
   const v=this.vocab,f=this.f;this.shapes={E:[v,d],P:[ctx,d],Q:[d,d],K:[d,d],U:[d,d],O:[d,d],A:[d,f],B:[f,d],W:[d,v],b:[1,v]};
   for(let l=1;l<3;l++)for(const [k,shape] of Object.entries({Q:[d,d],K:[d,d],U:[d,d],O:[d,d],A:[d,f],B:[f,d],g1:[1,d],g2:[1,d]}))this.shapes['L'+l+'_'+k]=shape;
   this.p={};this.m={};this.v={};for(const [k,[a,b]] of Object.entries(this.shapes)){let w=this.p[k]=zeros(a*b);this.m[k]=zeros(w.length);this.v[k]=zeros(w.length);if(k.endsWith('_g1')||k.endsWith('_g2'))w.fill(1);else{let scale=k==='b'?0:k==='E'||k==='P'?.12:Math.sqrt(6/(a+b));for(let i=0;i<w.length;i++)w[i]=(this.r()*2-1)*scale;}}
  }
  encode(s){return this.codec.encode(s);}decode(a){return this.codec.decode(a);}
  // RMS normalization and its exact backward derivative, with a trainable gain.
  norm(x,g,n){let d=this.d,y=zeros(x.length),r=zeros(n);for(let i=0;i<n;i++){let sum=0;for(let j=0;j<d;j++)sum+=x[i*d+j]**2;let inv=r[i]=1/Math.sqrt(sum/d+1e-5);for(let j=0;j<d;j++)y[i*d+j]=x[i*d+j]*inv*g[j];}return {y,r};}
  normBack(x,g,r,dy,dg,n){let d=this.d,dx=zeros(x.length);for(let i=0;i<n;i++){let dot=0,inv=r[i];for(let j=0;j<d;j++){let z=i*d+j;dot+=dy[z]*g[j]*x[z];dg[j]+=dy[z]*x[z]*inv;}for(let j=0;j<d;j++){let z=i*d+j;dx[z]=dy[z]*g[j]*inv-x[z]*dot*inv**3/d;}}return dx;}
  block(x,n,l){let d=this.d,f=this.f,p=this.p,pre=l?'L'+l+'_':'',heads=l?this.heads:1,hd=d/heads,sc=1/Math.sqrt(hd);
   let a=l?this.norm(x,p[pre+'g1'],n):{y:x,r:null},q=this.mm(a.y,p[pre+'Q'],n,d,d),k=this.mm(a.y,p[pre+'K'],n,d,d),u=this.mm(a.y,p[pre+'U'],n,d,d),att=zeros(heads*n*n),c=zeros(n*d);
   for(let h=0;h<heads;h++)for(let i=0;i<n;i++){let scores=zeros(i+1),off=h*hd;for(let j=0;j<=i;j++){let z=0;for(let t=0;t<hd;t++)z+=q[i*d+off+t]*k[j*d+off+t];scores[j]=z*sc;}soft(scores);for(let j=0;j<=i;j++){let w=scores[j];att[(h*n+i)*n+j]=w;for(let t=0;t<hd;t++)c[i*d+off+t]+=w*u[j*d+off+t];}}
   let y=this.mm(c,p[pre+'O'],n,d,d);for(let i=0;i<y.length;i++)y[i]+=x[i];let b=l?this.norm(y,p[pre+'g2'],n):{y,r:null},z=this.mm(b.y,p[pre+'A'],n,d,f);for(let i=0;i<z.length;i++)z[i]=Math.tanh(z[i]);let out=this.mm(z,p[pre+'B'],n,f,d);for(let i=0;i<out.length;i++)out[i]+=y[i];
   return {x,a,q,k,u,att,c,y,b,z,out,pre,heads,hd};
  }
  blockBack(s,dy,g,n){let {x,a,q,k,u,att,c,y,b,z,pre,heads,hd}=s,d=this.d,f=this.f,p=this.p;
   let dz=this.back(z,p[pre+'B'],dy,g[pre+'B'],n,f,d);for(let i=0;i<dz.length;i++)dz[i]*=1-z[i]**2;
   let dh=this.back(b.y,p[pre+'A'],dz,g[pre+'A'],n,d,f);if(b.r)dh=this.normBack(y,p[pre+'g2'],b.r,dh,g[pre+'g2'],n);for(let i=0;i<dh.length;i++)dh[i]+=dy[i];
   let dc=this.back(c,p[pre+'O'],dh,g[pre+'O'],n,d,d),dq=zeros(n*d),dk=zeros(n*d),du=zeros(n*d),sc=1/Math.sqrt(hd);
   for(let h=0;h<heads;h++)for(let i=0;i<n;i++){let da=zeros(i+1),mean=0,off=h*hd;for(let j=0;j<=i;j++){let z=0,w=att[(h*n+i)*n+j];for(let t=0;t<hd;t++){let ii=i*d+off+t,jj=j*d+off+t;z+=dc[ii]*u[jj];du[jj]+=w*dc[ii];}da[j]=z;mean+=z*w;}for(let j=0;j<=i;j++){let w=att[(h*n+i)*n+j]*(da[j]-mean)*sc;for(let t=0;t<hd;t++){let ii=i*d+off+t,jj=j*d+off+t;dq[ii]+=w*k[jj];dk[jj]+=w*q[ii];}}}
   let dx=this.back(a.y,p[pre+'Q'],dq,g[pre+'Q'],n,d,d),dxk=this.back(a.y,p[pre+'K'],dk,g[pre+'K'],n,d,d),dxu=this.back(a.y,p[pre+'U'],du,g[pre+'U'],n,d,d);for(let i=0;i<dx.length;i++)dx[i]+=dxk[i]+dxu[i];if(a.r)dx=this.normBack(x,p[pre+'g1'],a.r,dx,g[pre+'g1'],n);for(let i=0;i<dx.length;i++)dx[i]+=dh[i];return dx;
  }
  forward(ids){let n=ids.length,d=this.d,v=this.vocab,p=this.p,x=zeros(n*d);if(n<1||n>this.ctx)throw Error('Contexto inválido');for(let i=0;i<n;i++)for(let j=0;j<d;j++)x[i*d+j]=p.E[ids[i]*d+j]+p.P[i*d+j];let blocks=[];for(let l=0;l<this.layers;l++){let s=this.block(x,n,l);blocks.push(s);x=s.out;}let logits=this.mm(x,p.W,n,d,v);for(let i=0;i<n;i++)for(let j=0;j<v;j++)logits[i*v+j]+=p.b[j];return {n,y:x,blocks,logits};}
  train(ids,targets,lr=.001){let {n,y,blocks,logits}=this.forward(ids),d=this.d,v=this.vocab,p=this.p,g={};for(let k in p)g[k]=zeros(p[k].length);let dl=zeros(n*v),loss=0,count=targets.filter(t=>t>=0).length;if(!count)return null;
   for(let i=0;i<n;i++){let t=targets[i];if(t<0)continue;let prob=soft(logits.slice(i*v,(i+1)*v));loss-=Math.log(Math.max(1e-12,prob[t]));for(let j=0;j<v;j++){let z=(prob[j]-(j===t?1:0))/count;dl[i*v+j]=z;g.b[j]+=z;}}
   let dx=this.back(y,p.W,dl,g.W,n,d,v);for(let l=blocks.length-1;l>=0;l--)dx=this.blockBack(blocks[l],dx,g,n);
   for(let i=0;i<n;i++)for(let j=0;j<d;j++){let z=i*d+j;g.E[ids[i]*d+j]+=dx[z];g.P[z]+=dx[z];}
   let norm=0;for(let a of Object.values(g))for(let z of a)norm+=z*z;if(!Number.isFinite(norm)||!Number.isFinite(loss))throw Error('Gradiente no finito; entrenamiento detenido');
   let clip=Math.min(1,1/(Math.sqrt(norm)+1e-8));this.step++;this.optStep++;let c1=1-Math.pow(.9,this.optStep),c2=1-Math.pow(.999,this.optStep);
   for(let key in p){let a=p[key],m=this.m[key],vv=this.v[key],b=g[key];for(let i=0;i<a.length;i++){let grad=b[i]*clip;m[i]=.9*m[i]+.1*grad;vv[i]=.999*vv[i]+.001*grad*grad;a[i]-=lr*(m[i]/c1)/(Math.sqrt(vv[i]/c2)+1e-8);}}
   loss/=count;this.loss=this.loss===null?loss:.96*this.loss+.04*loss;return loss;
  }
  sample(history,{temperature=.75,topK=12}={}){let ids=history.slice(-this.ctx),v=this.vocab,a=this.forward(ids).logits.slice((ids.length-1)*v);a[BOS]=-Infinity;a[SEP]=-Infinity;let c=Array.from(a.keys()).sort((i,j)=>a[j]-a[i]).slice(0,topK);if(temperature===0)return c[0];let p=soft(Float32Array.from(c.map(i=>a[i]/temperature))),r=this.r();for(let i=0;i<p.length;i++){r-=p[i];if(r<=0)return c[i];}return c.at(-1);}
  reply(prompt,max=48,temp=.45){let h=[BOS,...this.encode(prompt).slice(-(this.ctx-2)),SEP],out=[];for(let i=0;i<max;i++){let t=this.sample(h,{temperature:temp});if(t===EOS)break;out.push(t);h.push(t);}return this.decode(out).trim();}
  widen(){throw Error('El modelo de tres capas ya usa su arquitectura avanzada.');}
  export(){let o=super.export();o.format='origen-deep-bpe-2';o.extra=this.codec.extra;return o;}
  static restore(o){let a=new DeepTransformer({d:o.d,ctx:o.ctx,extra:o.extra});for(let k in a.p)for(let q of ['p','m','v']){let b=unpack(o[q]?.[k]);if(b.length!==a[q][k].length||!b.every(Number.isFinite))throw Error('Pesos dañados');a[q][k].set(b);}if(!Number.isSafeInteger(o.step)||o.step<0||!Number.isSafeInteger(o.optStep)||o.optStep<0||o.optStep>o.step||!(o.loss===null||Number.isFinite(o.loss)))throw Error('Estado inválido');a.step=o.step;a.optStep=o.optStep;a.loss=o.loss;return a;}
  static upgrade(old,corpus,maxV=1024,seed=Date.now()){
   if(old instanceof DeepTransformer)throw Error('Ya usa tres capas');const next=new DeepTransformer({d:old.d,ctx:old.ctx,extra:learnMerges(corpus,maxV),seed}),d=old.d,v=next.vocab;
   for(let key of ['P','Q','K','U','O','A','B'])next.p[key].set(old.p[key]);
   next.p.E.set(old.p.E);for(let i=0;i<d;i++)next.p.W.set(old.p.W.subarray(i*V,(i+1)*V),i*v);next.p.b.set(old.p.b);
   // New BPE tokens start from constituent embeddings; output columns need training.
   for(let id=V;id<v;id++){let [a,b]=next.codec.extra[id-V];for(let j=0;j<d;j++){next.p.E[id*d+j]=(next.p.E[a*d+j]+next.p.E[b*d+j])/2;next.p.W[j*v+id]=(next.p.W[j*v+a]+next.p.W[j*v+b])/2;}next.p.b[id]=-4;}
   // Both residual blocks start as identity; old network is retained, Adam reset.
   for(let l=1;l<3;l++){next.p['L'+l+'_O'].fill(0);next.p['L'+l+'_B'].fill(0);}
   next.step=old.step;next.optStep=0;next.loss=null;return next;
  }
 }
 const deepCache=new WeakMap();
 function deepExample(model,item,random=Math.random){
  let entry=deepCache.get(item);if(!entry||entry.codec!==model.codec){entry={codec:model.codec,q:item.kind==='dialog'?model.encode(item.q):null,r:model.encode(item.kind==='dialog'?item.a:item.text)};deepCache.set(item,entry);}
  const {q,r}=entry,ctx=model.ctx;
  if(item.kind==='dialog'){let prompt=q.slice(-Math.min(q.length,Math.floor(ctx*.65))),room=ctx-prompt.length-2;let answer=r.slice(0,room);let seq=[BOS,...prompt,SEP,...answer];if(answer.length===r.length)seq.push(EOS);let ids=seq.slice(0,-1),targets=seq.slice(1).map((t,i)=>i>=prompt.length+1?t:-1);return targets.some(t=>t>=0)?[ids,targets]:null;}
  let seq=[BOS,...r,EOS],start=Math.max(0,Math.floor(random()*Math.max(1,seq.length-ctx)));let ids=seq.slice(start,start+ctx),targets=seq.slice(start+1,start+ctx+1);return targets.length?[ids.slice(0,targets.length),targets]:null;
 }
 function referenceLoss(model,items){let sum=0,n=0;for(const item of items){const ex=example(model,item,()=>0);if(!ex)continue;let logits=model.forward(ex[0]).logits,v=model.vocab||V;for(let i=0;i<ex[1].length;i++){let t=ex[1][i];if(t<0)continue;let p=soft(logits.slice(i*v,(i+1)*v));sum-=Math.log(Math.max(1e-12,p[t]));n++;}}return n?sum/n:null;}

const cached=new WeakMap();
function example(model,item,random=Math.random){if(model instanceof DeepTransformer)return deepExample(model,item,random);let a,mask;let c=cached.get(item);if(c){({a,mask}=c);}else if(item.kind==='dialog'){let q=encode(item.q),r=encode(item.a);a=[BOS,...q,SEP,...r,EOS];mask=q.length+2; // first answer token at index mask
}else{a=[BOS,...encode(item.text),EOS];mask=1;}
 if(!c)cached.set(item,{a,mask});
 let last=a.length-1;if(last<1)return null;let start=0;if(last>model.ctx){let min=item.kind==='dialog'?Math.max(0,mask-model.ctx):0;let max=last-model.ctx;start=min>max?max:min+Math.floor(random()*(max-min+1));}let ids=a.slice(start,start+model.ctx),targets=a.slice(start+1,start+1+model.ctx);ids=ids.slice(0,targets.length);targets=targets.map((t,i)=>start+i+1>=mask?t:-1);if(!targets.some(x=>x>=0))return null;return [ids,targets];}
const api={Transformer,DeepTransformer,encode,decode,example,referenceLoss,BOS,EOS,SEP,V};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.Origen=api;
})(typeof globalThis!=='undefined'?globalThis:this);
