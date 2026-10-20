const library = import('./mediapipe/vision_bundle.js?v=8.2');
const modelSource = 'https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task';
const wasmSource = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.32/wasm/';

async function loadAsset(remote, local) {
  // Reuse the verified local version immediately when already cached. A cold
  // browser downloads from the pinned public source without traversing Conveyor.
  try {
    const cached = await fetch(local, {cache:'only-if-cached', mode:'same-origin'});
    if (cached.ok) return {url:local, buffer:await cached.arrayBuffer()};
  } catch (_) {} // Some browsers do not support cache-only requests.
  const controllers = [new AbortController(), new AbortController()];
  const read = async (url, index) => {
    const response = await fetch(url, {signal:controllers[index].signal});
    if (!response.ok) throw new Error('Detector asset unavailable: '+response.status);
    return {url, buffer:await response.arrayBuffer()};
  };
  let timer, startFallback, started = false;
  const fallback = new Promise((resolve, reject) => {
    startFallback = () => {
      if (started) return;
      started = true; clearTimeout(timer);
      read(local, 1).then(resolve, reject);
    };
    timer = setTimeout(startFallback, 1500);
  });
  try {
    return await Promise.any([read(remote, 0).catch(error => {startFallback(); throw error;}), fallback]);
  } finally {
    clearTimeout(timer);
    controllers.forEach(controller => controller.abort());
  }
}

