// Independent current-pixel check. CPU inference must not block VIDEO preview.
const library=import('./mediapipe/vision_bundle.js?v=8.2');
let detector;
self.onmessage=async({data})=>{
  if(data.type==='init') {
    try {
      const start=performance.now();
      const {HandLandmarker}=await library;
      detector=await HandLandmarker.createFromOptions(data.files,{
        baseOptions:{modelAssetBuffer:new Uint8Array(data.model),delegate:'CPU'},
        runningMode:'IMAGE',numHands:2,minHandDetectionConfidence:.15,minHandPresenceConfidence:.15,
      });
      self.postMessage({type:'ready',init_ms:performance.now()-start});
    }catch(error){self.postMessage({type:'error',reason:String(error).slice(0,160)});}
    return;
  }
  if(data.type!=='frame')return;
  try {
    const start=performance.now();
    const result=detector.detect(data.frame);
    self.postMessage({type:'result',landmarks:result.landmarks,processing_ms:performance.now()-start});
  }catch(error){self.postMessage({type:'error',reason:String(error).slice(0,160)});}
  finally{data.frame.close();}
};
