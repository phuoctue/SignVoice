const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {webcrypto} = require('node:crypto');

function hand(x=.3) {
  return Array.from({length:21}, (_,i)=>({x:x+i*.005,y:.4+i*.007,z:-i*.001}));
}

test('small tracks require two fresh pixel failures, preserve verified still hands, default stays unchanged',async()=>{
  const small=hand().map(p=>({x:.8+(p.x-.3)*.3,y:.5+(p.y-.4)*.3,z:p.z*.3}));
  const frame=(timestamp)=>({data:{type:'frame',timestamp,frame:{width:640,height:480,close(){}}}});
  const baseline=await worker([small],[],null,true,false,2,false,{enable_recovery:false});
  await baseline.self.onmessage(frame(0));
  assert.equal(baseline.messages.at(-1).value.hand_observation.landmarks.length,1);
  const w=await worker([small],[],null,true,false,2,false,{enable_recovery:false,verify_small_tracks:true});
  for(const stamp of [0,500,1000,1100]) {await w.self.onmessage(frame(stamp));await new Promise(r=>setImmediate(r));}
  assert.equal(w.messages.at(-1).value.hand_observation.landmarks.length,0);
  assert.equal(w.messages.at(-1).value.hand_observation.track_verification.rejected,1);
  assert.ok(w.calls.some(c=>c[0]==='image'));
  const real=await worker([small,hand(.2)],[small,hand(.2)],null,true,false,2,false,{enable_recovery:false,verify_small_tracks:true});
  for(const stamp of [0,500,1000,1100]) {await real.self.onmessage(frame(stamp));await new Promise(r=>setImmediate(r));}
  assert.equal(real.messages.at(-1).value.hand_observation.landmarks.length,2);
});

test('verified large hands remain while every size receives periodic pixel checks',async()=>{
  const w=await worker([hand(),hand(.7)],[hand(),hand(.7)],null,true,false,2,false,{enable_recovery:false,verify_small_tracks:true});
  for(const timestamp of [0,500,1000,1100]) {await w.self.onmessage({data:{type:'frame',timestamp,frame:{width:640,height:480,close(){}}}});await new Promise(r=>setImmediate(r));}
  assert.equal(w.messages.at(-1).value.hand_observation.landmarks.length,2);
  assert.ok(w.calls.filter(c=>c[0]==='image').length>=2);
  assert.equal(w.messages.at(-1).value.hand_observation.track_verification.scope,'all_tracks');
});

test('stationary unconfirmed tracks above the old size cutoff are checked and rejected',async()=>{
  const w=await worker([hand(.8)],[],null,true,false,2,false,{enable_recovery:false,verify_small_tracks:true});
  for(const timestamp of [0,500,1000,1100]) {await w.self.onmessage({data:{type:'frame',timestamp,frame:{width:640,height:480,close(){}}}});await new Promise(r=>setImmediate(r));}
  assert.equal(w.messages.at(-1).value.hand_observation.landmarks.length,0);
});

test('fresh confirmation restores a previously rejected track and resets its misses',async()=>{
  const recovered=[];const w=await worker([hand(.8)],recovered,null,true,false,2,false,{enable_recovery:false,verify_small_tracks:true});
  const frame=async timestamp=>{await w.self.onmessage({data:{type:'frame',timestamp,frame:{width:640,height:480,close(){}}}});await new Promise(r=>setImmediate(r));};
  for(const stamp of [0,500,1000,1100])await frame(stamp);
  assert.equal(w.messages.at(-1).value.hand_observation.landmarks.length,0);
  recovered.push(hand(.8));await frame(1500);await frame(1600);
  assert.equal(w.messages.at(-1).value.hand_observation.landmarks.length,1);
  recovered.length=0;await frame(2000);await frame(2100);
  assert.equal(w.messages.at(-1).value.hand_observation.landmarks.length,1);
});

