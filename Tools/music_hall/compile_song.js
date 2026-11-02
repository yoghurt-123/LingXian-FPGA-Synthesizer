#!/usr/bin/env node
/*
 * M0 score compiler / adapter prototype.
 *
 * This is intentionally a draft: it emits the proposed FPGS v1 performance
 * stream, not a format consumed by the current FPGA firmware.  It never writes
 * to the FPGA project or the default bitstream.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const SAMPLE_NUM = 52500000;
const SAMPLE_DEN = 1088;
const SAMPLE_RATE = SAMPLE_NUM / SAMPLE_DEN;
const FPGS_MAGIC = Buffer.from('FPGS', 'ascii');
const FPGS_VERSION = 1;
const EVENT_SIZE = 8;
const HEADER_SIZE = 32;

const T = {
  PIANO_ON: 1,
  PIANO_OFF: 2,
  DRUM: 3,
  GUITAR_PLUCK: 4,
  GUITAR_CHORD: 5,
  PARAM: 6,
  RELEASE_ALL: 7,
  ALL_OFF: 8
};
const PARAM = { OCTAVE: 0, FRET: 1, PALM: 2, OVERDRIVE: 3, REVERB: 4, DAMPING: 5, PEDAL: 6 };

const PIANO_KEYS = [
  { key: 0, midi: 60, name: 'C4' },
  { key: 1, midi: 62, name: 'D4' },
  { key: 2, midi: 64, name: 'E4' },
  { key: 3, midi: 65, name: 'F4' },
  { key: 4, midi: 67, name: 'G4' },
  { key: 5, midi: 69, name: 'A4' },
  { key: 6, midi: 71, name: 'B4' },
  { key: 7, midi: 72, name: 'C5' },
  { key: 8, midi: 74, name: 'D5' },
  { key: 9, midi: 61, name: 'C#4' },
  { key: 10, midi: 63, name: 'D#4' },
  { key: 11, midi: 66, name: 'F#4' },
  { key: 12, midi: 68, name: 'G#4' },
  { key: 13, midi: 70, name: 'A#4' },
  { key: 14, midi: 73, name: 'C#5' },
  { key: 15, midi: 75, name: 'D#5' }
];

function u32(buf, off, v) { buf.writeUInt32LE(v >>> 0, off); }
function u16(buf, off, v) { buf.writeUInt16LE(v & 0xffff, off); }

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return (c ^ 0xffffffff) >>> 0;
}

function fnv32(s) {
  let h = 0x811c9dc5;
  for (const ch of Buffer.from(String(s), 'utf8')) {
    h ^= ch;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
const VELOCITY_CALIBRATION = {
  piano:  { gain: 1.00, gamma: 1.00, note: 'piano: linear source intent; not equal-loudness to other tracks' },
  guitar: { gain: 0.93, gamma: 0.98, note: 'guitar: slightly compressed/attenuated calibration; separate from piano' },
  drums:  { gain: 1.00, gamma: 0.90, note: 'drums: expanded low end; separate from piano/guitar' }
};
function q15Velocity(v, instrument) {
  if (!Number.isFinite(v) || v <= 0) return 1;
  const c = VELOCITY_CALIBRATION[instrument] || VELOCITY_CALIBRATION.piano;
  const x = clamp(v, 0, 127) / 127;
  return clamp(Math.round(Math.pow(x, c.gamma) * c.gain * 15), 1, 15);
}

function pianoMap(midi) {
  const candidates = [];
  for (const p of PIANO_KEYS) {
    for (const shift of [0, -12, 12]) {
      if (p.midi + shift === midi) {
        const octave = shift === -12 ? 0 : shift === 0 ? 1 : 2;
        // Prefer no octave shift; then prefer the lower key id for stable output.
        candidates.push({ key: p.key, octave, shift, name: p.name });
      }
    }
  }
  candidates.sort((a, b) => Math.abs(a.shift) - Math.abs(b.shift) || a.key - b.key);
  return candidates[0] || null;
}

function midiName(m) {
  const n = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
  return `${n[((m % 12) + 12) % 12]}${Math.floor(m / 12) - 1}`;
}

function buildTempo(score) {
  const ppqn = score.ppqn;
  if (!Number.isInteger(ppqn) || ppqn <= 0) throw new Error('ppqn must be a positive integer');
  const map = (score.tempo_map || [{ tick: 0, bpm: 72 }])
    .map(x => ({ tick: Math.round(x.tick), bpm: Number(x.bpm) }))
    .sort((a, b) => a.tick - b.tick);
  if (!map.length || map[0].tick !== 0) throw new Error('tempo_map must start at tick 0');
  for (const x of map) if (!(x.bpm > 0)) throw new Error('tempo must be positive');
  return map;
}

function makeTimeConverter(score) {
  const tempo = buildTempo(score);
  const ppqn = score.ppqn;
  return function sampleAt(tick) {
    let lastTick = 0;
    let lastSample = 0;
    for (let i = 0; i < tempo.length; i++) {
      const start = tempo[i].tick;
      const end = i + 1 < tempo.length ? tempo[i + 1].tick : Infinity;
      if (tick < start) break;
      const upto = Math.min(tick, end);
      const delta = upto - lastTick;
      if (delta > 0) {
        lastSample += Math.round(delta * 60 * SAMPLE_NUM / (tempo[i].bpm * ppqn * SAMPLE_DEN));
        lastTick = upto;
      }
      if (tick <= end) break;
    }
    return lastSample;
  };
}

function newReport(score) {
  return {
    schema_version: '0.1',
    song_id: score.song_id || null,
    title: score.title || null,
    content_kind: score.content_kind || null,
    sample_rate_num: SAMPLE_NUM,
    sample_rate_den: SAMPLE_DEN,
    sample_rate_hz: SAMPLE_RATE,
    ppqn: score.ppqn,
    tempo_map: score.tempo_map,
    event_count: 0,
    duration_ticks: score.duration_ticks || 0,
    duration_samples: 0,
    duration_seconds: 0,
    estimated_performance_size: 0,
    max_events_per_second: 0,
    max_events_in_50ms: 0,
    densest_group: { time_samples: 0, time_seconds: 0, count: 0, types: [] },
    peak_concurrency: { piano: 0, guitar: 0, drums: 0, total: 0 },
    peak_concurrency_time: { samples: 0, seconds: 0 },
    velocity_mapping: {
      source: 'MIDI 0..127',
      piano: VELOCITY_CALIBRATION.piano.note,
      guitar: VELOCITY_CALIBRATION.guitar.note,
      drums: VELOCITY_CALIBRATION.drums.note,
      curves: VELOCITY_CALIBRATION
    },
    checks: [],
    warnings: [],
    errors: [],
    unsupported: [
      'Current FPGA firmware has no timed event queue or bulk score transfer.',
      'A2/A3 are reserved ADC parameters; no real echo/delay is implemented.',
      'Guitar notes have natural decay and no per-note note-off; score duration is intent only.',
      'Drums are one-shots with no note-off/duration.',
      'Guitar overdrive/reverb and expression are shared global state, not per-note automation.'
    ],
    queue_estimate: null
  };
}

function addError(report, msg) { report.errors.push(msg); }
function addWarning(report, msg) { report.warnings.push(msg); }
function addCheck(report, name, ok, detail) { report.checks.push({ name, ok: !!ok, detail: detail || '' }); }

function compile(score) {
  const report = newReport(score);
  const sampleAt = makeTimeConverter(score);
  const events = [];
  const seqByTime = new Map();
  let nextOrder = 0;

  function push(tick, priority, trackOrder, type, a, b, flags, label) {
    const time = sampleAt(Math.max(0, Math.round(tick)));
    events.push({ tick, time, priority, trackOrder, order: nextOrder++, type, a, b, flags: flags || 0, label: label || '' });
  }

  const tracks = Array.isArray(score.tracks) ? score.tracks : [];
  const pianoTrack = tracks.find(t => t.instrument === 'piano');
  const guitarTrack = tracks.find(t => t.instrument === 'guitar');
  const drumTrack = tracks.find(t => t.instrument === 'drums');

  // Piano: one voice per NOTE_SEL key; global octave is latched at trigger.
  let pianoOctave = 1;
  const pianoIntervals = [];
  if (pianoTrack) {
    for (const n of pianoTrack.notes || []) {
      const start = Math.round(n.start_tick);
      const dur = Math.max(0, Math.round(n.duration_ticks || 0));
      if (start < 0 || start + dur > (score.duration_ticks || Infinity)) {
        addError(report, `piano note outside duration: start=${start}, duration=${dur}, midi=${n.midi}`);
        continue;
      }
      const map = pianoMap(n.midi);
      if (!map) {
        addError(report, `piano pitch ${n.midi} (${midiName(n.midi)}) is outside the FPGA C3..D#6 16-key window`);
        continue;
      }
      if (dur <= 0) addError(report, `piano note at tick ${start} has zero duration`);
      const vel = q15Velocity(n.velocity, "piano");
      if (map.octave !== pianoOctave) {
        push(start, 10, 0, T.PARAM, PARAM.OCTAVE, map.octave, 0, `piano octave=${map.octave}`);
        pianoOctave = map.octave;
      }
      push(start, 30, 0, T.PIANO_ON, map.key, vel, 0, `piano ${midiName(n.midi)} vel=${vel}`);
      push(start + dur, 20, 0, T.PIANO_OFF, map.key, 0, 0, `piano off key=${map.key}`);
      pianoIntervals.push({ start, end: start + dur, startSample: sampleAt(start), endSample: sampleAt(start + dur), key: map.key, midi: n.midi, label: midiName(n.midi) });
    }
  }

  // Piano interval checks: 16-slot limit, one voice per key, release lockout.
  const byKey = new Map();
  for (const n of pianoIntervals) {
    if (!byKey.has(n.key)) byKey.set(n.key, []);
    byKey.get(n.key).push(n);
  }
  for (const [key, list] of byKey) {
    list.sort((a, b) => a.start - b.start);
    for (let i = 0; i < list.length; i++) {
      const a = list[i];
      for (let j = i + 1; j < list.length; j++) {
        const b = list[j];
        if (b.start < a.end) addError(report, `piano same-key overlap key=${key} ${a.label}->${b.label}`);
        // Existing core ignores a new trigger while the previous external release is active (~1024 samples).
        const releaseSamples = 1024;
        const gapSamples = b.startSample - a.endSample;
        if (b.start >= a.end && gapSamples < releaseSamples) {
          addWarning(report, `piano same-key retrigger may be swallowed by ~1024-sample release: key=${key} ${a.label}->${b.label} gapSamples=${gapSamples} start=${a.startSample}/${b.startSample}`);
        }
      }
    }
  }

  // Guitar: global fret/palm latched before a pluck; six string IDs.
  let guitarFret = 0;
  let guitarPalm = 0;
  let guitarDurationWarned = false;
  const guitarIntervals = [];
  if (guitarTrack) {
    for (const n of guitarTrack.notes || []) {
      const start = Math.round(n.start_tick);
      const dur = Math.max(0, Math.round(n.duration_ticks || 0));
      if (start < 0 || start + dur > (score.duration_ticks || Infinity)) {
        addError(report, `guitar note outside duration: start=${start}, duration=${dur}`);
        continue;
      }
      const string = Number(n.string);
      const fret = Number(n.fret);
      if (!Number.isInteger(string) || string < 0 || string > 5) {
        addError(report, `guitar string ${n.string} outside 0..5`);
        continue;
      }
      if (!Number.isInteger(fret) || fret < 0 || fret > 12) {
        addError(report, `guitar fret ${n.fret} outside 0..12`);
        continue;
      }
      if (dur > 0 && !guitarDurationWarned) {
        addWarning(report, 'guitar score durations are intent only; hardware has natural decay and no per-note note-off');
        guitarDurationWarned = true;
      }
      const vel = q15Velocity(n.velocity, "guitar");
      if (fret !== guitarFret) {
        push(start, 10, 1, T.PARAM, PARAM.FRET, fret, 0, `guitar fret=${fret}`);
        guitarFret = fret;
      }
      const palm = n.palm ? 1 : 0;
      if (palm !== guitarPalm) {
        push(start, 10, 1, T.PARAM, PARAM.PALM, palm, 0, `guitar palm=${palm}`);
        guitarPalm = palm;
      }
      push(start, 30, 1, T.GUITAR_PLUCK, string, vel, (fret & 0xf) | (palm << 4), `guitar string=${string} fret=${fret} vel=${vel}`);
      guitarIntervals.push({ start, end: start + Math.max(1, dur), startSample: sampleAt(start), endSample: sampleAt(start + Math.max(1, dur)), string, fret, label: `string${string}/fret${fret}` });
    }
  }

  // Drums: one-shots, no duration; same-tick velocity is the latest latched value.
  const drumGroups = new Map();
  if (drumTrack) {
    for (const h of drumTrack.hits || []) {
      const start = Math.round(h.tick);
      if (start < 0 || start > (score.duration_ticks || Infinity)) {
        addError(report, `drum hit outside duration at tick ${start}`);
        continue;
      }
      const drum = Number(h.drum);
      if (!Number.isInteger(drum) || drum < 0 || drum > 8) {
        addError(report, `drum id ${h.drum} outside 0..8`);
        continue;
      }
      const vel = q15Velocity(h.velocity, "drums");
      push(start, 30, 2, T.DRUM, drum, vel, 0, `drum ${drum} vel=${vel}`);
      if (!drumGroups.has(start)) drumGroups.set(start, []);
      drumGroups.get(start).push({ drum, vel });
    }
  }

  // Same-tick drum IDs share the firmware's one latched velocity value.
  for (const [tick, list] of drumGroups) {
    if (list.length > 9) addError(report, `more than 9 drum hits at tick ${tick}`);
    const velocities = new Set(list.map(x => x.vel));
    if (velocities.size > 1) addWarning(report, `drums at tick ${tick} have different velocities ${[...velocities].join(',')}; firmware has one drum velocity latch`);
  }

  // Deterministic same-time ordering: parameters, note-off, triggers, drums.
  events.sort((x, y) => x.time - y.time || x.priority - y.priority || x.trackOrder - y.trackOrder || x.order - y.order);

  // Group flags: same absolute sample is one execution group.
  for (let i = 0; i < events.length;) {
    let j = i + 1;
    while (j < events.length && events[j].time === events[i].time) j++;
    events[i].flags |= 0x20;
    events[j - 1].flags |= 0x40;
    i = j;
  }

  // Polyphony and event density.
  const allTimes = [...new Set(events.map(e => e.time))].sort((a, b) => a - b);
  for (const t of allTimes) {
    const p = pianoIntervals.filter(n => n.startSample <= t && t < n.endSample).length;
    const g = guitarIntervals.filter(n => n.startSample <= t && t < n.endSample).length;
    const d = drumGroups.has(t) ? drumGroups.get(t).length : 0;
    const total = p + g + d;
    if (p > 16) addError(report, `piano concurrency ${p} > 16 at sample ${t}`);
    if (p > report.peak_concurrency.piano) report.peak_concurrency.piano = p;
    if (g > report.peak_concurrency.guitar) report.peak_concurrency.guitar = g;
    if (d > report.peak_concurrency.drums) report.peak_concurrency.drums = d;
    if (total > report.peak_concurrency.total) {
      report.peak_concurrency.total = total;
      report.peak_concurrency_time = { samples: t, seconds: t / SAMPLE_RATE };
    }
  }
  const guitarPoolTimes = new Set();
  for (const n of guitarIntervals) {
    for (const t of allTimes) {
      if (n.startSample <= t && t < n.endSample && n.string > 0) guitarPoolTimes.add(t);
    }
  }
  for (const t of guitarPoolTimes) {
    const pool = guitarIntervals.filter(n => n.string > 0 && n.startSample <= t && t < n.endSample).length;
    if (pool > 3) addError(report, `guitar pool concurrency ${pool} > 3 at sample ${t}`);
  }

  // Density buckets in the audio sample domain.
  const perSecond = new Map();
  const per50ms = new Map();
  for (const e of events) {
    const s = Math.floor(e.time / SAMPLE_RATE);
    perSecond.set(s, (perSecond.get(s) || 0) + 1);
    const b = Math.floor(e.time / (SAMPLE_RATE * 0.05));
    per50ms.set(b, (per50ms.get(b) || 0) + 1);
  }
  report.max_events_per_second = Math.max(0, ...perSecond.values());
  report.max_events_in_50ms = Math.max(0, ...per50ms.values());

  // Densest same-time group.
  const groupMap = new Map();
  for (const e of events) {
    if (!groupMap.has(e.time)) groupMap.set(e.time, []);
    groupMap.get(e.time).push(e);
  }
  for (const [time, list] of groupMap) {
    if (list.length > report.densest_group.count) {
      report.densest_group = {
        time_samples: time,
        time_seconds: time / SAMPLE_RATE,
        count: list.length,
        types: [...new Set(list.map(e => e.type))]
      };
    }
  }

  const lastEventSamples = events.length ? events[events.length - 1].time : 0;
  report.event_count = events.length;
  report.duration_samples = Math.max(lastEventSamples, sampleAt(score.duration_ticks || 0));
  report.duration_seconds = report.duration_samples / SAMPLE_RATE;
  report.estimated_performance_size = HEADER_SIZE + events.length * EVENT_SIZE;
  report.max_simultaneous_events = report.densest_group.count;
  report.queue_estimate = {
    fpga_slots: Math.max(64, Math.ceil(report.max_events_in_50ms * 16 / 64) * 64),
    basis: '64-slot floor; sample says a 50 ms burst of ' + report.max_events_in_50ms +
      ' events. M1 must replace this estimate with queue-jitter measurements.',
    record_bytes: EVENT_SIZE
  };

  addCheck(report, 'score schema', score.schema_version === '0.1', String(score.schema_version));
  addCheck(report, 'piano range', !report.errors.some(e => e.startsWith('piano pitch')), 'C3..D#6, 16-key window');
  addCheck(report, 'guitar range', !report.errors.some(e => e.startsWith('guitar string') || e.startsWith('guitar fret')), 'strings 0..5, fret 0..12');
  addCheck(report, 'drum ids', !report.errors.some(e => e.startsWith('drum id')), '0..8');
  addCheck(report, 'piano polyphony', !report.errors.some(e => e.includes('piano concurrency')), '<=16');
  addCheck(report, 'guitar pool', !report.errors.some(e => e.includes('guitar pool')), '<=3 pool + E2');
  addCheck(report, 'same-key release pairing', !report.errors.some(e => e.includes('same-key overlap')), 'no overlapping same-key piano notes');
  addCheck(report, 'parameter-before-trigger', true, 'compiler emits global parameters before dependent triggers');
  addCheck(report, 'same-time ordering', true, 'parameter -> note-off -> trigger/drum');
  addCheck(report, 'velocity mapping', true, 'per-instrument MIDI/127 -> 1..15 mapping records source intent');
  addCheck(report, 'timing conversion', true, 'absolute samples from score ticks; 52500000/1088 Hz');

  const performance = Buffer.alloc(HEADER_SIZE + events.length * EVENT_SIZE);
  FPGS_MAGIC.copy(performance, 0);
  performance[4] = FPGS_VERSION;
  performance[5] = HEADER_SIZE;
  performance[6] = EVENT_SIZE;
  performance[7] = 0;
  u32(performance, 8, SAMPLE_NUM);
  u16(performance, 12, SAMPLE_DEN);
  u16(performance, 14, 0);
  u32(performance, 16, events.length);
  u32(performance, 20, report.duration_samples);
  u32(performance, 24, 0); // checksum filled below
  u32(performance, 28, fnv32(score.song_id || ''));

  let off = HEADER_SIZE;
  for (const e of events) {
    u32(performance, off, e.time);
    performance[off + 4] = e.type;
    performance[off + 5] = e.a & 0xff;
    performance[off + 6] = e.b & 0xff;
    performance[off + 7] = e.flags & 0xff;
    off += EVENT_SIZE;
  }
  u32(performance, 24, crc32(performance.subarray(HEADER_SIZE)));

  report.sha256_performance = crypto.createHash('sha256').update(performance).digest('hex');
  report.event_type_counts = events.reduce((m, e) => (m[e.type] = (m[e.type] || 0) + 1, m), {});
  report.event_sample_span = events.length ? { first: events[0].time, last: events[events.length - 1].time } : null;

  return { performance, report, events };
}

function main() {
  const inPath = process.argv[2];
  const outDir = process.argv[3] || path.dirname(inPath);
  if (!inPath) {
    console.error('usage: node compile_song.js <score.json> [output-dir]');
    process.exit(2);
  }
  const score = JSON.parse(fs.readFileSync(inPath, 'utf8'));
  const { performance, report } = compile(score);
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, 'performance.bin'), performance);
  fs.writeFileSync(path.join(outDir, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(`events=${report.event_count} duration=${report.duration_seconds.toFixed(3)}s ` +
    `max50ms=${report.max_events_in_50ms} maxConc=${report.peak_concurrency.total} ` +
    `size=${report.estimated_performance_size} errors=${report.errors.length} warnings=${report.warnings.length}`);
  if (report.errors.length) {
    for (const e of report.errors) console.error('ERROR ' + e);
    process.exit(1);
  }
}

module.exports = { compile, pianoMap, sampleAt: null, SAMPLE_RATE, SAMPLE_NUM, SAMPLE_DEN, T, PARAM };

if (require.main === module) main();
