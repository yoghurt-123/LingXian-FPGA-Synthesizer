#!/usr/bin/env node
'use strict';
// Convert one signed decimal sample per line to mono 16-bit PCM WAV.
// The source sample rate is 52500000/1088 = 48253.676 Hz. WAV stores the
// nearest integer (48254 Hz); the README records the exact rational rate.
const fs = require('fs');
const path = require('path');
const text = process.argv[2];
const out = process.argv[3];
const rate = Number(process.argv[4] || 48254);
if (!text || !out) {
  console.error('usage: node text_to_wav.js <samples.txt> <out.wav> [rate=48254]');
  process.exit(2);
}
const lines = fs.readFileSync(text, 'utf8').split(/\r?\n/).filter(x => x.trim() !== '');
const n = lines.length;
const data = Buffer.alloc(n * 2);
let peak = 0, min = 0, max = 0, sum = 0, clip = 0, nonzero = 0;
for (let i = 0; i < n; i++) {
  let v = Number(lines[i]);
  if (!Number.isFinite(v)) v = 0;
  if (v > peak) peak = v;
  if (-v > peak) peak = -v;
  if (v < min) min = v;
  if (v > max) max = v;
  if (v > 32767 || v < -32768) clip++;
  const s = Math.max(-32768, Math.min(32767, Math.round(v)));
  if (s !== 0) nonzero++;
  sum += s;
  data.writeInt16LE(s, i * 2);
}
const header = Buffer.alloc(44);
header.write('RIFF', 0, 'ascii');
header.writeUInt32LE(36 + data.length, 4);
header.write('WAVE', 8, 'ascii');
header.write('fmt ', 12, 'ascii');
header.writeUInt32LE(16, 16);
header.writeUInt16LE(1, 20);   // PCM
header.writeUInt16LE(1, 22);   // mono
header.writeUInt32LE(rate, 24);
header.writeUInt32LE(rate * 2, 28);
header.writeUInt16LE(2, 32);
header.writeUInt16LE(16, 34);
header.write('data', 36, 'ascii');
header.writeUInt32LE(data.length, 40);
fs.writeFileSync(out, Buffer.concat([header, data]));
const report = {
  input: text,
  output: out,
  samples: n,
  rate,
  exact_rate_num: 52500000,
  exact_rate_den: 1088,
  exact_rate_hz: 52500000 / 1088,
  peak_abs: peak,
  min,
  max,
  mean: n ? sum / n : 0,
  clipped_samples: clip,
  nonzero_samples: nonzero
};
fs.writeFileSync(out + '.json', JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report));