test('slow independent validation cannot block previews or accumulate camera snapshots',async()=>{
  let release;const verifierGate=new Promise(resolve=>{release=resolve;});
  const small=hand().map(p=>({x:.8+(p.x-.3)*.3,y:.5+(p.y-.4)*.3,z:p.z*.3}));
  const w=await worker([small],[],null,true,false,2,false,{enable_recovery:false,verify_small_tracks:true,verifierGate});
  for(const timestamp of [0,500,600,700,800,900]) {
    await w.self.onmessage({data:{type:'frame',timestamp,frame:{width:640,height:480,close(){}}}});
    await new Promise(r=>setImmediate(r));
  }
  assert.equal(w.messages.filter(m=>m.value.type==='preview').length,6);
  assert.equal(w.calls.filter(c=>c[0]==='image').length,1);
  release();await new Promise(r=>setImmediate(r));
});

test('independent validator uses CPU IMAGE on the supplied pixels and closes failed frames',async()=>{
  const sent=[],options=[];
  const self={postMessage:value=>sent.push(value)};
  const fakeLibrary={HandLandmarker:{createFromOptions:async(files,value)=>{
    options.push(value);return {detect:bitmap=>{if(bitmap.fail)throw Error('bad frame');return {landmarks:[hand()]};}};
  }}};
  const source=fs.readFileSync(__dirname+'/../web/signvoice_hand_verifier.js','utf8')
    .replace("import('./mediapipe/vision_bundle.js?v=8.2')",'Promise.resolve(fakeLibrary)');
  vm.runInNewContext(source,{self,fakeLibrary,Uint8Array,performance});
  await self.onmessage({data:{type:'init',files:{},model:new ArrayBuffer(4)}});
  assert.equal(options[0].runningMode,'IMAGE');assert.equal(options[0].baseOptions.delegate,'CPU');
  const good={closed:false,close(){this.closed=true;}},bad={...good,fail:true};
  await self.onmessage({data:{type:'frame',frame:good}});
  await self.onmessage({data:{type:'frame',frame:bad}});
  assert.ok(good.closed && bad.closed);assert.equal(sent[1].landmarks.length,1);assert.equal(sent[2].type,'error');
});

test('verification failure clears old rejections; moved or enlarged hands are not quarantined',async()=>{
  const small=hand().map(p=>({x:.8+(p.x-.3)*.3,y:.5+(p.y-.4)*.3,z:p.z*.3}));
  const primary=[small];
  const w=await worker(primary,[],null,true,false,2,false,{enable_recovery:false,verify_small_tracks:true});
  const frame=timestamp=>w.self.onmessage({data:{type:'frame',timestamp,frame:{width:640,height:480,close(){}}}});
  for(const stamp of [0,500,1000,1100]) {await frame(stamp);await new Promise(r=>setImmediate(r));}
  assert.equal(w.messages.at(-1).value.hand_observation.landmarks.length,0);
  assert.equal(w.messages.at(-1).value.recovered_hands,0);
  vm.runInContext("verifier={detect(){throw new Error('validation failed')}}",w.scope);
  await frame(1500);await new Promise(r=>setImmediate(r));await frame(1600);
  assert.equal(w.messages.at(-1).value.hand_observation.landmarks.length,1);
  assert.match(w.messages.at(-1).value.hand_observation.track_verification.error,/validation failed/);
  primary[0]=hand(.7);
  await frame(1700);
  assert.equal(w.messages.at(-1).value.hand_observation.landmarks.length,1);
});

