#!/usr/bin/env node
'use strict';

// README distribution guard. No network access or third-party dependencies.
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');

const binaryExtension = /\.(?:apk|aab|exe|msi|msix|appx|zip|7z|rar|tar|tgz|gz|bz2|xz|dmg|pkg|appimage|deb|rpm|bin|dll|so|wasm|task|tflite|onnx|safetensors)(?:$|[?#/])/i;
const sharedHost = /(?:^|\.)(?:conveyor\.cloud|drive\.google\.com|drive\.usercontent\.google\.com|drive\.googleusercontent\.com|mediafire\.com|dropbox\.com|dropboxusercontent\.com|mega\.nz|mega\.io|1drv\.ms|onedrive\.live\.com|gofile\.io|pixeldrain\.com)$/i;

function forbiddenTarget(value) {
  const target = value.replace(/&amp;/g, '&').replace(/[>*.,;]+$/, '');
  let decoded;
  try { decoded = decodeURIComponent(target); } catch { decoded = target; }
  if (/^https?:\/\//i.test(target)) {
    let url;
    try { url = new URL(target); } catch { return false; }
    return sharedHost.test(url.hostname) || binaryExtension.test(decoded) ||
      /\/releases\/download\/|\/downloads?(?:\/|\?|$)/i.test(url.pathname + url.search) ||
      (/^(?:www\.)?github\.com$/i.test(url.hostname) && /\/archive\//i.test(url.pathname)) ||
      /[?&](?:export=download|download=(?:1|true))/i.test(decoded);
  }
  return binaryExtension.test(decoded);
}

function findings(text) {
  const result = [];
  text.split(/\r?\n/).forEach((line, index) => {
    const targets = [
      ...(line.match(/https?:\/\/[^\s<>`"'\])]+/gi) || []),
      ...Array.from(line.matchAll(/\]\(\s*<?([^\s)>]+)/g), match => match[1]),
      ...Array.from(line.matchAll(/\b(?:href|src)\s*=\s*["']([^"']+)["']/gi), match => match[1]),
      ...Array.from(line.matchAll(/^\s*\[[^\]]+\]:\s*<?([^\s>]+)/g), match => match[1]),
      ...(line.match(/\b[A-Z]:\\[^`"<>\r\n]+\.(?:apk|aab|exe|msi|zip|7z|rar)\b/gi) || []),
    ];
    if (/\b[\w-]+\.conveyor\.cloud\b/i.test(line) || targets.some(forbiddenTarget)) {
      result.push(index + 1);
    }
  });
  return result;
}

function selfTest() {
  const assert = require('node:assert/strict');
  for (const text of [
    '[APK](https://example.org/app.apk)',
    '[EXE](downloads/app.exe)',
    '<a href="https://example.org/app.zip?token=fixture">file</a>',
    '[file]: https://example.org/app%2Eapk',
    'https://example.org/releases/download/v1/app',
    'https://github.com/example/project/archive/refs/heads/main.zip',
    'https://drive.google.com/file/d/fixture/view',
    'https://www.mediafire.com/file/fixture',
    '`sample.conveyor.cloud`',
    '`E:\\Build\\app.apk`',
  ]) assert.equal(findings(text).length, 1, text);
  for (const text of [
    '[Source](https://github.com/google-ai-edge/mediapipe)',
    'Package: https://www.npmjs.com/package/@mediapipe/tasks-vision/v/0.10.32',
    '[Guide](docs/SETUP_AI.md)',
    'Run node.exe to build an APK locally.',
    'http://localhost:3003/api-docs',
  ]) assert.equal(findings(text).length, 0, text);
  console.log('README download guard: 15 self-tests passed.');
}

function git(args) {
  return execFileSync('git', args, {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
}

function check(ref) {
  const files = git(ref ? ['ls-tree', '-r', '-z', '--name-only', ref] :
    ['ls-files', '-z', '--cached', '--others', '--exclude-standard']).split('\0')
    .filter(file => /^readme(?:\..*)?$/i.test(path.posix.basename(file)));
  let bad = false;
  for (const file of new Set(files)) {
    const text = ref ? git(['show', `${ref}:${file}`]) :
      (fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '');
    for (const line of findings(text)) {
      console.error(`${file}:${line}: prohibited download/artifact/tunnel link${ref ? ` in ${ref}` : ''}.`);
      bad = true;
    }
  }
  if (bad) throw new Error('Push blocked: remove these links from README and commit the cleanup. Do not bypass the guard.');
  console.log(`README download guard: ${new Set(files).size} files clean${ref ? ` (${ref})` : ' (working tree)'}.`);
}

try {
  const args = process.argv.slice(2);
  if (args.includes('--self-test')) {
    selfTest();
  } else if (args.includes('--pre-push')) {
    const refs = fs.readFileSync(0, 'utf8').trim().split(/\r?\n/).filter(Boolean);
    for (const line of refs) {
      const sha = line.trim().split(/\s+/)[1];
      if (!/^[a-f0-9]{40,64}$/i.test(sha || '')) throw new Error('Invalid push input.');
      if (!/^0+$/.test(sha)) check(sha);
    }
  } else if (args.length === 2 && args[0] === '--ref') {
    check(args[1]);
  } else if (!args.length) {
    check();
  } else {
    throw new Error('Usage: check-readme-download-links.cjs [--ref HEAD | --pre-push | --self-test]');
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