// Pixel frame and XYZ observations travel together. Python still owns feature
// normalization, tracking slots, sequence inference and recognition decisions.
let delegate = 'GPU';
let detector, recovery, modelHash, pixels, context, crop, cropContext, streamReader;
let lastRetry = -Infinity, failures = 0, retryIndex = 0, previous = [], previousAt = -Infinity;
let faceAnchor = [0,0,0,0], anchorAt = -Infinity;
let earlyPreview = false, independentEncode = false, targetHands = 2, startupMs = 0, assetLoadMs = 0, detectorInitMs = 0;
let encoding = false, pendingEncode = null, encoderCanvas, encoderContext;
let temporalHistory = false, history = [], liveObservations = false;
// One encoder in flight and one replaceable snapshot. Never queue old camera frames.
function enqueueEncode(bitmap, meta, observedAt) {
  pendingEncode?.bitmap.close();
  pendingEncode = {bitmap, meta, observedAt};
  if (!encoding) void encodeLatest();
}
async function encodeLatest() {
  encoding = true;
  try {
    while (pendingEncode) {
      const job = pendingEncode; pendingEncode = null;
      const {bitmap, meta} = job;
      try {
        encoderCanvas ??= new OffscreenCanvas(meta.width, meta.height);
        encoderContext ??= encoderCanvas.getContext('2d');
        if (encoderCanvas.width !== meta.width) encoderCanvas.width = meta.width;
        if (encoderCanvas.height !== meta.height) encoderCanvas.height = meta.height;
        encoderContext.drawImage(bitmap, 0, 0); // immutable pixels paired with this XYZ
      } finally { bitmap.close(); }
      const jpeg = await (await encoderCanvas.convertToBlob({type:'image/jpeg', quality:.78})).arrayBuffer();
      send({...meta, encode_ms:performance.now()-job.observedAt}, jpeg);
    }
  } catch (error) {
    pendingEncode?.bitmap.close(); pendingEncode = null;
    send({type:'unavailable', reason:String(error).slice(0,240)});
  } finally { encoding = false; }
}
const stamps = [];
const send = (value, jpeg) => self.postMessage({meta: JSON.stringify(value), jpeg}, jpeg ? [jpeg] : []);
self.onmessage = async ({data}) => {
  if (data.type === 'init') {
    const initBegin = performance.now();
    const progress = phase => send({type:'init_progress', phase, elapsed_ms:performance.now()-initBegin});
    if (data.startup_progress === true) progress('runtime');
    earlyPreview = data.early_preview === true;
    targetHands = data.target_hands === 1 ? 1 : 2;
    independentEncode = earlyPreview && data.independent_encode === true;
    temporalHistory = data.temporal_history === true;
    liveObservations = data.live_observations === true;
    try {
      // Download model and selected WASM concurrently, rather than making each
      // large transfer wait for the previous resource over a public tunnel.
      const modelDownload = loadAsset(modelSource,
        new URL('./mediapipe/hand_landmarker.task?v=8.2', self.location.href).href).then(asset => asset.buffer);
      const runtimeDownload = library.then(async ({FilesetResolver, HandLandmarker}) => {
        const files = await FilesetResolver.forVisionTasks(new URL('./mediapipe/wasm', self.location.href).href);
        await Promise.all(['wasmLoaderPath', 'wasmBinaryPath'].map(async key => {
          if (!files[key]) return;
          const name = files[key].split('/').pop();
          const asset = await loadAsset(wasmSource+name, files[key]+'?v=8.2');
          files[key] = asset.url; // SDK reuses the selected resource from HTTP cache
        }));
        return {files, HandLandmarker};
      });
      const [{files, HandLandmarker}, model] = await Promise.all([runtimeDownload, modelDownload]);
      if (data.startup_progress === true) progress('model');
      modelHash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', model))].map(x => x.toString(16).padStart(2, '0')).join('');
      assetLoadMs = performance.now()-initBegin;
      const detectorBegin = performance.now();
      const canvas = new OffscreenCanvas(640, 480);
      const options = {
        baseOptions: {modelAssetBuffer: new Uint8Array(model), delegate: 'GPU'},
        canvas, runningMode: 'VIDEO', numHands: 2,
        minHandDetectionConfidence: .15, minHandPresenceConfidence: .15, minTrackingConfidence: .22,
      };
      if (data.startup_progress === true) progress('primary_detector');
      try { detector = await HandLandmarker.createFromOptions(files, options); }
      catch (_) {
        // Same-frame CPU observations also skip Python's detector. Keep this
        // fallback local so GPU-disabled browsers need not wait for the network.
        delegate = 'CPU';
        detector = await HandLandmarker.createFromOptions(files, {...options,
          canvas:new OffscreenCanvas(640,480), baseOptions:{...options.baseOptions, delegate}});
      }
      try {
        if (data.enable_recovery === false) throw new Error('Primary VIDEO tracker handles reacquisition');
        if (delegate !== 'GPU') throw new Error('CPU uses primary VIDEO tracking only');
        recovery = await HandLandmarker.createFromOptions(files, {
          baseOptions: {modelAssetBuffer: new Uint8Array(model), delegate: 'GPU'},
          canvas: new OffscreenCanvas(640, 480), runningMode: 'IMAGE', numHands: 2,
          minHandDetectionConfidence: .15, minHandPresenceConfidence: .15,
        });
      } catch (_) { recovery = null; } // Primary GPU remains usable.
      pixels = new OffscreenCanvas(640, 480);
      context = pixels.getContext('2d');
      crop = new OffscreenCanvas(640, 480);
      cropContext = crop.getContext('2d');
      let renderer = 'unknown';
      try {
        const gl = canvas.getContext('webgl2');
        const debug = gl?.getExtension('WEBGL_debug_renderer_info');
        if (debug) renderer = gl.getParameter(debug.UNMASKED_RENDERER_WEBGL);
      } catch (_) {}
      startupMs = performance.now()-initBegin;
      detectorInitMs = performance.now()-detectorBegin;
      send({type: 'ready', delegate, renderer, init_ms:startupMs, asset_load_ms:assetLoadMs,
        detector_init_ms:detectorInitMs, recovery_enabled:!!recovery});
    } catch (error) {
      // Both local delegates failed; service CPU detection remains available.
      send({type: 'unavailable', reason: String(error).slice(0, 240)});
    }
    return;
  }
  if (data.type === 'context') {
    if (Array.isArray(data.anchor) && data.anchor.length === 4 && data.anchor.every(Number.isFinite)) {
      faceAnchor = data.anchor; anchorAt = data.timestamp;
    }
    return;
  }
  if (data.type === 'camera_stream') {
    if (!detector || streamReader) return;
    streamReader = data.readable.getReader();
    let origin, last = -1;
    try {
      while (true) {
        const {done, value: frame} = await streamReader.read();
        if (done) break;
        origin ??= frame.timestamp;
        const timestamp = Math.round(data.timestamp + (frame.timestamp - origin) / 1000);
        // VideoFrame's clock describes capture time, not UI delivery time.
        if (timestamp <= last) { frame.close(); continue; }
        last = timestamp;
        await processFrame(frame, timestamp, 'track_processor');
        // A permanently full camera queue must still give blob completion and
        // context messages a task turn (microtask-only reads can starve them).
        if (independentEncode) await new Promise(resolve => setTimeout(resolve, 0));
      }
    } catch (error) {
      send({type: 'unavailable', reason: String(error).slice(0, 240)});
    } finally {
      await streamReader.cancel().catch(() => {});
      streamReader.releaseLock();
      streamReader = null;
    }
    return;
  }
  if (data.type !== 'frame') return;
  await processFrame(data.frame, data.timestamp, 'video_callback');
};