async function worker(primary=[], recovered=[], jpegGate=null, earlyPreview=true, independentEncode=false, targetHands=2, failGpu=false, initOptions={}) {
  const messages=[], calls=[], created=[], snapshots=[];
  const result = points=>({landmarks:points.map(h=>h.map(p=>({...p}))),
    handedness:points.map(()=>[{categoryName:'Left'}])});
  const fakeLibrary={FilesetResolver:{forVisionTasks:async()=>{await initOptions.filesGate;return {}; }},
    HandLandmarker:{createFromOptions:async(files,options)=>{
      created.push(options);
      if (failGpu && options.baseOptions.delegate === 'GPU') throw new Error('GPU unsupported');
      return {detectForVideo:(_,stamp)=>{calls.push(['video',stamp]);return result(primary);},
        detect:()=>{calls.push(['image']);return result(recovered);}};
    }}};
  class VerificationWorker {
    postMessage(data){
      if(data.type==='init') Promise.resolve().then(()=>this.onmessage({data:{type:'ready'}}));
      else if(data.type==='frame') {
        calls.push(['image']);
        Promise.resolve(initOptions.verifierGate).then(()=>{
          data.frame.close();this.onmessage({data:{type:'result',landmarks:result(recovered).landmarks}});
        });
      }
    }
    terminate(){}
  }
  class Canvas {
    constructor(w,h){this.width=w;this.height=h;}
    getContext(type){return type==='2d'?{drawImage:(image)=>{this.id=image.id;}}:null;}
    transferToImageBitmap(){const bitmap={id:this.id,closed:false,close(){this.closed=true;}};snapshots.push(bitmap);return bitmap;}
    async convertToBlob(options){if(options?.type==='image/png' && initOptions.pngFailure) throw new Error('PNG unsupported');const id=this.id;if(jpegGate) await jpegGate;return {arrayBuffer:async()=>{
      const bytes=new ArrayBuffer(16);new Uint8Array(bytes)[0]=id ?? 0;return bytes;}};}
  }
  const self={location:{href:'http://localhost/signvoice_hand_worker.js'},
    postMessage:m=>messages.push({...m,value:JSON.parse(m.meta)})};
  const scope=vm.createContext({self,URL,crypto:webcrypto,performance,setTimeout,clearTimeout,AbortController,OffscreenCanvas:Canvas,Worker:VerificationWorker,
    Uint8Array,ArrayBuffer,fetch:async (url,options)=>{initOptions.fetches?.push(String(url));
      if(initOptions.fetchAsset) return initOptions.fetchAsset(String(url),options);
      return {ok:options?.cache!=='only-if-cached',arrayBuffer:async()=>new ArrayBuffer(4)};},fakeLibrary});
  const source=fs.readFileSync(__dirname+'/../web/signvoice_hand_worker.js','utf8')
    .replace("import('./mediapipe/vision_bundle.js?v=8.2')",'Promise.resolve(fakeLibrary)');
  vm.runInContext(source,scope);
  await self.onmessage({data:{type:'init',early_preview:earlyPreview,independent_encode:independentEncode,target_hands:targetHands,...initOptions}});
  assert.ok(messages.some(m=>m.value.type==='ready'),JSON.stringify(messages.map(m=>m.value)));
  return {self,messages,calls,created,snapshots,scope};
}

test('PNG capture is opt-in, exact-frame paired, sampled and bounded',async()=>{
  const off=await worker([hand()]);
  await off.self.onmessage({data:{type:'frame',timestamp:0,frame:{id:3,width:640,height:480,close(){}}}});
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(off.messages.filter(m=>m.value.type==='diagnostic_pixels').length,0);
  const on=await worker([hand()],[],null,true,true,2,false,{diagnostic_pixels:true});
  for(let i=0;i<125;i++) {
    await on.self.onmessage({data:{type:'frame',timestamp:i*250,frame:{id:i,width:640,height:480,close(){}}}});
    await new Promise(resolve=>setImmediate(resolve));
  }
  const pngs=on.messages.filter(m=>m.value.type==='diagnostic_pixels');
  assert.equal(pngs.length,15);
  for(const png of pngs) {
    assert.equal(png.value.timestamp_ms,png.value.hand_observation.timestamp_ms);
    assert.equal(png.value.pixel_stage,'resized_detector_input');
    assert.equal(png.value.mirrored,false);
    assert.equal(new Uint8Array(png.jpeg)[0],png.value.timestamp_ms/250);
    assert.deepEqual(png.value.raw_landmarks,png.value.hand_observation.landmarks);
  }
});

test('stop command prevents further local PNG work without disabling tracking',async()=>{
  const w=await worker([hand()],[],null,true,true,2,false,{diagnostic_pixels:true});
  await w.self.onmessage({data:{type:'stop_diagnostic_pixels'}});
  await w.self.onmessage({data:{type:'frame',timestamp:0,frame:{width:640,height:480,close(){}}}});
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(w.messages.filter(m=>m.value.type==='diagnostic_pixels').length,0);
  assert.ok(w.messages.some(m=>m.value.type==='preview'));
  assert.ok(w.messages.some(m=>m.value.type==='tracking'));
});

