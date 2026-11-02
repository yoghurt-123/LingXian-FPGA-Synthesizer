#!/usr/bin/env node
// Generate an original 8-bar technical etude for M0 format/compiler testing.
// This is deliberately NOT a transcription or arrangement of "Let It Be".
const fs = require('fs');
const path = require('path');

const PPQN = 480;
const BEAT = PPQN;
const BAR = 4 * BEAT;
const BARS = 8;
const BPM = 72;
const SONG_ID = 'm0-technical-demo';
const TITLE = 'M0 三乐器技术样片（原创，不是 Let It Be）';

const notes = [];
const guitar = [];
const drums = [];

function addPiano(bar, beat, durationBeats, midi, velocity) {
  notes.push({
    start_tick: (bar - 1) * BAR + beat * BEAT,
    duration_ticks: Math.round(durationBeats * BEAT),
    midi,
    velocity
  });
}

function addGuitar(bar, beat, durationBeats, string, fret, velocity, palm) {
  guitar.push({
    start_tick: (bar - 1) * BAR + beat * BEAT,
    duration_ticks: Math.round(durationBeats * BEAT),
    string, fret, velocity, palm: !!palm, technique: 'pluck'
  });
}

function addDrum(bar, beat, drum, velocity) {
  drums.push({
    tick: (bar - 1) * BAR + Math.round(beat * BEAT),
    drum, velocity
  });
}

// Original melodic etude: two-note piano texture plus guitar punctuation.
// Pitch material stays inside the FPGA's C3..D#6 / 16-key window.
const melody = [
  [1, 0, 1, 67, 96], [1, 1, 1, 69, 92], [1, 2, 1, 67, 88], [1, 3, 1, 64, 84],
  [2, 0, 1, 62, 90], [2, 1, 1, 64, 88], [2, 2, 1, 67, 94], [2, 3, 1, 69, 98],
  [3, 0, 1, 72, 102], [3, 1, 1, 71, 94], [3, 2, 1, 69, 90], [3, 3, 1, 67, 86],
  [4, 0, 1, 64, 88], [4, 1, 1, 62, 84], [4, 2, 1, 60, 82], [4, 3, 1, 62, 86],
  [5, 0, 1, 64, 94], [5, 1, 1, 67, 98], [5, 2, 1, 69, 96], [5, 3, 1, 67, 90],
  [6, 0, 1, 64, 88], [6, 1, 1, 62, 84], [6, 2, 1, 60, 82], [6, 3, 1, 64, 88],
  [7, 0, 1, 65, 92], [7, 1, 1, 69, 100], [7, 2, 1, 67, 94], [7, 3, 1, 64, 88],
  [8, 0, 1, 62, 90], [8, 1, 1, 64, 84], [8, 2, 2, 60, 88]
];
melody.forEach(([bar, beat, dur, midi, vel]) => addPiano(bar, beat, dur, midi, vel));

// Sparse second piano voice in the same octave; durations end before any
// melody note on the same key starts. This exercises the 16-key voice model.
const harmony = [
  [1, 2, 1, 62, 72], [2, 2, 1, 62, 70], [3, 2, 1, 64, 68], [4, 2, 1, 67, 70],
  [5, 2, 1, 60, 70], [6, 2, 1, 67, 68], [7, 2, 1, 60, 68], [8, 2, 1, 67, 70]
];
harmony.forEach(([bar, beat, dur, midi, vel]) => addPiano(bar, beat, dur, midi, vel));

// Guitar: low E2 support plus a restrained upper-string answer.
for (let bar = 1; bar <= 8; bar++) {
  addGuitar(bar, 0, 2, 0, 0, 88 + (bar % 3) * 4, false);
  addGuitar(bar, 2, 1, [1, 2, 3, 4][(bar - 1) % 4], 0, 82 + (bar % 4) * 3, false);
}
addGuitar(7, 3, 1, 5, 3, 88, false);
addGuitar(7, 3.5, 1, 4, 2, 82, false);
addGuitar(8, 3, 1, 5, 5, 92, false);

// Nine-drum vocabulary with varied velocities and a small fill.
for (let bar = 1; bar <= 8; bar++) {
  addDrum(bar, 0, 0, 112 + (bar % 2) * 5);
  addDrum(bar, 2, 0, 98 + (bar % 3) * 4);
  addDrum(bar, 1, 1, 96 + (bar % 4) * 5);
  addDrum(bar, 3, 1, 104 + (bar % 3) * 4);
  const hatVel = 70 + (bar % 3) * 6;
  for (let eighth = 0; eighth < 8; eighth++) {
    // Keep kick+hat simultaneous groups at one velocity.
    const vel = eighth === 0 ? 112 + (bar % 2) * 5 : hatVel;
    if (eighth === 7 && bar === 4) addDrum(bar, 3.5, 3, 88); // open hat
    else if (bar === 8 && eighth >= 6) { /* fill replaces closed hats */ }
    else addDrum(bar, eighth * 0.5, 2, vel);
  }
  if (bar === 1) addDrum(bar, 0, 5, 112); // crash; same velocity group
  if (bar === 8) addDrum(bar, 0, 5, 114);
  if (bar === 4) addDrum(bar, 3, 4, 76); // ride; same velocity group
  if (bar === 8) {
    addDrum(bar, 3, 6, 100); // high tom
    addDrum(bar, 3.25, 8, 96); // mid tom
    addDrum(bar, 3.5, 7, 104); // low tom
  }
}

// The current drum engine latches one velocity for all simultaneous drum bits.
// Keep each same-tick group at one velocity; vary velocity between groups.
const groupedDrums = new Map();
for (const h of drums) {
  if (!groupedDrums.has(h.tick)) groupedDrums.set(h.tick, []);
  groupedDrums.get(h.tick).push(h);
}
for (const group of groupedDrums.values()) {
  const v = Math.max(...group.map(h => h.velocity));
  group.forEach(h => { h.velocity = v; });
}

const score = {
  schema_version: '0.1',
  song_id: SONG_ID,
  title: TITLE,
  composer: 'Project M0 original technical demo',
  rights: 'Original technical demo for format validation; not Let It Be; no third-party score or recording is included.',
  content_kind: 'technical_demo_not_let_it_be',
  ppqn: PPQN,
  time_signature: { numerator: 4, denominator: 4 },
  tempo_map: [{ tick: 0, bpm: BPM }],
  duration_ticks: BARS * BAR,
  tracks: [
    { id: 'piano', instrument: 'piano', notes },
    { id: 'guitar', instrument: 'guitar', notes: guitar },
    { id: 'drums', instrument: 'drums', hits: drums }
  ],
  sections: [
    { start_bar: 1, end_bar: 2, title: '技术样片 A：钢琴主题' },
    { start_bar: 3, end_bar: 4, title: '技术样片 B：吉他进入' },
    { start_bar: 5, end_bar: 6, title: '技术样片 C：鼓组推进' },
    { start_bar: 7, end_bar: 8, title: '技术样片 D：三轨收束与过门' }
  ]
};

const out = path.join(__dirname, '..', '..', 'music_packs', 'm0_technical_demo');
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'score.json'), JSON.stringify(score, null, 2) + '\n');
console.log(`wrote ${path.join(out, 'score.json')} (piano=${notes.length}, guitar=${guitar.length}, drums=${drums.length})`);
