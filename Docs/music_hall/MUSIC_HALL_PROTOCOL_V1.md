# Music Hall Protocol v1

Status: **frozen for the 2026-10-26 candidate**. This is the single shared definition for App, ESP and FPGA.

- FPGA protocol version: **3**
- Music-hall protocol: **v1**
- `.fpgasong` format: **1.0**
- Audio sample clock: `52500000 / 1088 = 48253.676470588 Hz`
- Existing free-play `E0 EVENT KEY VALUE` and UART immediate `TYPE=0x10` remain unchanged.
- The App must not infer fields or compatibility from this document's prose; use the byte layouts and `protocol_vectors_v1.json`.

## 1. Layers

```text
App: package/status/stage
  -> BLE E2 control/transfer frames
ESP: validate, cache in SPIFFS, stream compact events
  -> UART A5 5A frames with absolute sample time
FPGA: queue, audio-sample scheduler, existing piano/guitar/drum engines
```

The ESP does not interpret musical pitch. The FPGA does not parse ZIP/JSON/MIDI.
BLE ATT write success, ESP receipt, ESP Flash commit and FPGA execution are four different facts.

## 2. Common framing and CRC

UART frame:

```text
A5 5A TYPE SEQ LEN PAYLOAD[0..LEN-1] CRC8
```

BLE music frame:

```text
E2 TYPE SEQ LEN PAYLOAD[0..LEN-1] CRC8
```

- Multi-byte integers are **little-endian**.
- `LEN` is the payload length, not including header/CRC.
- CRC8: polynomial `0x07`, init `0x00`, no reflection, over `TYPE SEQ LEN PAYLOAD`. The E2 byte and all header bytes are excluded. The same rule applies to every ESP reply (CAPS_RSP, STATUS, ERROR). For seq=0, the frozen CAPS_RSP example has CRC `0x4C`.
- UART `LEN <= 16`; BLE `LEN <= 180`.
- All numbers below are unsigned.
- Performance times are **absolute audio samples from the play origin**, not milliseconds and not BLE arrival time.

## 3. Performance event layout

`performance.bin` header (32 bytes):

| Offset | Size | Meaning |
|---:|---:|---|
| 0 | 4 | ASCII `FPGS` |
| 4 | 1 | 1 |
| 5 | 1 | 32 |
| 6 | 1 | 8 |
| 7 | 1 | flags 0 |
| 8 | 4 | 52500000 |
| 12 | 2 | 1088 |
| 14 | 2 | reserved 0 |
| 16 | 4 | event count |
| 20 | 4 | duration in samples |
| 24 | 4 | CRC32 of event area |
| 28 | 4 | song id FNV32 |

Each event is 8 bytes:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 4 | absolute time (samples) |
| 4 | 1 | type |
| 5 | 1 | a |
| 6 | 1 | b |
| 7 | 1 | flags |

Types:

| Type | Event | a | b | flags |
|---:|---|---|---|---|
| 1 | piano note on | key 0..15 | velocity 1..15 | 0 |
| 2 | piano note off | key 0..15 | 0 | 0 |
| 3 | drum one-shot | drum 0..8 | velocity 1..15 | 0 |
| 4 | guitar pluck | string 0..5 | velocity 1..15 | fret bits0..3, palm bit4 |
| 5 | guitar chord | preset | velocity | palm |
| 6 | parameter | id | value | 0 |
| 7 | release song notes | 0 | 0 | 0 |
| 8 | all-off | 0 | 0 | 0 |

Parameter ids: 0 piano octave, 1 guitar fret, 2 guitar palm, 3 overdrive, 4 reverb, 5 damping, 6 pedal delay. Parameters precede dependent triggers when sent at the same time.

The current candidate expands a type-4 record into legacy `0x21` fret, `0x22` palm and `0x20` pluck at the same due sample. It does not wait for a per-note PONG.

## 4. App → ESP (BLE E2)

