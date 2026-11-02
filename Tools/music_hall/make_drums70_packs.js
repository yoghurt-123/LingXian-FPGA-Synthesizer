'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync, spawnSync } = require('child_process');
const { compile } = require('./compile_song');

const root = process.cwd();
const configs = [
  {
    source: 'music_packs/half_beast_full',
    variant: 'music_packs/half_beast_full_drums70',
    zip: 'music_packs/half_beast_full_drums70.fpgasong'
  },
  {
    source: 'music_packs/qing_tian_120s',
    variant: 'music_packs/qing_tian_120s_drums70',
    zip: 'music_packs/qing_tian_120s_drums70.fpgasong'
  }
];
const scale = 0.70;
const hash = b => crypto.createHash('sha256').update(b).digest('hex');

function readJson(file) { return JSON.parse(fs.readFileSync(file, 'utf8')); }
function writeJson(file, obj) { fs.writeFileSync(file, JSON.stringify(obj, null, 2) + '\n'); }
function copyFile(src, dst) { fs.copyFileSync(src, dst); }
function ensureDir(p) { fs.mkdirSync(p, { recursive: true }); }

function makeVariant(c) {
  const src = path.join(root, c.source);
  const dst = path.join(root, c.variant);
  fs.rmSync(dst, { recursive: true, force: true });
  ensureDir(path.join(dst, 'score'));
  for (const f of ['score/score.json', 'score/performance.bin', 'score/report.json', 'score/stage.json']) {
    copyFile(path.join(src, f), path.join(dst, f));
  }
  for (const f of ['LICENSE_SOURCE.md', 'manifest.json', 'package_summary.json']) {
    copyFile(path.join(src, f), path.join(dst, f));
  }

  const score = readJson(path.join(dst, 'score/score.json'));
  const drumTrack = score.tracks.find(t => t.instrument === 'drums');
  if (!drumTrack || !Array.isArray(drumTrack.hits)) throw new Error('drum track missing in ' + c.source);
  const before = drumTrack.hits.map(h => ({ ...h }));
  for (const h of drumTrack.hits) {
    if (Number(h.velocity) > 0) h.velocity = Math.max(1, Math.round(Number(h.velocity) * scale));
  }
  writeJson(path.join(dst, 'score/score.json'), score);

  const out = compile(score);
  fs.writeFileSync(path.join(dst, 'score/performance.bin'), out.performance);
  writeJson(path.join(dst, 'score/report.json'), out.report);

  const manifest = readJson(path.join(dst, 'manifest.json'));
  const fileNames = ['score/score.json', 'score/performance.bin', 'score/report.json', 'score/stage.json', 'LICENSE_SOURCE.md'];
  manifest.files = {};
  for (const f of fileNames) {
    const b = fs.readFileSync(path.join(dst, f));
    manifest.files[f] = { bytes: b.length, sha256: hash(b) };
  }
  manifest.event_count = out.report.event_count;
  manifest.duration_seconds = out.report.duration_seconds;
  manifest.max_events_in_50ms = out.report.max_events_in_50ms;
  writeJson(path.join(dst, 'manifest.json'), manifest);

  const temp = path.join(process.env.TEMP || process.env.TMP || '.', path.basename(dst));
  fs.rmSync(temp, { recursive: true, force: true });
  ensureDir(temp);
  for (const f of fileNames) {
    const target = path.join(temp, f);
    ensureDir(path.dirname(target));
    copyFile(path.join(dst, f), target);
  }
  copyFile(path.join(dst, 'manifest.json'), path.join(temp, 'manifest.json'));
  const zip = path.join(root, c.zip);
  fs.rmSync(zip, { force: true });
  const ps = `Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::CreateFromDirectory('${temp.replace(/'/g, "''")}','${zip.replace(/'/g, "''")}',[IO.Compression.CompressionLevel]::Optimal,$false)`;
  execFileSync('powershell', ['-NoProfile', '-Command', ps], { stdio: 'inherit' });
  const zb = fs.readFileSync(zip);
  const summary = readJson(path.join(dst, 'package_summary.json'));
  summary.file = path.basename(zip);
  summary.bytes = zb.length;
  summary.sha256 = hash(zb);
  summary.event_count = out.report.event_count;
  summary.duration_seconds = out.report.duration_seconds;
  summary.performance_bytes = out.report.estimated_performance_size;
  summary.drums_velocity_scale = scale;
  summary.drums_velocity_min_nonzero = 1;
  writeJson(path.join(dst, 'package_summary.json'), summary);
  return { config: c, score, before, out, zip, zipBytes: zb.length, zipSha: hash(zb) };
}

