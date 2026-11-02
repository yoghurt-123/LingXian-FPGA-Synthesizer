#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const dir = process.argv[2];
if (!dir) {
  console.error('usage: node build_pack.js <pack-dir>');
  process.exit(2);
}
const abs = path.resolve(dir);
const required = ['score.json', 'performance.bin', 'report.json', 'stage.json'];
for (const f of required) {
  if (!fs.existsSync(path.join(abs, f))) {
    console.error('missing ' + f + '; run compile_song.js first');
    process.exit(1);
  }
}
const score = JSON.parse(fs.readFileSync(path.join(abs, 'score.json'), 'utf8'));
const report = JSON.parse(fs.readFileSync(path.join(abs, 'report.json'), 'utf8'));
if (report.errors && report.errors.length) {
  console.error('report has errors; refusing to build pack');
  process.exit(1);
}
if (score.song_id !== report.song_id) {
  console.error('score/report song_id mismatch');
  process.exit(1);
}
const files = {};
for (const f of required) {
  const b = fs.readFileSync(path.join(abs, f));
  files[f] = { bytes: b.length, sha256: crypto.createHash('sha256').update(b).digest('hex') };
}
const manifest = {
  format: 'fpgasong',
  format_version: '0.1',
  song_id: score.song_id,
  title: score.title,
  composer: score.composer,
  rights: score.rights,
  content_kind: score.content_kind || 'unknown',
  created: new Date().toISOString().slice(0, 10),
  target: {
    sample_rate_num: 52500000,
    sample_rate_den: 1088,
    sample_rate_hz: 52500000 / 1088,
    ppqn: score.ppqn,
    firmware_support: 'draft-not-supported-by-current-firmware'
  },
  capabilities_required: [
    'piano',
    'guitar-pluck',
    'drums',
    'timed-event-queue',
    'bulk-song-transfer'
  ],
  files,
  compile_report: 'report.json',
  limitations: report.unsupported,
  verification: {
    event_count: report.event_count,
    duration_seconds: report.duration_seconds,
    max_events_in_50ms: report.max_events_in_50ms,
    peak_concurrency_total: report.peak_concurrency.total,
    setup_note: 'The music-hall timed path is not implemented in the current firmware. This manifest is a design artifact until M1/M2.'
  }
};
fs.writeFileSync(path.join(abs, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log('wrote ' + path.join(abs, 'manifest.json'));
