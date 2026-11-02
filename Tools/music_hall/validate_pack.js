#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { compile, SAMPLE_RATE } = require('./compile_song');

const dir = process.argv[2];
if (!dir) {
  console.error('usage: node validate_pack.js <unpacked-pack-dir>');
  process.exit(2);
}
const abs = path.resolve(dir);
const failures = [];
const notes = [];
function check(cond, msg) { if (!cond) failures.push(msg); else notes.push('OK ' + msg); }
function sha(buf) { return crypto.createHash('sha256').update(buf).digest('hex'); }

const manifestPath = path.join(abs, 'manifest.json');
check(fs.existsSync(manifestPath), 'manifest.json exists');
if (!fs.existsSync(manifestPath)) {
  console.log('FAIL\n' + failures.join('\n'));
  process.exit(1);
}
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
check(manifest.format === 'fpgasong', 'format=fpgasong');
check(manifest.format_version === '1.0' || manifest.format_version === '0.1', 'format_version=1.0 or 0.1');
check(manifest.content_kind === 'technical_demo_not_let_it_be' || manifest.content_kind === 'licensed-score',
  'content_kind is explicit');
check(manifest.files && typeof manifest.files === 'object', 'manifest has files');
const scoreDir = fs.existsSync(path.join(abs, 'score', 'score.json')) ? 'score/' : '';
for (const f of ['score.json', 'performance.bin', 'report.json', 'stage.json']) {
  const p = path.join(abs, scoreDir + f);
  check(fs.existsSync(p), `${f} exists`);
  if (!fs.existsSync(p)) continue;
  const b = fs.readFileSync(p);
  const known = manifest.files[f] || manifest.files[scoreDir + f];
  check(!!known, `${f} listed in manifest`);
  if (known) {
    check(known.bytes === b.length, `${f} size matches manifest`);
    check(known.sha256 === sha(b), `${f} sha256 matches manifest`);
  }
}

const score = JSON.parse(fs.readFileSync(path.join(abs, scoreDir + 'score.json'), 'utf8'));
const compiled = compile(score);
check(compiled.report.errors.length === 0, 'score compiles without errors');
const perf = fs.readFileSync(path.join(abs, scoreDir + 'performance.bin'));
const report = JSON.parse(fs.readFileSync(path.join(abs, scoreDir + 'report.json'), 'utf8'));
check(perf.subarray(0, 4).toString('ascii') === 'FPGS', 'performance magic FPGS');
check(perf.readUInt8(4) === 1, 'performance version 1');
check(perf.readUInt8(5) === 32, 'performance header size 32');
check(perf.readUInt8(6) === 8, 'performance event size 8');
check(perf.readUInt32LE(8) === 52500000, 'performance sample numerator 52500000');
check(perf.readUInt16LE(12) === 1088, 'performance sample denominator 1088');
const n = perf.readUInt32LE(16);
check(n === compiled.report.event_count, 'performance event count matches compiler');
check(perf.length === 32 + n * 8, 'performance size matches header+events');
check(report.event_count === n, 'report event count matches');
check(compiled.performance.equals(perf), 'committed performance is byte-identical to compiler output');
check(Math.abs(report.duration_seconds - compiled.report.duration_seconds) < 1e-9, 'report duration matches');
check(report.peak_concurrency.total >= 1, 'concurrency report present');
check(manifest.compile_report === 'report.json' || manifest.compile_report === 'score/report.json', 'manifest compile_report');
check(manifest.target.sample_rate_num === 52500000, 'manifest sample numerator');
check(manifest.target.sample_rate_den === 1088, 'manifest sample denominator');
check(manifest.target.firmware_support === 'draft-not-supported-by-current-firmware' || manifest.target.firmware_support === 'timed-playback-v1-required',
  'manifest declares firmware support requirements');
check(manifest.content_kind !== 'licensed-score' || score.rights, 'licensed pack has rights text');

console.log((failures.length ? 'FAIL' : 'PASS') + ` ${manifest.song_id || '(unknown)'} ` +
  `events=${n} duration=${report.duration_seconds.toFixed(3)}s ` +
  `files=${Object.keys(manifest.files).length}`);
for (const x of notes) console.log(x);
for (const x of failures) console.log('FAIL ' + x);
if (failures.length) process.exit(1);
