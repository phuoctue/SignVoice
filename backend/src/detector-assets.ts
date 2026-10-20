import { Application } from 'express';
import { existsSync, readFileSync } from 'fs';
import path from 'path';
import { gzipSync } from 'zlib';

// Compress once at startup, never on the camera request path. No extra package.
export function serveDetectorAssets(app: Application, webRoot: string): void {
  for (const name of ['hand_landmarker.task', 'vision_bundle.js',
    'wasm/vision_wasm_internal.js', 'wasm/vision_wasm_internal.wasm',
    'wasm/vision_wasm_nosimd_internal.js', 'wasm/vision_wasm_nosimd_internal.wasm']) {
    const file = path.join(webRoot, 'mediapipe', name);
    if (!existsSync(file)) continue;
    const plain = readFileSync(file);
    const compressed = gzipSync(plain);
    app.get(`/mediapipe/${name}`, (req, res) => {
      res.type(name.endsWith('.task') ? 'application/octet-stream' : path.extname(name));
      res.setHeader('Cache-Control', 'public, max-age=86400');
      res.vary('Accept-Encoding');
      if (req.acceptsEncodings('gzip')) {
        res.setHeader('Content-Encoding', 'gzip');
        res.send(compressed);
      } else res.send(plain);
    });
  }
}
