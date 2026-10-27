import {RequestHandler} from 'express';
import {gzip} from 'node:zlib';

/** Compress large JSON reads without adding another media round-trip.
 * Private responses retain their no-store; token/OAuth responses are excluded.
 */
export const dictionaryCompression: RequestHandler = (req, res, next) => {
  if (req.method !== 'GET' || /^\/auth(?:\/|$)/.test(req.path)) return next();
  res.vary('Accept-Encoding');
  if (!req.headers['accept-encoding'] || !req.acceptsEncodings('gzip')) return next();
  const original = res.json.bind(res);
  res.json = body => {
    if (res.getHeader('Content-Encoding') || res.headersSent) return original(body);
    const json = JSON.stringify(body);
    if (!json || Buffer.byteLength(json) < 2048) return original(body);
    gzip(json, (error, compressed) => {
      if (res.destroyed || res.writableEnded) return;
      if (error || compressed.length >= Buffer.byteLength(json)) {
        original(body);
        return;
      }
      res.removeHeader('Content-Length');
      res.setHeader('Content-Encoding', 'gzip');
      res.type('json').send(compressed);
    });
    return res;
  };
  next();
};
