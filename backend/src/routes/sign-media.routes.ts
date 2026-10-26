import { Router } from 'express';
import path from 'node:path';
import { DictionaryEntry, EntryStatus } from '../models/DictionaryEntry.model';

// Dataset and review folders are never web roots. Only linked published media is served.
const mediaRoot = path.resolve(__dirname, '../../../.runtime/sign-library-media');
export function createSignMediaRouter(root = mediaRoot) {
const router = Router();
// Cache URL resolution, never publication permission: every request still checks PUBLISHED.
const resolvedUrls = new Map<string, string[]>();
router.get('/license/:name', (req, res, next) => {
  if (!['apache-2.0', 'cc-by-4.0'].includes(req.params.name)) { res.sendStatus(404); return; }
  res.type('text/plain').sendFile(`LICENSE-${req.params.name}.txt`, { root, dotfiles: 'deny' }, error => {
    if ((error as NodeJS.ErrnoException)?.code === 'ENOENT') res.sendStatus(404);
    else if (error) next(error);
  });
});
router.get('/:file', async (req, res, next) => {
  try {
    const filename = req.params.file;
    if (!/^[a-f0-9]{64}(?:-[1-5])?\.(?:mp4|jpg)$/.test(filename)) {
      res.sendStatus(404); return;
    }
    const mediaPath = `/sign-media/${filename}`;
    const candidates = [...new Set([mediaPath, `${req.protocol}://${req.get('host')}${mediaPath}`,
      ...(process.env.PUBLIC_ORIGIN ? [process.env.PUBLIC_ORIGIN.replace(/\/$/, '') + mediaPath] : []),
      ...(resolvedUrls.get(filename) ?? [])])];
    const started = performance.now();
    let entry = await DictionaryEntry.findOne({ status: EntryStatus.PUBLISHED, $or: [
      {videoUrl: {$in: candidates}}, {thumbnailUrl: {$in: candidates}}, {imageUrls: {$in: candidates}},
    ] }).select('_id videoUrl thumbnailUrl imageUrls').lean();
    if (!entry) {
      const suffix = new RegExp(`/sign-media/${filename.replace('.', '\\.')}$`);
      entry = await DictionaryEntry.findOne({status: EntryStatus.PUBLISHED, $or: [
        {videoUrl: suffix}, {thumbnailUrl: suffix}, {imageUrls: suffix},
      ]}).select('_id videoUrl thumbnailUrl imageUrls').lean();
    }
    if (!entry) { res.sendStatus(404); return; }
    const urls = [entry.videoUrl, entry.thumbnailUrl, ...(entry.imageUrls ?? [])]
      .filter((url): url is string => typeof url === 'string' && url.endsWith(mediaPath));
    if (urls.length) {
      if (resolvedUrls.size >= 10000 && !resolvedUrls.has(filename)) resolvedUrls.delete(resolvedUrls.keys().next().value!);
      resolvedUrls.set(filename, urls);
    }
    res.setHeader('Server-Timing', `media_lookup;dur=${(performance.now() - started).toFixed(1)}`);
    res.sendFile(filename, { root, dotfiles: 'deny', maxAge: '1d', acceptRanges: true }, error => {
      if ((error as NodeJS.ErrnoException)?.code === 'ENOENT') res.sendStatus(404);
      else if (error) next(error);
    });
  } catch (error) { next(error); }
});
return router;
}
export default createSignMediaRouter();