| TYPE | Direction | Name | Payload |
|---:|---|---|---|
| 0x01 | App→ESP | CAPS_REQ | empty |
| 0x81 | ESP→App | CAPS_RSP | version8, caps32, max_bytes32 |
| 0x10 | App→ESP | BEGIN | session32, total_bytes32, performance_sha256[32] — exactly 40 bytes |
| 0x11 | App→ESP | DATA | offset32, bytes... |
| 0x12 | App→ESP | COMMIT | performance_sha256[32] — exactly 32 bytes |
| 0x13 | App→ESP | PREPARE | empty |
| 0x14 | App→ESP | PLAY | flags8 (0) |
| 0x15 | App→ESP | STOP | reason8 (0 stop,1 user,2 replace,3 disconnect) |
| 0x16 | App→ESP | STATUS_REQ | empty |
| 0x96 | ESP→App | STATUS | state8, code8, received32, stored32 |
| 0x97 | ESP→App | ERROR | code8 |

- The App first reads `CAPS_RSP`; unknown required capabilities must be rejected.
- `BEGIN` is **always exactly 40 payload bytes**: session32, total32, SHA-256[32]. There is no short BEGIN and no length-based fallback. ESP must reject any other BEGIN length with an explicit error.
- The SHA-256 in `BEGIN` is over the complete `performance.bin` bytes only (not the ZIP, JSON, score or WAV). `BEGIN` stores this expected digest; `COMMIT` carries the same digest, and ESP must require both to match the digest it computes over the bytes actually received. `COMMIT` is authoritative for received bytes; failure leaves no playable cache.
- `BEGIN` allocates/reuses the transfer buffer and resets received bytes.
- `DATA` chunks are at most 180 payload bytes; recommended 128 bytes. ESP replies `STATUS` for every DATA frame.
- `COMMIT` is accepted only after exact length and SHA256 match. Failure discards the incomplete cache and must not enable playback.
- ESP stores the complete performance blob in SPIFFS (`/music_perf.bin`) and logs the write result. It checks a 65536-byte maximum and the actual allocation. Legacy NVS `music/perf` is migrated once and removed.
- `PREPARE` loads/validates the header; `PLAY` only starts after prepare succeeds.
- The `PLAY` response is **ESP transport state 2**: ESP has accepted PLAY and started streaming toward FPGA. It is **not** an FPGA execution acknowledgement. There is no FPGA-ready/started acknowledgement in this candidate; App animation is explicitly estimated and must not be described as hardware-confirmed.
- One active session. A new `BEGIN` stops the old one and invalidates its play id.
- Music-hall and BLE free-play are mutually exclusive in the current candidate. Song ownership is implemented through the existing BLE event source; physical TTP/USB ownership is not touched by song stop.

ESP state values: `0=idle, 1=transfer, 2=playing, 3=stored/prepared, 4=ended, 5=error`.
ESP error codes: `1=bad frame,2=not ready,3=UART send,4=bad total,5=alloc,6=data range,7=incomplete,8=hash,9=storage,10=header,11=prepare,12=unsupported`.

## 5. ESP → FPGA (UART)

Existing immediate event `0x10` and PING/QUERY are unchanged.

| TYPE | Direction | Name | Payload |
|---:|---|---|---|
| 0x30 | ESP→FPGA | SONG_BEGIN | play_id32, event_count32, duration_samples32, flags32 |
| 0x31 | ESP→FPGA | SONG_EVENT | exactly one 8-byte performance record |
| 0x32 | ESP→FPGA | SONG_PLAY | play_id32, lead_samples32, flags32 |
| 0x33 | ESP→FPGA | SONG_STOP | play_id32, reason8 |

- `SONG_BEGIN` clears the FPGA queue and records the expected count/duration.
- Events are sent in increasing time order. `SONG_PLAY` sets the play origin to the FPGA's current audio sample count plus `lead_samples`.
- A lead of 24127 samples is 500 ms; the App/ESP may not shorten it below 100 ms.
- FPGA queue: 128 records of 64 bits. Full source peak is 7 events per 50 ms, 39 events per second and 4 concurrent voices; the queue has substantial margin.
- ESP preloads about one second before `SONG_PLAY`, then streams with about 1.5 seconds of lookahead.
- Do not send PONG per event. Hardware position/progress is not implemented in this candidate.

FPGA error handling: queue overflow and underrun are sticky and stop the song. A missed event is not replayed. No random jitter, catch-up burst, or 48 kHz approximation is permitted.

