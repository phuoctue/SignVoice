import {Router} from 'express';
import path from 'node:path';
import {mkdir, writeFile, rm} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {User} from '../models/User.model';
import {AppError} from '../common/errors/AppError';

const root = path.resolve(__dirname, '../../../.runtime/avatar-media');
const idPattern = /^[a-f\d]{24}$/i;
export function avatarImage(value: string) {
  const match = /^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/]+={0,2})$/.exec(value);
  if (!match) throw new AppError('Chọn ảnh JPG, PNG hoặc WebP.', 400, 'INVALID_AVATAR');
  const bytes = Buffer.from(match[2], 'base64');
  const valid = bytes.length >= 12 && bytes.length <= 512 * 1024 && bytes.toString('base64') === match[2] && (
    match[1] === 'jpeg' && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255 ||
    match[1] === 'png' && bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) ||
    match[1] === 'webp' && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP');
  if (!valid) throw new AppError('Ảnh không hợp lệ hoặc lớn hơn 512 KB.', 400, 'INVALID_AVATAR');
  return {bytes, extension: match[1] === 'jpeg' ? 'jpg' : match[1]};
}
export async function saveAvatarImage(userId: string, value: string) {
  if (!idPattern.test(userId)) throw new Error('Invalid avatar owner');
  const {bytes, extension} = avatarImage(value);
  const filename = `${createHash('sha256').update(bytes).digest('hex')}.${extension}`;
  const folder = path.join(root, userId);
  await mkdir(folder, {recursive: true});
  try { await writeFile(path.join(folder, filename), bytes, {flag: 'wx'}); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error; }
  return `/user-media/avatars/${userId}/${filename}`;
}
export async function removeOwnedAvatars(userId: string) {
  if (!idPattern.test(userId)) throw new Error('Invalid avatar owner');
  await rm(path.join(root, userId), {recursive: true, force: true});
}
export function createAvatarMediaRouter() {
  const router = Router();
  router.get('/:user/:file', async (req, res, next) => {
    try {
      if (!idPattern.test(req.params.user) || !/^[a-f\d]{64}\.(jpg|png|webp)$/.test(req.params.file)) { res.sendStatus(404); return; }
      const url = `/user-media/avatars/${req.params.user}/${req.params.file}`;
      if (!await User.exists({_id: req.params.user, avatarUrl: url})) { res.sendStatus(404); return; }
      res.setHeader('Cache-Control', 'private, max-age=3600');
      res.sendFile(req.params.file, {root: path.join(root, req.params.user), dotfiles: 'deny'}, error => {
        if ((error as NodeJS.ErrnoException)?.code === 'ENOENT') res.sendStatus(404);
        else if (error) next(error);
      });
    } catch (error) { next(error); }
  });
  return router;
}