async function processFrame(image, timestamp, captureSource) {
  try {
    if (!detector) return;
    const begin = performance.now();
    const sourceWidth = image.displayWidth || image.width;
    const sourceHeight = image.displayHeight || image.height;
    const width = Math.min(sourceWidth, 640);
    const height = Math.round(sourceHeight * width / sourceWidth);
    if (pixels.width !== width || pixels.height !== height) history = [];
    if (pixels.width !== width) pixels.width = width;
    if (pixels.height !== height) pixels.height = height;
    context.drawImage(image, 0, 0, width, height);
    const raw = detector.detectForVideo(pixels, timestamp);
    const found = {landmarks: [], handedness: []};
    raw.landmarks.forEach((hand,i) => {
      if (foregroundHand(hand,height/width,timestamp) && !found.landmarks.some(old=>duplicateHand(old,hand,height/width))) {
        found.landmarks.push(hand);found.handedness.push(raw.handedness[i]);
      }
    });
    const primaryCount = found.landmarks.length;
    const delay = Math.min(2000, (primaryCount ? 600 : 200) * 2 ** Math.min(failures, 3));
    let retried = false;
    if (recovery && primaryCount < targetHands && timestamp - lastRetry >= delay) {
      lastRetry = timestamp; retried = true;
      const bounds = recoveryBounds(found.landmarks, previous, timestamp - previousAt, ++retryIndex);
      const [x, y, x1, y1] = bounds;
      const cw = Math.max(1, Math.round((x1-x)*width)), ch = Math.max(1, Math.round((y1-y)*height));
      if (crop.width !== cw) crop.width = cw;
      if (crop.height !== ch) crop.height = ch;
      cropContext.drawImage(pixels, x*width, y*height, cw, ch, 0, 0, cw, ch);
      const recovered = recovery.detect(crop);
      recovered.landmarks.forEach((hand, i) => {
        const mapped = hand.map(p => ({x: x+p.x*cw/width, y: y+p.y*ch/height, z: p.z*cw/width}));
        if (found.landmarks.length < 2 && foregroundHand(mapped,height/width,timestamp) && !found.landmarks.some(old => duplicateHand(old, mapped, height/width))) {
          found.landmarks.push(mapped); found.handedness.push(recovered.handedness[i]);
        }
      });
      failures = found.landmarks.length > primaryCount ? 0 : Math.min(failures+1, 8);
    }
    if (found.landmarks.length === 2) failures = 0;
    if (found.landmarks.length) { previous = found.landmarks; previousAt = timestamp; }
    const now = performance.now();
    stamps.push(now);
    if (stamps.length > 24) stamps.shift();
    const landmarks = found.landmarks.map(hand => hand.map(p => [p.x, p.y]));
    // Paint measured joints immediately. JPEG encoding and the service transport
    // must not delay the local overlay; inference still receives matching pixels.
    const meta = {type: 'tracking', timestamp, capture_source: captureSource, recovery_ran: retried,
      recovered_hands: found.landmarks.length-primaryCount, landmarks, width, height,
      hand_observation: {schema: 'mediapipe_hand_3d_v1', sdk: '0.10.32', platform:'web', delegate:delegate.toLowerCase(), model_sha256: modelHash,
        init_ms:startupMs, asset_load_ms:assetLoadMs, detector_init_ms:detectorInitMs,
        raw_hands:raw.landmarks.length, rejected_hands:Math.max(0,raw.landmarks.length-primaryCount),
        processing_ms:now-begin, fps:stamps.length>1 ? 1000*(stamps.length-1)/(now-stamps[0]) : 0, recovery_enabled:!!recovery,
        timestamp_ms: timestamp, width, height,
        landmarks: found.landmarks.map(hand => hand.map(p => [p.x, p.y, p.z])),
        handedness: found.handedness.map(hand => hand[0].categoryName)},
      processing_ms: now - begin, fps: stamps.length > 1 ? 1000 * (stamps.length - 1) / (now - stamps[0]) : 0};
    if (earlyPreview) send({type:'preview',timestamp,capture_source:captureSource,landmarks,
      ...(temporalHistory || liveObservations ? {hand_observation:meta.hand_observation} : {}),
      processing_ms:now-begin,fps:meta.fps});
    if (temporalHistory) {
      // Preserve measured intermediate poses even when JPEG/network skips them.
      // No pixels or synthetic/interpolated joints are added to these samples.
      if (!history.length || timestamp-history.at(-1).timestamp_ms >= 60) {
        history.push({timestamp_ms:timestamp, landmarks:meta.hand_observation.landmarks,
          handedness:meta.hand_observation.handedness});
      }
      history = history.filter(row => timestamp-row.timestamp_ms <= 2000).slice(-32);
      meta.hand_history = history.slice();
    }
    if (independentEncode) {
      enqueueEncode(pixels.transferToImageBitmap(), meta, now);
    } else {
      const jpeg = await (await pixels.convertToBlob({type:'image/jpeg', quality:.78})).arrayBuffer();
      send({...meta, encode_ms:performance.now()-now}, jpeg);
    }
  } catch (error) {
    send({type: 'unavailable', reason: String(error).slice(0, 240)});
  } finally {
    image?.close();
  }
}