## 6. Sample timing and ordering

```text
sample(tick) = round(tick * 60 * 52500000 / (bpm * ppqn * 1088))
```

Each event is converted from its absolute source tick, not by accumulating rounded deltas. For the full song: 2/4, 120 BPM, PPQN 480, 62,388 ticks, 64.9875 s, 3,135,886 samples.

At one FPGA sample, events are ordered:

1. parameters (octave/fret/palm/effects),
2. note-offs,
3. triggers/drums.

The scheduler expands guitar type-4 into fret, palm, then pluck in that order. It holds each legacy event if the 16-slot BLE event FIFO is full, and it does not advance the music queue until the event is accepted.

## 7. Gain and stop

- The accepted 4-second reference used a common master gain `0.302653962158`; the candidate uses Q15 `9919` for music-hall playback.
- The gain is applied only while `song_active`; stopping restores the free-play volume setting.
- No per-track normalization, compressor, EQ or software reverb is added.
- Hardware progress/position (`0xB1`) is not implemented. The App may show transfer/play state from ESP STATUS but must not display a hardware position as if it were verified.
- `SONG_STOP` / end / session replacement:
  1. discard future events and the queue,
  2. clear song-owned (BLE-source) note state with legacy `BLE_RELEASE_ALL`,
  3. restore free-play volume,
  4. never generate a global panic for a normal stop.
- Physical TTP/USB keys are protected by the existing source-owner rules. BLE free-play is not preserved if it shares the BLE source; the App must leave free-play before starting a song.
- Pause, seek and resume are **not implemented**. Do not expose them as working.

## 8. Capability mask

FPGA protocol 3 reports `0x0003FFFF`:

- bits 0..15: existing free-play/expression capabilities,
- bit16: timed event queue,
- bit17: bulk performance transfer,
- bit18: progress report — **not set** (not implemented),
- bit19: song-owned release — **not set** (current stop uses the existing BLE release path),
- bit20: seek — not set,
- bit21: real echo/delay — not set.

## 9. Full song facts

- Source: `Rock Theme 3`, Umplix, CC0 1.0, OpenGameArt.
- Full source MIDI: 65 bars, 2/4, 120 BPM, 238 guitar notes, 436 drums, end tick 62,388.
- Tracks 3 and 4 are byte-for-byte duplicates of track 1 from tick 31200; they are not additional voices and are not triggered.
- No source piano, vocal or independent bass. Piano is an arrangement of the guitar riff +12 semitones. No bass was invented.
- Drums: 35→0, 38→1, 42→2, 43→6 (high floor tom to high tom), 49→5 (crash). The existing six engine maps external 5 to internal bit0 (Crash) and external 6 to internal bit4 (high tom). Internal bit5 is low tom and is not used by this song.
- Crash velocity is stored but the current six engine does not apply its declared velocity multiplier. This is a known limitation, not a claim of working crash dynamics.
- Guitar uses the accepted clean path, low-string mapping and natural decay; it has no per-note Note Off.
- Piano note duration is shortened/clamped to leave at least 48 ticks before the next same-key note; no same-key overlap errors remain.

## 10. Test vectors

Machine-readable: `docs/music_hall/protocol_vectors_v1.json`.

CRC vectors include UART `SONG_BEGIN`, `SONG_PLAY`, first `SONG_EVENT`, `SONG_STOP`, BLE CAPS_REQ/CAPS_RSP, 40-byte BEGIN, DATA, COMMIT, STATUS, ERROR and STOP. Builders must test CRC, endianness and the first event byte-for-byte before testing audio. Run `node tools/music_hall/verify_protocol_vectors.js`.

## 11. Persistence and failure policy

- ESP stores the entire compact performance blob in SPIFFS, not the ZIP or WAV.
- ESP must validate total length and SHA256 before enabling PLAY. It must never silently delete notes to fit.
- BLE disconnect: stop song and invalidate future events. Do not continue autonomously.
- UART timeout/underrun: FPGA stops; ESP reports an error; no catch-up burst.
- Old session/package identifiers are rejected after reconnect.
- Logs remain non-blocking; `Serial.setTxTimeoutMs(0)` remains enabled.
