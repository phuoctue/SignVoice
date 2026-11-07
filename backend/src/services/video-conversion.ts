import { spawn } from 'node:child_process';
import { existsSync, readdirSync, createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { AppError } from '../common/errors/AppError';

export function videoConverterPath(): string {
  if (process.env.VIDEO_FFMPEG_PATH) return process.env.VIDEO_FFMPEG_PATH;
  const binaries = path.resolve(__dirname, '../../../.tools/video-tools/imageio_ffmpeg/binaries');
  if (existsSync(binaries)) {
    const file = readdirSync(binaries).find(name => /^ffmpeg.*(?:\.exe)?$/.test(name));
    if (file) return path.join(binaries, file);
  }
  return 'ffmpeg';
}

export async function convertVideo(input: string, output: string): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const child = spawn(videoConverterPath(), [
      '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
      '-protocol_whitelist', 'file,pipe', '-i', input,
      '-map', '0:v:0', '-map', '0:a:0?',
      '-vf', "scale=w='min(1920,iw)':h='min(1920,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', '-threads', '2', output,
    ], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
    child.stderr?.resume();
    const timer = setTimeout(() => {
      child.kill();
      reject(new AppError('Video xử lý quá lâu. Hãy thử video ngắn hơn.', 422, 'VIDEO_CONVERSION_TIMEOUT'));
    }, 30 * 60 * 1000);
    child.once('error', () => {
      clearTimeout(timer);
      reject(new AppError('Máy chủ chưa có bộ chuyển video. Chạy scripts/setup-video-upload.ps1.', 503, 'VIDEO_CONVERTER_UNAVAILABLE'));
    });
    child.once('close', code => {
      clearTimeout(timer);
      if (code === 0) resolve();
      else reject(new AppError('Không đọc được video. File có thể bị hỏng hoặc định dạng chưa được hỗ trợ.', 422, 'INVALID_VIDEO'));
    });
  });
}

export async function videoHash(filename: string): Promise<string> {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(filename)) hash.update(chunk);
  return hash.digest('hex');
}