function foregroundHand(hand, aspect, timestamp) {
  const valid = faceAnchor[3] > 0 && timestamp >= anchorAt && timestamp-anchorAt <= 1200;
  const threshold = valid ? Math.max(.012,.1*faceAnchor[2]) : .025;
  const wrist = hand[0];
  const radius = Math.max(...hand.map(p=>Math.hypot(p.x-wrist.x,(p.y-wrist.y)*aspect,p.z-wrist.z)));
  return radius >= threshold && (!valid || Math.abs(wrist.x-faceAnchor[0]) <= Math.max(.35,4*faceAnchor[2]));
}

function duplicateHand(a, b, aspect) {
  const distance = (p,q) => Math.hypot(p.x-q.x,(p.y-q.y)*aspect);
  const median = values => values.sort((a,b)=>a-b)[Math.floor(values.length/2)];
  const radius = Math.max(.025, ...a.map(p=>distance(p,a[0])), ...b.map(p=>distance(p,b[0])));
  // Only near-identical duplicate observations count as the same hand. Two
  // actual hands may touch or overlap during a sign and must remain separate.
  return distance(a[0],b[0]) < .12*radius && median(a.map((p,i)=>distance(p,b[i]))) < .08*radius;
}

function recoveryBounds(hands, previousHands, age, attempt) {
  // Re-detect in current pixels. Previous points only choose a search region.
  let points = hands.length === 0 && age <= 350 ? previousHands.flat() : [];
  if (hands.length === 1 && attempt % 3 === 0) {
    return hands[0][0].x < .5 ? [.3,0,1,1] : [0,0,.7,1];
  }
  if (hands.length === 1 && attempt % 3 === 2) points = hands[0];
  if (!points.length) return [0,0,1,1];
  const xs=points.map(p=>p.x), ys=points.map(p=>p.y);
  const x=Math.min(...xs), y=Math.min(...ys), x1=Math.max(...xs), y1=Math.max(...ys);
  const pad=Math.max(.12,Math.max(x1-x,y1-y)*.85);
  const bounds = [Math.max(0,x-pad),Math.max(0,y-pad),Math.min(1,x1+pad), hands.length ? 1 : Math.min(1,y1+pad)];
  return bounds[2]-bounds[0] >= .05 && bounds[3]-bounds[1] >= .05 ? bounds : [0,0,1,1];
}
