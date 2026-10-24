#!/usr/bin/env node
// Distributed inside the media bundle. Uses only Node.js built-in modules.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {parseArgs} = require('node:util');

function normalizedJson(value) {
  if (Array.isArray(value)) return value.map(normalizedJson);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, normalizedJson(value[key])]));
  return value;
}
function taxonomyHash(filename) {
  return crypto.createHash('sha256').update(JSON.stringify(normalizedJson(JSON.parse(fs.readFileSync(filename, 'utf8').replace(/^\uFEFF/, ''))))).digest('hex');
}
async function digest(filename) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(filename)) hash.update(chunk);
  return hash.digest('hex');
}
function inside(root, candidate) {
  const relative = path.relative(root, candidate);
  if (relative.startsWith('..' + path.sep) || relative === '..' || path.isAbsolute(relative)) throw Error('Destination leaves the project');
}
function safeDestination(root, candidate) {
  inside(root, candidate);
  let existing = candidate;
  while (!fs.existsSync(existing)) existing = path.dirname(existing);
  inside(root, fs.realpathSync(existing));
  if (fs.existsSync(candidate) && fs.lstatSync(candidate).isSymbolicLink()) throw Error('Refusing linked destination: ' + candidate);
}
async function main() {
  const {values} = parseArgs({options: {project: {type: 'string'}, 'verify-only': {type: 'boolean', default: false}}});
  const bundle = __dirname;
  const manifest = JSON.parse(fs.readFileSync(path.join(bundle, 'manifest.json'), 'utf8'));
  if (manifest.format !== 'signvoice-reference-media' || manifest.version !== 1 || !Array.isArray(manifest.files) ||
      !manifest.files.length || manifest.files.length > 30000 || new Set(manifest.files.map(file => file.path)).size !== manifest.files.length) throw Error('Invalid bundle manifest');
  const metadata = new Set(['library.json', 'categories.json', 'taxonomy.json', 'source_cards.json', 'package-info.json']);
  const allowed = name => /^media\/[a-f0-9]{64}(?:-[1-5])?\.(?:mp4|jpg)$/.test(name) ||
    ['media/LICENSE-apache-2.0.txt', 'media/LICENSE-cc-by-4.0.txt', 'README_VI.md', 'install-media.cjs'].includes(name) ||
    name.startsWith('metadata/') && metadata.has(name.slice('metadata/'.length));
  for (const [index, file] of manifest.files.entries()) {
    if (typeof file.path !== 'string' || !allowed(file.path) || !/^[a-f0-9]{64}$/.test(file.sha256) || !Number.isSafeInteger(file.bytes) || file.bytes < 0) throw Error('Unsafe bundle entry');
    const source = path.join(bundle, ...file.path.split('/'));
    const stat = fs.lstatSync(source);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size !== file.bytes || await digest(source) !== file.sha256) throw Error('Checksum mismatch: ' + file.path);
    if ((index + 1) % 2000 === 0) console.log(`Verified ${index + 1}/${manifest.files.length} files`);
  }
  console.log(`Bundle verified: ${manifest.entries} entries, ${manifest.videos} videos, ${manifest.images} images.`);
  if (values['verify-only']) return;
  if (!values.project) throw Error('Use --verify-only or --project "absolute/path/to/SignVoice"');
  const project = fs.realpathSync(path.resolve(values.project));
  for (const required of ['backend/package.json', 'backend/scripts/import-sign-library.ts', 'backend/src/services/sign-library-categories.ts', 'backend/src/config/sign-library-categories.json']) {
    if (!fs.existsSync(path.join(project, required)) || !fs.statSync(path.join(project, required)).isFile()) {
      throw Error('Pull the complete updated code first; missing ' + required);
    }
  }
  const taxonomy = path.join(project, 'backend/src/config/sign-library-categories.json');
  if (taxonomyHash(taxonomy) !== manifest.taxonomySha256) throw Error('The code taxonomy differs from this bundle. Pull the matching dictionary/category update first. No source code was overwritten.');
  const plans = [];
  for (const file of manifest.files) {
    if (!file.path.startsWith('media/') && !file.path.startsWith('metadata/')) continue;
    const destination = file.path.startsWith('media/')
      ? path.join(project, '.runtime/sign-library-media', file.path.slice('media/'.length))
      : path.join(project, '.runtime/speech-sign-library/shared-20261024', file.path.slice('metadata/'.length));
    safeDestination(project, destination);
    const exists = fs.existsSync(destination);
    if (exists && (!fs.statSync(destination).isFile() || await digest(destination) !== file.sha256)) throw Error('Existing file differs; not overwritten: ' + destination);
    plans.push({source: path.join(bundle, ...file.path.split('/')), destination, exists});
  }
  // Verify all sources and all conflicts before making any copy.
  for (const plan of plans) {
    if (plan.exists) continue;
    fs.mkdirSync(path.dirname(plan.destination), {recursive: true});
    fs.copyFileSync(plan.source, plan.destination, fs.constants.COPYFILE_EXCL);
  }
  console.log(`Installed ${plans.filter(plan => !plan.exists).length} files; ${plans.filter(plan => plan.exists).length} identical files kept.`);
  console.log('Media installed. Configure your own backend/.env and active ADMIN, then import the dictionary as described in README_VI.md.');
  console.log('Catalog: .runtime/speech-sign-library/shared-20261024/library.json');
  console.log('This installer did not connect to MongoDB or change user/account data.');
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
