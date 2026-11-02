#!/usr/bin/env node
'use strict';
// Minimal Standard MIDI File inspector used for M0 source verification.
const fs = require('fs');
const path = require('path');

function readVar(buf, pos) {
  let v = 0, n = 0;
  while (pos < buf.length) {
    const b = buf[pos++];
    v = (v << 7) | (b & 0x7f);
    n++;
    if (!(b & 0x80)) break;
    if (n > 4) throw new Error('bad variable-length quantity');
  }
  return { value: v, pos, bytes: n };
}
function str(buf, off, len) { return buf.subarray(off, off + len).toString('ascii'); }
function u32(buf, off) { return buf.readUInt32BE(off); }
function u16(buf, off) { return buf.readUInt16BE(off); }

function inspect(file) {
  const b = fs.readFileSync(file);
  if (str(b, 0, 4) !== 'MThd') throw new Error('not a MIDI file');
  const headerLen = u32(b, 4);
  const format = u16(b, 8);
  const ntracks = u16(b, 10);
  const division = u16(b, 12);
  let pos = 8 + headerLen;
  const tracks = [];
  let tempo = [{ tick: 0, usPerQuarter: 500000 }];
  let timeSig = null;
  for (let ti = 0; ti < ntracks && pos + 8 <= b.length; ti++) {
    if (str(b, pos, 4) !== 'MTrk') throw new Error('expected MTrk at ' + pos);
    const len = u32(b, pos + 4);
    const start = pos + 8;
    const end = start + len;
    let p = start, tick = 0, running = 0;
    const notesOn = new Map();
    const notes = [];
    const progs = new Set();
    const channels = new Set();
    let name = null;
    let maxOverlap = 0;
    const events = [];
    while (p < end) {
      const dt = readVar(b, p); tick += dt.value; p = dt.pos;
      if (p >= end) break;
      let status = b[p];
      if (status < 0x80) {
        if (!running) throw new Error('running status without status at ' + p);
        status = running;
      } else {
        p++;
        if (status < 0xf0) running = status;
      }
      if (status === 0xff) {
        const type = b[p++];
        const l = readVar(b, p); p = l.pos;
        const data = b.subarray(p, p + l.value);
        p += l.value;
        if (type === 0x03) name = data.toString('utf8');
        if (type === 0x51 && l.value === 3) {
          tempo.push({ tick, usPerQuarter: (data[0] << 16) | (data[1] << 8) | data[2] });
        }
        if (type === 0x58 && l.value >= 2) {
          timeSig = { tick, numerator: data[0], denominator: 1 << data[1] };
        }
        if (type === 0x2f) break;
        continue;
      }
      if (status === 0xf0 || status === 0xf7) {
        const l = readVar(b, p); p = l.pos + l.value; continue;
      }
      const cmd = status & 0xf0;
      const ch = status & 0x0f;
      if (cmd === 0xc0 || cmd === 0xd0) {
        const d = b[p++];
        if (cmd === 0xc0) progs.add(d);
        continue;
      }
      const d1 = b[p++];
      let d2;
      if (cmd !== 0xd0) d2 = b[p++];
      channels.add(ch);
      if (cmd === 0x90 && d2 > 0) {
        const key = `${ch}:${d1}`;
        notesOn.set(key, { tick, key: d1, ch, vel: d2 });
        let active = 0;
        for (const n of notesOn.values()) if (n) active++;
        maxOverlap = Math.max(maxOverlap, active);
      } else if (cmd === 0x80 || (cmd === 0x90 && d2 === 0)) {
        const key = `${ch}:${d1}`;
        const n = notesOn.get(key);
        if (n) {
          notesOn.delete(key);
          notes.push({ tick: n.tick, key: n.key, ch, vel: n.vel, dur: tick - n.tick, end: tick });
          events.push({ tick: n.tick, end: tick, key: n.key, ch, vel: n.vel });
        }
      }
    }
    // Treat notes still sounding at track end as closed there.
    for (const n of notesOn.values()) {
      notes.push({ tick: n.tick, key: n.key, ch: n.ch, vel: n.vel, dur: tick - n.tick, end: tick });
    }
    tracks.push({ index: ti, name, format, division, len, channels: [...channels], progs: [...progs], notes, maxOverlap, endTick: tick });
    pos = end;
  }
  // Absolute-to-seconds using tempo map.
  const usPerTick = tempo.map(x => x);
  function seconds(tick) {
    let t = 0;
    for (let i = 0; i < tempo.length; i++) {
      const s = tempo[i].tick;
      const e = i + 1 < tempo.length ? tempo[i + 1].tick : Infinity;
      if (tick <= s) break;
      const u = Math.min(tick, e) - s;
      t += u * tempo[i].usPerQuarter / division / 1e6;
      if (tick <= e) break;
    }
    return t;
  }
  return { file, format, ntracks, division, tempo, timeSig, tracks, seconds };
}

function summarize(file) {
  const m = inspect(file);
  const out = {
    file,
    format: m.format,
    division: m.division,
    tracks: m.tracks.map(t => {
      const keys = t.notes.map(n => n.key);
      const vels = t.notes.map(n => n.vel);
      const unmappedDrums = [...new Set(t.notes.filter(n => n.ch === 9).map(n => n.key))].filter(k => ![35,36,38,40,42,46,49,51,50,45,47,48].includes(k));
      return {
        index: t.index,
        name: t.name,
        channels: t.channels,
        programs: t.progs,
        notes: t.notes.length,
        midiMin: keys.length ? Math.min(...keys) : null,
        midiMax: keys.length ? Math.max(...keys) : null,
        velocityMin: vels.length ? Math.min(...vels) : null,
        velocityMax: vels.length ? Math.max(...vels) : null,
        noteOnMin: t.notes.length ? Math.min(...t.notes.map(n => n.tick)) : null,
        noteOnMax: t.notes.length ? Math.max(...t.notes.map(n => n.tick)) : null,
        endTick: t.endTick,
        maxOverlap: t.maxOverlap,
        durationSeconds: t.notes.length ? (t.notes.reduce((a, n) => Math.max(a, n.end), 0) * 60 / 120 / m.division) : 0,
        unmappedDrums
      };
    }),
    tempo: m.tempo,
    timeSig: m.timeSig,
    durationSeconds: m.tracks.reduce((a, t) => Math.max(a, t.endTick), 0) * 60 / 120 / m.division
  };
  return out;
}

if (require.main === module) {
  const f = process.argv[2];
  if (!f) { console.error('usage: node inspect_midi.js <file.mid>'); process.exit(2); }
  const s = summarize(f);
  console.log(JSON.stringify(s, null, 2));
}
module.exports = { inspect, summarize };
