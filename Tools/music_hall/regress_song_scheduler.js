const fs = require('fs');
const Fs = 52500000 / 1088;
const LATE = 48254;

function run(file) {
  const b = fs.readFileSync(file);
  if (b.toString('ascii', 0, 4) !== 'FPGS') throw new Error('bad magic ' + file);
  const n = b.readUInt32LE(16);
  const dur = b.readUInt32LE(20);
  const ev = [];
  for (let i = 0; i < n; i++) {
    const o = 32 + i * 8;
    ev.push({ t: b.readUInt32LE(o), type: b[o + 4], a: b[o + 5], b: b[o + 6], flags: b[o + 7] });
  }

  const Q = new Array(128);
  let head = 0, tail = 0, q = 0, next = 0;
  let emitted = 0, legacy = 0, under = 0, late = 0, maxq = 0;

  function enqueue() {
    while (next < n && q < 128) {
      Q[tail] = ev[next++];
      tail = (tail + 1) % 128;
      q++;
      if (q > maxq) maxq = q;
    }
  }

  for (let pos = 0; pos <= dur; pos++) {
    enqueue();
    if (pos > 0 && q === 0 && emitted < n) under++;
    while (q > 0) {
      const e = Q[head];
      if (e.t + LATE < pos) {
        head = (head + 1) % 128;
        q--;
        emitted++;
        legacy++;
        late++;
        enqueue();
        continue;
      }
      if (e.t > pos) break;
      head = (head + 1) % 128;
      q--;
      emitted++;
      legacy += e.type === 4 ? 3 : 1;
      enqueue();
    }
  }

  let order = true;
  for (let i = 1; i < n; i++) if (ev[i].t < ev[i - 1].t) order = false;
  const out = {
    file,
    event_count: n,
    duration_samples: dur,
    duration_seconds: +(dur / Fs).toFixed(3),
    emitted,
    legacy_frames: legacy,
    last_event_time: +(ev[n - 1].t / Fs).toFixed(3),
    last_event_index: n - 1,
    order_monotonic: order,
    underflow_samples: under,
    late_drops: late,
    max_queue_depth: maxq,
    end_reason: 'duration',
    all_events_consumed: emitted === n
  };
  console.log(JSON.stringify(out, null, 2));
  return out;
}

const files = process.argv.slice(2);
const results = files.map(run);
if (results.some(r => !r.all_events_consumed || r.late_drops || r.underflow_samples || !r.order_monotonic)) {
  process.exit(1);
}
