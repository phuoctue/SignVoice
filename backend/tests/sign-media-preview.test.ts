import {afterEach, beforeEach, describe, expect, it} from 'vitest';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {addInlineThumbnails} from '../src/services/sign-media-preview.service';

let directory: string;
const filename = `${'a'.repeat(64)}-1.jpg`;
beforeEach(() => { directory = mkdtempSync(path.join(tmpdir(), 'signvoice-preview-')); });
afterEach(() => { rmSync(directory, {recursive:true, force:true}); });
describe('bounded inline dictionary thumbnails', () => {
  it('attaches JPEG bytes to authorized records without altering URLs', async () => {
    const bytes = Buffer.from([255,216,255,10,20]);
    writeFileSync(path.join(directory, filename), bytes);
    const input = [{word:'hello', thumbnailUrl:`https://old.example/sign-media/${filename}`}];
    const result = await addInlineThumbnails(input, 'thumbnailUrl', directory);
    expect(result[0]).toMatchObject({...input[0], thumbnailDataUrl:`data:image/jpeg;base64,${bytes.toString('base64')}`});
    expect(input[0]).not.toHaveProperty('thumbnailDataUrl');
  });
  it('ignores missing files, arbitrary paths, external photos, invalid and oversized JPEGs', async () => {
    writeFileSync(path.join(directory, filename), Buffer.alloc(100*1024));
    const inputs = ['https://external.example/photo.jpg', '/sign-media/../../.env', `/sign-media/${filename}`];
    expect(await addInlineThumbnails(inputs.map(imageUrl=>({imageUrl})), 'imageUrl', directory)).toEqual(inputs.map(imageUrl=>({imageUrl})));
  });
  it('caps inline payloads to the first twenty records', async () => {
    writeFileSync(path.join(directory, filename), Buffer.from([255,216,255,1]));
    const result = await addInlineThumbnails(Array.from({length:25},()=>({thumbnailUrl:`/sign-media/${filename}`})), 'thumbnailUrl', directory);
    expect(result.slice(0,20).every(entry=>'thumbnailDataUrl' in entry)).toBe(true);
    expect(result.slice(20).some(entry=>'thumbnailDataUrl' in entry)).toBe(false);
  });
});