test('PNG encoder failure reports diagnostic error while recognition keeps running',async()=>{
  const w=await worker([hand()],[],null,true,true,2,false,{diagnostic_pixels:true,pngFailure:true});
  await w.self.onmessage({data:{type:'frame',timestamp:0,frame:{width:640,height:480,close(){}}}});
  await new Promise(resolve=>setImmediate(resolve));
  assert.ok(w.messages.some(m=>m.value.type==='diagnostic_error'));
  assert.ok(w.messages.some(m=>m.value.type==='tracking'));
  assert.ok(w.messages.some(m=>m.value.type==='preview'));
  assert.equal(w.messages.filter(m=>m.value.type==='unavailable').length,0);
});

test('measured preview arrives before a delayed JPEG; paired inference frame still waits',async()=>{
  let finish;const gate=new Promise(resolve=>{finish=resolve;});
  const w=await worker([hand()],[],gate);
  const pending=w.self.onmessage({data:{type:'frame',timestamp:0,frame:{width:640,height:480,close(){}}}});
  await Promise.resolve();
  const preview=w.messages.find(m=>m.value.type==='preview');
  assert.ok(preview);assert.equal(preview.value.landmarks.length,1);
  assert.equal(preview.jpeg,undefined);
  assert.equal(w.messages.filter(m=>m.value.type==='tracking').length,0);
  finish();await pending;
  const paired=w.messages.find(m=>m.value.type==='tracking');
  assert.equal(paired.value.timestamp,preview.value.timestamp);
  assert.equal(paired.jpeg.byteLength,16);
});

test('older clients get only their existing tracking message until they opt into previews',async()=>{
  const w=await worker([hand()],[],null,false);
  await w.self.onmessage({data:{type:'frame',timestamp:0,frame:{width:640,height:480,close(){}}}});
  assert.equal(w.messages.filter(m=>m.value.type==='preview').length,0);
  assert.equal(w.messages.filter(m=>m.value.type==='tracking').length,1);
});

test('glyph XYZ is available before JPEG compression finishes',async()=>{
  let finish;const gate=new Promise(resolve=>{finish=resolve;});
  const w=await worker([hand()],[],gate,true,true,1,false,{temporal_history:true});
  const pending=w.self.onmessage({data:{type:'frame',timestamp:123,frame:{width:640,height:480,close(){}}}});
  await Promise.resolve();await Promise.resolve();
  const preview=w.messages.find(m=>m.value.type==='preview').value;
  assert.equal(preview.hand_observation.timestamp_ms,123);
  assert.equal(preview.hand_observation.landmarks[0][0].length,3);
  assert.equal(preview.hand_observation.handedness[0],'Left');
  assert.equal(w.messages.filter(m=>m.value.type==='tracking').length,0);
  finish();await pending;
});

test('word mode emits both measured hands without needing glyph history or JPEG',async()=>{
  let finish;const gate=new Promise(resolve=>{finish=resolve;});
  const w=await worker([hand(.2),hand(.65)],[],gate,true,true,2,false,{live_observations:true});
  const pending=w.self.onmessage({data:{type:'frame',timestamp:123,frame:{width:640,height:480,close(){}}}});
  await Promise.resolve();await Promise.resolve();
  const preview=w.messages.find(m=>m.value.type==='preview').value;
  assert.equal(preview.hand_observation.landmarks.length,2);
  assert.equal(preview.hand_observation.timestamp_ms,123);
  assert.equal(w.messages.filter(m=>m.value.type==='tracking').length,0);
  finish();await pending;
});

test('native stream keeps capture timestamps, matching XYZ/JPEG, and releases every frame',async()=>{
  const w=await worker([hand()]);let index=0,closed=0,cancelled=0,released=0;
  const times=[9000000,9033333,9033333,9066667];
  const readable={getReader:()=>({read:async()=>index===times.length?{done:true}:
    {value:{timestamp:times[index++],displayWidth:640,displayHeight:480,close(){closed++;}}},
    cancel:async()=>{cancelled++;},releaseLock(){released++;}})};
  await w.self.onmessage({data:{type:'camera_stream',readable,timestamp:2000}});
  const rows=w.messages.filter(m=>m.value.type==='tracking');
  assert.deepEqual(rows.map(m=>m.value.timestamp),[2000,2033,2067]);
  for(const {value:m,jpeg} of rows){
    assert.equal(m.capture_source,'track_processor');
    assert.equal(m.hand_observation.timestamp_ms,m.timestamp);
    assert.equal(m.hand_observation.width,m.width);
    assert.equal(m.hand_observation.landmarks[0].length,21);
    assert.equal(jpeg.byteLength,16);
  }
  assert.equal(closed,4);assert.equal(cancelled,1);assert.equal(released,1);
});

