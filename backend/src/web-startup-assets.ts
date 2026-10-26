import {Application} from 'express';
import {existsSync, readFileSync, readdirSync} from 'node:fs';
import path from 'node:path';
import {gzipSync} from 'node:zlib';

// Compress public build assets once. Never compress on the AI/video request path
// or cache authenticated API responses. Revalidation keeps new builds visible.
export function serveWebStartupAssets(app: Application, webRoot: string): void {
  const assets = ['main.dart.js', 'flutter_bootstrap.js', 'flutter.js'];
  const collect = (relative: string) => {
    const folder = path.join(webRoot, relative);
    if (!existsSync(folder)) return;
    for (const entry of readdirSync(folder, {withFileTypes: true})) {
      const name = `${relative}/${entry.name}`;
      if (entry.isDirectory()) collect(name);
      else if (/\.(js|wasm)$/.test(name)) assets.push(name);
    }
  };
  collect('canvaskit');
  for (const name of assets) {
    const file = path.join(webRoot, name);
    if (!existsSync(file)) continue;
    const plain = readFileSync(file), compressed = gzipSync(plain);
    app.get(`/${name}`, (req, res) => {
      res.type(name.endsWith('.wasm') ? 'application/wasm' : 'application/javascript');
      res.setHeader('Cache-Control', 'no-cache');
      res.vary('Accept-Encoding');
      const encoding = req.get('Accept-Encoding') ? req.acceptsEncodings('gzip', 'identity') : 'identity';
      if (!encoding) {res.status(406).end(); return;}
      if (encoding === 'gzip') {
        res.setHeader('Content-Encoding', 'gzip');
        res.send(compressed);
      } else res.send(plain);
    });
  }
}