function compare(c, made) {
  const src = path.join(root, c.source);
  const dst = path.join(root, c.variant);
  const os = readJson(path.join(src, 'score/score.json'));
  const ns = readJson(path.join(dst, 'score/score.json'));
  const ot = {};
  const nt = {};
  for (const t of os.tracks) ot[t.instrument] = t;
  for (const t of ns.tracks) nt[t.instrument] = t;
  for (const inst of ['piano', 'guitar']) {
    if (JSON.stringify(ot[inst]) !== JSON.stringify(nt[inst])) throw new Error(inst + ' score data changed');
  }
  if (ot.drums.hits.length !== nt.drums.hits.length) throw new Error('drum hit count changed');
  for (let i = 0; i < ot.drums.hits.length; i++) {
    const a = { ...ot.drums.hits[i] };
    const b = { ...nt.drums.hits[i] };
    const av = a.velocity;
    delete a.velocity;
    delete b.velocity;
    if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error('drum non-velocity field changed');
    const expected = Number(ot.drums.hits[i].velocity) > 0 ? Math.max(1, Math.round(Number(ot.drums.hits[i].velocity) * scale)) : Number(ot.drums.hits[i].velocity);
    if (nt.drums.hits[i].velocity !== expected) throw new Error('drum velocity scale mismatch');
  }
  const op = fs.readFileSync(path.join(src, 'score/performance.bin'));
  const np = fs.readFileSync(path.join(dst, 'score/performance.bin'));
  const on = op.readUInt32LE(16);
  const nn = np.readUInt32LE(16);
  if (on !== nn) throw new Error('event count changed');
  if (op.readUInt32LE(20) !== np.readUInt32LE(20)) throw new Error('duration changed');
  let drums = 0;
  let changedDrums = 0;
  for (let i = 0; i < on; i++) {
    const oo = 32 + i * 8;
    const no = 32 + i * 8;
    if (op.readUInt32LE(oo) !== np.readUInt32LE(no)) throw new Error('timestamp changed at ' + i);
    if (op[oo + 4] !== np[no + 4]) throw new Error('event type changed at ' + i);
    if (op[oo + 5] !== np[no + 5]) throw new Error('event a changed at ' + i);
    if (op[oo + 7] !== np[no + 7]) throw new Error('event flags changed at ' + i);
    if (op[oo + 4] === 3) {
      drums++;
      if (op[oo + 6] !== np[no + 6]) changedDrums++;
    } else if (op[oo + 6] !== np[no + 6]) {
      throw new Error('non-drum velocity changed at ' + i);
    }
  }
  const v = spawnSync(process.execPath, [path.join(root, 'tools/music_hall/validate_pack.js'), dst], {
    cwd: root, encoding: 'utf8'
  });
  process.stdout.write(v.stdout || '');
  process.stderr.write(v.stderr || '');
  if (v.status !== 0) throw new Error('pack validation failed: ' + c.variant);
  return { event_count: on, drum_events: drums, drum_velocity_events_changed: changedDrums };
}

const results = [];
for (const c of configs) {
  const made = makeVariant(c);
  const checks = compare(c, made);
  results.push({
    source: c.source,
    variant_dir: c.variant,
    zip: path.join(root, c.zip),
    zip_bytes: made.zipBytes,
    zip_sha256: made.zipSha,
    event_count: checks.event_count,
    drum_events: checks.drum_events,
    drum_velocity_events_changed: checks.drum_velocity_events_changed,
    validation: 'PASS'
  });
}
console.log(JSON.stringify(results, null, 2));
