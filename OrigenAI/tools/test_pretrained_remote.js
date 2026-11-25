'use strict';
const fs=require('node:fs'),assert=require('node:assert/strict'),vm=require('node:vm');
const script=fs.readFileSync('app/src/main/assets/pretrained_remote.js','utf8');
const markup=fs.readFileSync('app/src/main/assets/index.html','utf8');
for(const id of ['preRemoteAuto','preRemoteState','preRemoteAnswers','preRemoteCheck','preRemoteOpenSync'])
  assert(markup.includes('id="'+id+'"'),id+' UI missing');
assert(markup.includes('<script src="pretrained_remote.js"></script>'));
new vm.Script(script);
assert(script.includes("pre_pull"));
assert(script.includes("pre_push"));
assert(script.includes("window.origenRemoteInfer"));
assert(script.includes("window.origenRemoteSave"));
assert(!script.includes('config.messages'));
assert(!script.includes('config.examples'));
console.log('GitHub pretrained remote UI, isolation and request protocol checked');
