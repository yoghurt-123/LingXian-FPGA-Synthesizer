# BLE Control Protocol v2 (App / ESP / FPGA)

Status: expression-control candidate for `candidate_ble_expression`.
Hardware acceptance of the expression layer is pending.

The v1 basic events remain valid; v2 adds guitar fret/chord/expression, piano
octave/damping and real capability reporting. App v0.10.2 basic playback is
kept as a compatibility path.

## 1. Layers and identity

- BLE name: `FPGA-Instrument`
- Service: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- RX (App write): `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`
- TX (notify): `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`
- ESP <-> FPGA UART: `115200 8N1`, ESP GPIO21/TX -> D19, GPIO20/RX <- E19,
  common ground.
- App performance packet: exactly four bytes `E0 EVENT KEY VALUE`.
- ASCII diagnostics: `PING`, `FPGA_PING`, `FPGA_STATUS`, `STATUS`,
  `BLE_RELEASE`, `ALL_OFF`.
- `E1 00` requests the FPGA capability/status query.

The App, ESP and FPGA use the same event/key numbers below; the ESP only adds
UART sequence and CRC.

## 2. UART frame

```text
A5 5A TYPE SEQ LEN PAYLOAD[0..LEN-1] CRC8
```

- `TYPE 0x01`: diagnostic ping; reply `0x81`.
- `TYPE 0x10`: performance event; `LEN=3`, payload `EVENT KEY VALUE`.
- `TYPE 0x11`: capability/status query; `LEN=1`, payload `0x01`; reply `0x91`.
- `TYPE 0x91`: query reply; `LEN=6`.
- `CRC8`: poly `0x07`, init `0x00`, over `TYPE/SEQ/LEN/PAYLOAD`; header
  excluded.
- `SEQ`: ESP-assigned 0..255; replies echo the query sequence.
- Normal performance events do not wait for a reply.

## 3. Event table

| EVENT | Name | KEY | VALUE |
| ---: | --- | --- | --- |
| 0x01 | Piano note on | 0..15 | 1..15 velocity |
| 0x02 | Piano note off | 0..15 | 0 |
| 0x03 | Drum one-shot | 0..8 | 1..15 |
| 0x04 | Guitar pluck (v1 compatibility) | 0..5 | 1..15 |
| 0x05 | BLE release all | 0 | 0 |
| 0x06 | Global all-stop | 0 | 0 |
| 0x07 | Session start | 0 | 0 |
| 0x08 | Heartbeat | 0 | 0 |
| 0x20 | Guitar pluck | 0..5 string | 1..15 velocity |
| 0x21 | Guitar fret selection | 0..12 | 0 |
| 0x22 | Guitar palm mute | 0/1 | 0 |
| 0x23 | Chord select only | 0..3 preset | 0 |
| 0x24 | Chord trigger selected | 0 | 1..15 velocity |
| 0x25 | Chord release/cancel pending | 0 | 0 |
| 0x26 | Pitch bend state | 0=center,1=left,2=right | 0 |
| 0x27 | Vibrato | 0/1 | 0 |
| 0x28 | Glide/legato | 0/1 | 0 |
| 0x29 | Slide time | 1..15 | 0 |
| 0x2A | Overdrive target | 0/1 | 0 |
| 0x2B | Reverb target | 0/1 | 0 |
| 0x30 | Piano octave | 0/1/2 | 0 |
| 0x31 | BLE damping mode | 0/1 | 0 |
| 0x32 | BLE pedal delay | 0/1 | 0 |
| 0x33 | Release pending BLE pedal notes | 0 | 0 |

Out-of-range events are rejected by ESP and FPGA; a bad event cannot silently
sound a wrong note.

## 4. Piano

- Key map is the existing NOTE_SEL order:

| KEY | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Note | C4 | D4 | E4 | F4 | G4 | A4 | B4 | C5 | D5 | C#4 | D#4 | F#4 | G#4 | A#4 | C#5 | D#5 |

- `PIANO_OCT`: 0=low, 1=original, 2=high (the same three settings as the USB
  Home/End control). The value is sampled at the piano trigger and latched in
  the existing shared voice.
- BLE note-off releases only BLE-owned notes. If TTP or USB currently holds
  the same note, the release is suppressed.
- BLE damping:
  - `DAMP=1` (default): BLE note-off requests the existing external release.
  - `DAMP=0`: BLE note-off leaves the voice to its natural decay.
  - `PEDAL_DELAY=1`: with damping on, a BLE note-off is held pending;
    `PEDAL_DELAY=0` or `PEDAL_RELEASE` releases pending BLE notes, subject to
    the physical-hold gate.
  - `RELEASE_ALL` releases all BLE-held/pending notes; `ALL_OFF` uses the
    existing global panic/kill path.
