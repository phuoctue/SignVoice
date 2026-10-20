import { Router } from 'express';
import path from 'node:path';
import { DictionaryEntry, EntryStatus } from '../models/DictionaryEntry.model';

// Dataset and review folders are never web roots. Only linked published media is served.
const mediaRoot = path.resolve(__dirname, '../../../.runtime/sign-library-media');
export function createSignMediaRouter(root = mediaRoot) {
const router = Router();
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
    const suffix = new RegExp(`/sign-media/${filename.replace('.', '\\.')}$`);
    const entry = await DictionaryEntry.findOne({ status: EntryStatus.PUBLISHED, $or: [
      { videoUrl: suffix }, { thumbnailUrl: suffix }, { imageUrls: suffix },
    ] }).select('_id').lean();
    if (!entry) { res.sendStatus(404); return; }
    res.sendFile(filename, { root, dotfiles: 'deny', maxAge: '1d', acceptRanges: true }, error => {
      if ((error as NodeJS.ErrnoException)?.code === 'ENOENT') res.sendStatus(404);
      else if (error) next(error);
    });
  } catch (error) { next(error); }
});
return router;
}
export default createSignMediaRouter();