test('failed recovery backs off while primary observations keep running',async()=>{
  const w=await worker();let closed=0;
  for(let stamp=0;stamp<=2000;stamp+=67){
    await w.self.onmessage({data:{type:'frame',timestamp:stamp,
      frame:{width:640,height:480,close(){closed++;}}}});
  }
  assert.equal(w.calls.filter(c=>c[0]==='video').length,30);
  assert.ok(w.calls.filter(c=>c[0]==='image').length<=4);
  assert.equal(closed,30);
});

test('recovery does not duplicate a primary hand or invent missing observations',async()=>{
  const w=await worker([hand()],[hand()]);
  await w.self.onmessage({data:{type:'frame',timestamp:0,frame:{width:640,height:480,close(){}}}});
  const m=w.messages.at(-1).value;
  assert.equal(m.hand_observation.landmarks.length,1);
  assert.equal(m.recovered_hands,0);
  assert.equal(m.hand_observation.handedness.length,1);
});

test('a different current-pixel hand is merged with its matching handedness',async()=>{
  const w=await worker([hand()],[hand(.7)]);
  await w.self.onmessage({data:{type:'frame',timestamp:0,frame:{width:640,height:480,close(){}}}});
  const m=w.messages.at(-1).value;
  assert.equal(m.hand_observation.landmarks.length,2);
  assert.equal(m.recovered_hands,1);
  assert.equal(m.hand_observation.handedness.length,2);
});

test('duplicate primary outputs do not become false two-hand evidence',async()=>{
  const w=await worker([hand(),hand()]);
  await w.self.onmessage({data:{type:'frame',timestamp:0,frame:{width:640,height:480,close(){}}}});
  assert.equal(w.messages.at(-1).value.hand_observation.landmarks.length,1);
});

test('foreground face scale retains a folded hand and excludes background hands before recovery',async()=>{
  const small=hand().map(p=>({x:.5+(p.x-.3)*.12,y:.4+(p.y-.4)*.12,z:p.z*.12}));
  const w=await worker([small,hand(.95)]);
  await w.self.onmessage({data:{type:'context',anchor:[.5,.2,.1,1],timestamp:0}});
  await w.self.onmessage({data:{type:'frame',timestamp:30,frame:{width:640,height:480,close(){}}}});
  const m=w.messages.at(-1).value;
  assert.equal(m.hand_observation.landmarks.length,1);
  assert.equal(m.landmarks.length,1);
  assert.equal(m.hand_observation.landmarks[0][0][0],.5);
  assert.equal(m.recovery_ran,true);
});


test('slow JPEG cannot stall detection; active + newest snapshots retain matching timestamps/pixels', async()=>{
  let finish; const gate=new Promise(resolve=>{finish=resolve;});
  const w=await worker([hand()],[],gate,true,true);
  let closed=0;
  for(let id=1;id<=6;id++) {
    await w.self.onmessage({data:{type:'frame',timestamp:id*33,
      frame:{id,width:640,height:480,close(){closed++;}}}});
  }
  assert.equal(w.messages.filter(m=>m.value.type==='preview').length,6);
  assert.equal(w.calls.filter(c=>c[0]==='video').length,6);
  assert.equal(w.messages.filter(m=>m.value.type==='tracking').length,0);
  assert.equal(closed,6);
  assert.ok(w.snapshots.slice(0,5).every(b=>b.closed));
  finish(); await new Promise(resolve=>setImmediate(resolve));
  const encoded=w.messages.filter(m=>m.value.type==='tracking');
  assert.deepEqual(encoded.map(m=>m.value.timestamp),[33,198]);
  assert.deepEqual(encoded.map(m=>new Uint8Array(m.jpeg)[0]),[1,6]);
  assert.ok(w.snapshots.every(b=>b.closed));
  assert.ok(encoded.every(m=>m.value.timestamp===m.value.hand_observation.timestamp_ms));
});