- USB F7/right-Ctrl behavior is not replaced; it continues to control USB
  notes. BLE damping is a separate BLE-source extension.

## 5. Guitar

### String map

KEY 0..5 = E2, A2, D3, G3, B3, E4 (the existing six request keys). The request
goes through `guitar_ctrl`'s request latch, note/velocity write, dynamic pool
allocation, replacement fade, and trigger logic. It does **not** write a
physical slot directly.

### Fret / velocity / palm

- `GTR_FRET` selects current BLE fret 0..12. It becomes the fret of the next
  BLE `GTR_PLUCK` and the target for a later glide.
- `GTR_PLUCK` carries its own velocity. The current fret and palm state are
  latched with the request in `guitar_ctrl`.
- Fret ratio follows the existing 0..12 semitone table; E2=A2... base strings
  are unchanged.
- Velocity 1..15 is written into the same per-slot velocity metadata as USB.
- `GTR_PALM` sets the palm-mute state applied to the next BLE pluck/chord. It
  does not globally kill physical strings.

### Chords

`CHORD_SELECT` selects preset without sounding:

| KEY | Preset | Original definition |
| ---: | --- | --- |
| 0 | U = C | A2+3, D3+2, G3 |
| 1 | I = G | E2+3, A2+2, D3 |
| 2 | O = Dm | D3, D3+3, G3+2 |
| 3 | P = Am | A2, D3+2, B3+1 |

`CHORD_TRIGGER` (KEY=0, VALUE=velocity) triggers the selected preset through
the existing chord engine, using its original three-slot preparation, fade,
metadata write and direction-L commit. `CHORD_RELEASE` cancels a **pending**
BLE chord trigger and clears BLE chord selection; a chord already committed is
the existing short one-shot pattern and is not converted into a new sustained
source.

### Expression

- `BEND`: 0=center, 1=left (-2 semitones), 2=right (+2 semitones). These are
  the original arrow-key endpoints, not a continuous pitch field.
- `VIB`: 0/1; existing 5 Hz, ±50 cent LFO/depth ramp.
- `GLIDE`: 0/1; existing F11 legato slide switch semantics.
- `SLIDE_TIME`: 1..15, 20 ms steps; 1=20 ms, 4=80 ms default, 15=300 ms.
- BLE plucks bind to the most recent manual lead through the existing
  `trig_usb`/`trig_fret` path; the module still applies expression only to the
  most recent accepted manual trigger.
- USB expression keys have priority while active. BLE bend/glide/fret/time
  applies when no USB expression key is active. This is a deterministic
  arbitration, not independent per-source expression engines.
- Overdrive and reverb are shared global guitar effects. Their targets are
  explicit (`0/1`), never “toggle again”. Overdrive uses the existing mute,
  settle and change-application sequence; a target change does not pluck a
  string. Reverb target updates the existing shared reverb selection.

## 6. Drums

KEY 0..8: kick, snare, closed hat, open hat, ride, crash, tom high, tom low,
tom mid. One-shot. BLE velocity is latched until the existing drum trigger is
accepted; it is not selected only for the one-cycle event pulse.

## 7. Capabilities / status

Query: `A5 5A 11 SEQ 01 01 CRC8`; reply `0x91`, LEN 6:

```text
VERSION CAPS0 CAPS1 CAPS2 CAPS3 STATUS
```

- VERSION = 2.
- CAPS = 0x0000FFFF for this candidate:
  bit0 piano, bit1 drums, bit2 guitar pluck, bit3 chords, bit4 fret, bit5 palm,
  bit6 bend/vibrato, bit7 glide/slide, bit8 overdrive, bit9 reverb, bit10 piano
  octave, bit11 damping/pedal, bit12 release-all, bit13 all-off, bit14 session/
  heartbeat, bit15 query.
- STATUS bit0 = FPGA event FIFO/parser overflow sticky flag; other bits 0.
- ESP returns the FPGA's actual values:
  `CAPS;<version>;<8 hex caps>;<status>` (e.g. `CAPS;2;0000FFFF;0`).
  It no longer hard-codes FFFF.

## 8. Session / release / arbitration

- Connect: ESP clears old queues and sends `SESSION_START`; FPGA clears BLE
  held notes/pending releases/chord trigger state, resets BLE octave/damping/
  fret/palm to basic defaults, keeps global FX/reverb targets.
