import { Router, RequestHandler } from 'express';
import { createWriteStream, constants } from 'node:fs';
import { mkdir, mkdtemp, copyFile, unlink, rmdir } from 'node:fs/promises';
import { Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import path from 'node:path';
import { rateLimit } from 'express-rate-limit';
import { requireAuth, requirePermission } from '../common/middlewares/auth.middleware';
import { AppError } from '../common/errors/AppError';
import { convertVideo, videoHash } from '../services/video-conversion';
import { signPersonalVideo } from '../services/personal-video';

const mediaRoot = path.resolve(__dirname, '../../../.runtime/sign-library-media');
export const MAX_VIDEO_BYTES = 1024 * 1024 * 1024;
type Converter = (input: string, output: string) => Promise<void>;

export function createVideoUploadRouter(root = mediaRoot, converter: Converter = convertVideo, maxBytes = MAX_VIDEO_BYTES, visibility: 'dictionary' | 'personal' = 'dictionary') {
  const router = Router();
  let active = 0;
  const authorize: RequestHandler = visibility === 'dictionary' ? requirePermission('dictionary:write') : (_req, _res, next) => next();
  router.post('/', requireAuth, authorize,
    rateLimit({ windowMs: 15 * 60 * 1000, limit: 10 }),
    async (req, res, next) => {
      if (!req.is('application/octet-stream') && !req.is('video/*')) {
        next(new AppError('Hãy chọn một file video từ máy.', 415, 'INVALID_VIDEO_TYPE')); return;
      }
      const tooLarge = () => new AppError('Video cần nhỏ hơn hoặc bằng 1 GB.', 413, 'VIDEO_TOO_LARGE');
      if (Number(req.get('content-length')) > maxBytes) { next(tooLarge()); return; }
      if (active >= 2) {
        next(new AppError('Máy chủ đang xử lý video khác. Vui lòng thử lại sau.', 503, 'VIDEO_PROCESSING_BUSY')); return;
      }
      active++;
      let temporary: string | undefined;
      let videoUrl: string | undefined;
      let failure: unknown;
      try {
        const destination = visibility === 'personal' ? path.join(root, req.user!.id.toString()) : root;
        await mkdir(destination, { recursive: true });
        temporary = await mkdtemp(path.join(destination, '.upload-'));
        const input = path.join(temporary, 'input');
        const output = path.join(temporary, 'output.mp4');
        let received = 0;
        const limit = new Transform({ transform(chunk, _encoding, callback) {
          received += chunk.length;
          callback(received > maxBytes ? tooLarge() : null, chunk);
        } });
        const abort = () => limit.destroy(new AppError('Quá trình tải video đã bị ngắt.', 400, 'VIDEO_UPLOAD_ABORTED'));
        req.once('aborted', abort);
        try {
          await pipeline(req.pipe(limit), createWriteStream(input, { flags: 'wx' }));
        } finally {
          req.removeListener('aborted', abort);
          req.unpipe(limit);
          if (!req.complete && !req.destroyed) req.resume();
        }
        if (!received) throw new AppError('File video trống.', 400, 'INVALID_VIDEO');
        await converter(input, output);
        const filename = `${await videoHash(output)}.mp4`;
        try { await copyFile(output, path.join(destination, filename), constants.COPYFILE_EXCL); }
        catch (error) { if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error; }
        videoUrl = visibility === 'personal'
          ? signPersonalVideo(`/personal-videos/${req.user!.id}/${filename}`)
          : `${req.protocol}://${req.get('host')}/sign-media/${filename}`;
      } catch (error) { failure = error; }
      finally {
        if (temporary) {
          await Promise.allSettled(['input', 'output.mp4'].map(file => unlink(path.join(temporary!, file))));
          await rmdir(temporary).catch(() => undefined);
        }
        active--;
      }
      if (failure) next(failure);
      else res.status(201).json({ success: true, data: { videoUrl } });
    });
  return router;
}
export default createVideoUploadRouter();