test('digit/letter mode does not spend recovery time searching for an unused second hand', async()=>{
  const w=await worker([hand()],[],null,true,true,1);
  for(let t=0;t<1000;t+=34) await w.self.onmessage({data:{type:'frame',timestamp:t,
    frame:{width:640,height:480,close(){}}}});
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(w.calls.filter(c=>c[0]==='image').length,0);
  assert.equal(w.calls.filter(c=>c[0]==='video').length,30);
});

test('GPU-disabled browser keeps local CPU tracking and marks same-frame metadata truthfully', async()=>{
  const w=await worker([hand()],[],null,true,false,2,true);
  assert.equal(w.messages[0].value.delegate,'CPU');
  await w.self.onmessage({data:{type:'frame',timestamp:1,frame:{width:640,height:480,close(){}}}});
  const result=w.messages.at(-1).value;
  assert.equal(result.hand_observation.platform,'web');
  assert.equal(result.hand_observation.delegate,'cpu');
  assert.equal(result.hand_observation.landmarks.length,1);
  assert.equal(result.recovery_ran,false);
});


test('a saturated direct camera stream yields task turns for JPEG completion and control messages', async()=>{
  const w=await worker([hand()],[],null,true,true);
  let index=0;
  const readable={getReader:()=>({read:async()=>index===5?{done:true}:
    {value:{id:++index,timestamp:index*33000,displayWidth:640,displayHeight:480,close(){}}},
    cancel:async()=>{},releaseLock(){}})};
  await w.self.onmessage({data:{type:'camera_stream',readable,timestamp:0}});
  assert.equal(w.messages.filter(m=>m.value.type==='preview').length,5);
  assert.ok(w.messages.filter(m=>m.value.type==='tracking').length>=2);
});

test('cold-start mode initializes only the primary detector and reports elapsed setup separately',async()=>{
  const w=await worker([hand()],[],null,true,true,2,false,{enable_recovery:false,startup_progress:true});
  assert.equal(w.created.length,1);
  const ready=w.messages.find(m=>m.value.type==='ready').value;
  assert.equal(ready.recovery_enabled,false);assert.ok(ready.init_ms>=0);
  assert.deepEqual(w.messages.filter(m=>m.value.type==='init_progress').map(m=>m.value.phase),
    ['runtime','model','primary_detector']);
  await w.self.onmessage({data:{type:'frame',timestamp:1000,frame:{width:640,height:480,close(){}}}});
  await new Promise(resolve=>setImmediate(resolve));
  const tracked=w.messages.find(m=>m.value.type==='tracking').value;
  assert.equal(tracked.recovery_ran,false);
  assert.equal(tracked.hand_observation.init_ms,ready.init_ms);
  assert.ok(tracked.hand_observation.processing_ms>=0);
});

test('model download starts while runtime resolution is still pending',async()=>{
  let release;const filesGate=new Promise(resolve=>{release=resolve;});const fetches=[];
  const pending=worker([],[],null,true,true,2,false,{enable_recovery:false,filesGate,fetches});
  await new Promise(resolve=>setImmediate(resolve));
  try { assert.ok(fetches.some(url=>url.includes('hand_landmarker.task'))); }
  finally { release(); await pending; }
});

test('two separately measured hands near each other are not merged into one',async()=>{
  const w=await worker([hand(.3),hand(.33)],[],null,true,false,2,false,{enable_recovery:false});
  await w.self.onmessage({data:{type:'frame',timestamp:1,frame:{width:640,height:480,close(){}}}});
  assert.equal(w.messages.at(-1).value.hand_observation.landmarks.length,2);
});