- Disconnect: ESP sends `BLE_RELEASE_ALL`; FPGA timeout (2 s without heartbeat)
  also releases BLE notes. Heartbeats continue during a long note; normal
  long notes are not cut by keyboard inactivity.
- `BLE_RELEASE_ALL`: BLE notes, pending pedal notes, BLE chord trigger, bend/
  vibrato/glide are cleared. Physical USB/TTP and shared FX targets are not
  forcibly changed.
- `ALL_OFF`: existing global panic/kill semantics; separate from BLE release.
- Physical keyboard/touch remain independent. Shared guitar FX/reverb and
  expression targets are explicitly global; they are not claimed per-source
  independent DSP chains.

## 9. Error replies

- `ERR:BUSY`: bounded queue full or diagnostic request already pending.
- `ERR:FPGA_TIMEOUT`: no matching query/ping within 600 ms.
- `ERR:UART_TX`: ESP UART flow-control/write failure.
- `ERR:TOO_LONG`: BLE write too long.
- `ERR:BAD_EVENT`: event/key/value out of range.
- `ERR:UNKNOWN_CMD`: unknown ASCII diagnostic.

Performance events do not consume the diagnostic PONG lock.

## 10. Test vectors

Byte-identical UART examples (header included):

| Action | Frame |
| --- | --- |
| Fret 3, seq 1 | `A5 5A 10 01 03 21 03 00 D1` |
| String 0, fret 3, velocity 12, seq 2* | `A5 5A 10 02 03 20 00 0C 07` |
| Chord select U, seq 3 | `A5 5A 10 03 03 23 00 00 FC` |
| Chord trigger velocity 15, seq 4 | `A5 5A 10 04 03 24 00 0F EE` |
| Bend left, seq 5 | `A5 5A 10 05 03 26 01 00 62` |
| Vibrato on, seq 6 | `A5 5A 10 06 03 27 01 00 AF` |
| Glide on, seq 7 | `A5 5A 10 07 03 28 01 00 8A` |
| Slide time 10, seq 8 | `A5 5A 10 08 03 29 0A 00 46` |
| Overdrive 1, seq 9 | `A5 5A 10 09 03 2A 01 00 0E` |
| Reverb 1, seq 10 | `A5 5A 10 0A 03 2B 01 00 C3` |
| Piano octave 2, seq 11 | `A5 5A 10 0B 03 30 02 00 D0` |
| Damping 0, seq 12 | `A5 5A 10 0C 03 31 00 00 B8` |
| Pedal delay 1, seq 13 | `A5 5A 10 0D 03 32 01 00 72` |
| Query, seq 14 | `A5 5A 11 0E 01 01 4F` |
| Reply, seq 14 | `A5 5A 91 0E 06 02 FF FF 00 00 00 4C` |

`*` The pluck uses the current BLE fret (set to 3 by the preceding event in a
real sequence). The event itself carries only string/velocity; this is the
documented order rule.

Basic v1 vectors remain in the hardware archive at
`text4/candidate_ble_uart/docs/` and are still accepted.

## 11. ESP USB test entry

The ESP USB CDC monitor accepts readable commands. These are converted to the
same internal AppEvent queue and UART framing as BLE, never sent as text to
the FPGA. The monitor and a computer script cannot share the COM port.

```text
TEST NOTE 0 15          piano C4 on
TEST OFF 0              piano C4 off
TEST DRUM 0 15          kick
TEST GTR 0 3 12         string E2, fret 3, velocity 12
TEST GTRM 0 3 12        same with palm mute
TEST CHS 0              select U/C without sounding
TEST CHT 15             trigger selected chord, velocity 15
TEST CHORD 0 15         select + trigger U/C
TEST OCT 2              high octave
TEST BEND 1             left -2 semitones
TEST VIB 1 / 0
TEST GLIDE 1 / 0
TEST SLIDE 10
TEST OD 1 / 0
TEST REV 1 / 0
TEST DAMP 0 / 1
TEST PEDAL 1 / 0
TEST PEDREL
TEST REL
TEST STOP
TEST CAPS
TEST HELP
```

Computer injection is not BLE hardware acceptance; record them separately.

## 12. Compatibility and limits

- Old v1 App basic `E0 01/02/03/04/05/06` events continue to work.
- New event values are additive; old App does not need the new query.
- Event payload is still 3 bytes, so parameters are ordered events. The ESP
  preserves event order; it never merges a parameter across a trigger.
- No bulk score/sample transfer.
- At most two expression states are meaningful: shared USB/BLE effects and the
  most recent manual lead; per-source independent guitar FX/DSP is not claimed.
- Chord release only cancels a pending BLE chord trigger; a committed chord is
  the original short one-shot pattern.
