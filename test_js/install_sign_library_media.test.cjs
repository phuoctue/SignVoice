const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');

const workspace = path.resolve(__dirname, '..');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
function canonical(value) {
  return Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
}
function fixture() {
  const parent = path.join(workspace, '.runtime/media-installer-tests'); fs.mkdirSync(parent, {recursive: true});
  const root = fs.mkdtempSync(path.join(parent, 'case-'));
  const bundle = path.join(root, 'bundle'), project = path.join(root, 'project');
  fs.mkdirSync(path.join(bundle, 'media'), {recursive: true});
  fs.mkdirSync(path.join(bundle, 'metadata'), {recursive: true});
  const taxonomy = {groups: {Example: ['a']}, keywords: {}};
  fs.copyFileSync(path.join(workspace, 'scripts/install-sign-library-media.cjs'), path.join(bundle, 'install-media.cjs'));
  fs.writeFileSync(path.join(bundle, 'media', 'a'.repeat(64) + '.mp4'), 'opaque-test-payload');
  fs.writeFileSync(path.join(bundle, 'metadata/taxonomy.json'), JSON.stringify(taxonomy));
  fs.writeFileSync(path.join(bundle, 'metadata/library.json'), '[]');
  for (const filename of ['backend/package.json', 'backend/scripts/import-sign-library.ts',
    'backend/src/services/sign-library-categories.ts', 'backend/src/config/sign-library-categories.json']) {
    const target = path.join(project, filename); fs.mkdirSync(path.dirname(target), {recursive: true});
    fs.writeFileSync(target, filename.endsWith('sign-library-categories.json') ? JSON.stringify(taxonomy) : '{}');
  }
  const files = ['install-media.cjs', 'media/' + 'a'.repeat(64) + '.mp4', 'metadata/taxonomy.json', 'metadata/library.json'].map(filename => {
    const data = fs.readFileSync(path.join(bundle, filename)); return {path: filename, bytes: data.length, sha256: hash(data)};
  });
  fs.writeFileSync(path.join(bundle, 'manifest.json'), JSON.stringify({format: 'signvoice-reference-media', version: 1,
    entries: 1, videos: 1, images: 0, taxonomySha256: hash(JSON.stringify(canonical(taxonomy))), files}));
  const run = () => spawnSync(process.execPath, [path.join(bundle, 'install-media.cjs'), '--project', project], {encoding: 'utf8'});
  return {root, bundle, project, run, video: path.join(project, '.runtime/sign-library-media', 'a'.repeat(64) + '.mp4')};
}
test('installs intact files and keeps identical existing media on another run', () => {
  const f = fixture();
  assert.equal(f.run().status, 0);
  assert.equal(fs.readFileSync(f.video, 'utf8'), 'opaque-test-payload');
  const repeated = f.run(); assert.equal(repeated.status, 0); assert.match(repeated.stdout, /identical files kept/);
});
test('detects damaged source before creating destination media', () => {
  const f = fixture(); fs.appendFileSync(path.join(f.bundle, 'media', 'a'.repeat(64) + '.mp4'), 'damage');
  const result = f.run(); assert.equal(result.status, 1); assert.match(result.stderr, /Checksum mismatch/);
  assert.equal(fs.existsSync(path.join(f.project, '.runtime')), false);
});
test('does not overwrite conflicting destination data', () => {
  const f = fixture(); fs.mkdirSync(path.dirname(f.video), {recursive: true}); fs.writeFileSync(f.video, 'keep-recipient-data');
  const result = f.run(); assert.equal(result.status, 1); assert.match(result.stderr, /not overwritten/);
  assert.equal(fs.readFileSync(f.video, 'utf8'), 'keep-recipient-data');
  assert.equal(fs.existsSync(path.join(f.project, '.runtime/speech-sign-library')), false);
});
test('trusted installer reads a supplied bundle and versions changed metadata without overwriting the previous catalog', () => {
  const f=fixture();
  const run=()=>spawnSync(process.execPath,[path.join(workspace,'scripts/install-sign-library-media.cjs'),'--bundle',f.bundle,'--project',f.project,'--update'],{encoding:'utf8'});
  assert.equal(run().status,0);
  const pending=()=>JSON.parse(fs.readFileSync(path.join(f.project,'.runtime/library-package-pending.json'),'utf8'));
  const first=pending();
  const manifestPath=path.join(f.bundle,'manifest.json'),manifest=JSON.parse(fs.readFileSync(manifestPath));
  const content=JSON.stringify([{word:'new reference'}]);
  fs.writeFileSync(path.join(f.bundle,'metadata/library.json'),content);
  const entry=manifest.files.find(item=>item.path==='metadata/library.json');
  entry.bytes=Buffer.byteLength(content);entry.sha256=hash(content);
  fs.writeFileSync(manifestPath,JSON.stringify(manifest));
  assert.equal(run().status,0);
  const second=pending();assert.notEqual(first.packageRevision,second.packageRevision);
  assert.equal(fs.readFileSync(path.join(f.project,first.catalog),'utf8'),'[]');
  assert.equal(fs.readFileSync(path.join(f.project,second.catalog),'utf8'),content);
  assert.equal(fs.readFileSync(f.video,'utf8'),'opaque-test-payload');
  assert.equal(run().status,0);assert.equal(pending().packageRevision,second.packageRevision);
});
test('verify-only never writes package state or destination media', () => {
  const f=fixture();
  const result=spawnSync(process.execPath,[path.join(workspace,'scripts/install-sign-library-media.cjs'),'--bundle',f.bundle,'--verify-only'],{encoding:'utf8'});
  assert.equal(result.status,0);assert.equal(fs.existsSync(path.join(f.project,'.runtime')),false);
});
