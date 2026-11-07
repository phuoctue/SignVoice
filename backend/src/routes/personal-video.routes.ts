import { Router } from 'express';
import path from 'node:path';
import { validPersonalVideoSignature } from '../services/personal-video';

export const personalVideoRoot = path.resolve(__dirname, '../../../.runtime/personal-videos');
export function createPersonalVideoRouter(root = personalVideoRoot) {
  const router = Router();
  router.get('/:userId/:file', (req, res, next) => {
    const resource = `/personal-videos/${req.params.userId}/${req.params.file}`;
    if (!validPersonalVideoSignature(resource, req.query.expires, req.query.signature)) {
      res.sendStatus(403); return;
    }
    res.setHeader('Cache-Control', 'private, no-store');
    res.sendFile(req.params.file, { root: path.join(root, req.params.userId), dotfiles: 'deny', acceptRanges: true }, error => {
      if ((error as NodeJS.ErrnoException)?.code === 'ENOENT') res.sendStatus(404);
      else if (error) next(error);
    });
  });
  return router;
}
export default createPersonalVideoRouter();