test('a raised hand beside the face stays visible when switching from one to two hands',async()=>{
  const points=[hand(.4)];
  const w=await worker(points,[],null,true,false,2,false,{enable_recovery:false});
  await w.self.onmessage({data:{type:'context',anchor:[.5,.2,.1,1],timestamp:0}});
  await w.self.onmessage({data:{type:'frame',timestamp:1,frame:{width:640,height:480,close(){}}}});
  assert.equal(w.messages.at(-1).value.landmarks.length,1);
  points.push(hand(.82));
  await w.self.onmessage({data:{type:'frame',timestamp:34,frame:{width:640,height:480,close(){}}}});
  assert.equal(w.messages.at(-1).value.landmarks.length,2);
  points.pop();
  await w.self.onmessage({data:{type:'frame',timestamp:67,frame:{width:640,height:480,close(){}}}});
  assert.equal(w.messages.at(-1).value.landmarks.length,1);
});

test('a folded hand is not lost merely because face context has expired',async()=>{
  const small=hand().map(p=>({x:.5+(p.x-.3)*.3,y:.4+(p.y-.4)*.3,z:p.z*.3}));
  const w=await worker([small],[],null,true,false,2,false,{enable_recovery:false});
  await w.self.onmessage({data:{type:'context',anchor:[.5,.2,.1,1],timestamp:0}});
  for(const timestamp of [1,1500]) {
    await w.self.onmessage({data:{type:'frame',timestamp,frame:{width:640,height:480,close(){}}}});
    assert.equal(w.messages.at(-1).value.landmarks.length,1);
  }
});

test('cold resources use the pinned fast source and retain local fallback if it is blocked',async()=>{
  const fetches=[];
  await worker([],[],null,true,false,2,false,{enable_recovery:false,fetches,
    fetchAsset:async (url,options)=>{
      if(options?.cache==='only-if-cached') return {ok:false};
      if(new URL(url).origin!=='http://localhost') throw new Error('CDN blocked');
      return {ok:true,arrayBuffer:async()=>new ArrayBuffer(4)};
    }});
  assert.ok(fetches.some(url=>url.startsWith('https://storage.googleapis.com/')));
  assert.ok(fetches.some(url=>url.startsWith('http://localhost/mediapipe/hand_landmarker.task')));
});

test('cached local resources do not require another CDN transfer',async()=>{
  const fetches=[];
  await worker([],[],null,true,false,2,false,{enable_recovery:false,fetches,
    fetchAsset:async (url,options)=>{
      assert.equal(options.cache,'only-if-cached');
      return {ok:true,arrayBuffer:async()=>new ArrayBuffer(4)};
    }});
  assert.ok(fetches.length>0);
  assert.ok(fetches.every(url=>url.startsWith('http://localhost/')));
});

test('a stalled CDN cannot block local fallback and losing transfer is aborted',async()=>{
  let aborted=false;
  const w=await worker([],[],null,true,false,2,false,{enable_recovery:false,
    fetchAsset:async (url,options)=>{
      if(options?.cache==='only-if-cached') return {ok:false};
      if(url.includes('slow.invalid')) return new Promise((resolve,reject)=>{
        options.signal.addEventListener('abort',()=>{aborted=true;reject(new Error('aborted'));});
      });
      return {ok:true,arrayBuffer:async()=>new ArrayBuffer(4)};
    }});
  const asset=await w.scope.loadAsset('https://slow.invalid/model','http://localhost/model');
  assert.equal(asset.url,'http://localhost/model');
  assert.equal(aborted,true);
});

test('letter history preserves intermediate measurements when JPEG delivery skips frames',async()=>{
  let finish;const gate=new Promise(resolve=>{finish=resolve;});
  const points=[hand()];
  const w=await worker(points,[],gate,true,true,1,false,{enable_recovery:false,temporal_history:true});
  for(let i=0;i<12;i++) {
    points[0][8].x=.3+i*.01;
    await w.self.onmessage({data:{type:'frame',timestamp:i*67,
      frame:{id:i,width:640,height:480,close(){}}}});
  }
  finish();await new Promise(resolve=>setImmediate(resolve));
  const latest=w.messages.filter(m=>m.value.type==='tracking').at(-1).value;
  assert.equal(latest.hand_history.length,12);
  assert.equal(latest.hand_history[0].timestamp_ms,0);
  assert.equal(latest.hand_history.at(-1).timestamp_ms,737);
  assert.equal(latest.hand_history[0].landmarks[0][8][0],.3);
  assert.equal(latest.hand_history.at(-1).landmarks[0][8][0],.41);
});
