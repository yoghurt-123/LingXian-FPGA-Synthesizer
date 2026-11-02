# FPGA UART Bridge (ESP32-C3-Zero) v0.5.3-start-tx — music hall

## Purpose

BLE <-> UART bridge for the accepted basic link plus the expression-control
candidate. The App sends four-byte `E0 EVENT KEY VALUE` performance events;
the ESP adds sequence/CRC and preserves their order. The old v1 basic events
remain valid.

## Board / build

- Board: `ESP32C3 Dev Module`
- `USB CDC On Boot = Enabled`
- ESP32 Arduino core 3.3.12
- FQBN: `esp32:esp32:esp32c3:CDCOnBoot=cdc`
- Sketch: `fpga_uart_bridge.ino`
- Binary: `build/fpga_uart_bridge.ino.bin`
- Merged: `build/fpga_uart_bridge.ino.merged.bin`
- Binary SHA256:
  `0B090F1E4FA8249B385C040540C0AFD07BB5533D20A64F06C4D96C01D3C01818`
- Merged SHA256:
  `9B8A0E63F8ADA1BCC00B337FC59A5B586D25774D1697133FD83A46A5BF195E9F`
- Compile: flash `712,400` bytes (54%), RAM `19,296` bytes (5%).
- Music-hall binary is not a hardware acceptance claim.
- Non-fatal `BLE2902` deprecation warning.

Compile success is not hardware validation.

## Wiring / UART

- ESP GPIO21/TX -> FPGA D19 (ble_uart_rx).
- ESP GPIO20/RX <- FPGA E19 (ble_uart_tx).
- Common ground J13 pin 12.
- 115200 8N1; do not connect ESP 5V/3.3V; do not use FPGA U15/C18/C19.
- USB CDC monitor port is dynamic; do not assume COM10.

## BLE identity

- Name: `FPGA-Instrument`
- Service: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- RX (App write): `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`
- TX (notify): `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`

## Protocol

The fixed v2 event/parameter table, key maps, CRC vectors and capability bits
are in:
`..\..\Docs\BLE_CONTROL_PROTOCOL.md`

Old basic App v0.10.2 events 0x01..0x06 remain compatible. New expression
events 0x20..0x33 are additive.

## Capabilities

`FPGA_STATUS` (or App `E1 00`) sends a UART query. The ESP parses the FPGA
reply and notifies:

```text
CAPS;2;0000FFFF;0
```

- version = 2
- 8 hex digits = actual 32-bit capability mask from FPGA
- final digit = status bit0 (event FIFO/parser overflow)
- The ESP no longer hard-codes `FFFF`.

Capability bits are defined in the protocol document.

## USB computer test entry

The USB CDC monitor accepts readable test commands and converts them to the
**same AppEvent queue/UART frame** as BLE. They are never sent as text to the
FPGA. The USB test entry starts a USB test session (SESSION_START/heartbeat) itself; BLE is not required for UART injection.

```text
TEST NOTE <key> <vel>
TEST OFF <key>
TEST DRUM <key> <vel>
TEST GTR <string> <fret> <vel> [palm=0/1]
TEST GTRM <string> <fret> <vel>
TEST CHS <0..3>
TEST CHT <vel>
TEST CHORD <0..3> <vel>
TEST OCT <0..2>
TEST BEND <0..2>
TEST VIB <0/1>
TEST GLIDE <0/1>
TEST SLIDE <1..15>
TEST OD <0/1>
TEST REV <0/1>
TEST DAMP <0/1>
TEST PEDAL <0/1>
TEST PEDREL
TEST REL
TEST STOP
TEST CAPS
TEST HELP
```

Examples:

```text
TEST GTR 0 3 12
TEST GTRM 0 3 12
TEST CHS 0
TEST CHT 15
TEST CHORD 0 15
TEST OCT 2
```

The serial monitor and a computer test script cannot open the same COM port
simultaneously. Computer injection is not BLE hardware acceptance; record the
two separately.

A Windows script is at:
`..\..\Tools\ble_expression_test.ps1`

## Diagnostics / compatibility

- `PING` -> local `PONG`.
- `FPGA_PING` -> `FPGA_PONG seq=N` only after valid FPGA reply.
- `FPGA_STATUS` -> `CAPS;...`.
- `STATUS` -> local bridge status.
- `BLE_RELEASE` / `ALL_OFF`.
- Diagnostics remain independent of the music-event queue; music events do
  not wait for a PONG.
- `Serial.setTxTimeoutMs(0)` and buffered logging are retained.
- BLE callback only copies/enqueues; main loop parses/sends.
- Release/all-off use queue-reset priority if the bounded App queue is full;
  otherwise queue failure is observable as `ERR:BUSY`.

## Session

Connect sends `SESSION_START`; disconnect sends `BLE_RELEASE_ALL`; heartbeat
every 500 ms; FPGA timeout 2 s releases BLE-held state. Old queued events are
dropped on reconnect.

## Upload

1. Open `fpga_uart_bridge.ino`.
2. Select `ESP32C3 Dev Module`, `USB CDC On Boot = Enabled`, actual port.
3. Upload.
4. Open USB CDC monitor at 115200.

No hardware upload was performed here.


## Music hall v1 additions

- `E2` binary frames: CAPS, BEGIN, DATA, COMMIT, PREPARE, PLAY, STOP, STATUS; STATUS after each DATA.
- SPIFFS file `/music_perf.bin`; maximum 65536 bytes; checks length, SHA256, header and allocation before enabling playback. Legacy NVS `music/perf` is migrated once and removed, freeing NVS pages.
- UART `0x30 SONG_BEGIN`, `0x31 SONG_EVENT`, `0x32 SONG_PLAY`, `0x33 SONG_STOP`; existing `0x10` immediate events remain.
- Preloads about 1 s, then streams with about 1.5 s lookahead; no per-note PONG.
- Hardware progress is not implemented; the ESP source has a dormant `0xB1` forwarder but the FPGA candidate never emits it. Do not advertise a stage position as hardware-verified.
- Pause/seek are not implemented.
- Song stop uses the existing BLE release path; physical TTP/USB keys are protected. Song and BLE free-play are mutually exclusive.
- Build source was also verified with the direct `arduino-builder` command; the script's custom `arduino_hw` path must contain the ESP32 platform (the build environment is external to the repo).
- Exact protocol: `docs/music_hall/MUSIC_HALL_PROTOCOL_V1.md`.
- Full PnR timing-closed candidate: no progress; see handoff.
## 2026-10-27 protocol fixes (v0.5 rebuild)

- BEGIN is exactly 40 bytes: session32, total32, performance_sha256[32]. No short BEGIN or length fallback.
- SHA-256 is over `performance.bin` only. BEGIN stores the expected digest; COMMIT must match it and the digest computed over received bytes.
- E2 reply CRC covers TYPE, SEQ, LEN, PAYLOAD and excludes E2. CAPS_RSP seq 0 is `0x4C`; STATUS and ERROR use the same rule. The previous ERROR CRC length bug is fixed.
- PLAY status is ESP transport state 2 (PLAY accepted, streaming toward FPGA), not an FPGA execution acknowledgement. The status echoes the PLAY request sequence.
- Shared vectors: `docs/music_hall/protocol_vectors_v1.json`; verifier: `node tools/music_hall/verify_protocol_vectors.js`.
## Playback transmit state machine — v0.5.3-start-tx

- PLAY enters a non-blocking sequence: `BEGIN → preload events → PLAY`.
- UART-busy frames are retried from `loop`; the start path has a 3 s bound, STOP has a 2 s bound. The App 4 s timeout was not extended.
- `sendSongEvent()` returns whether the UART frame was accepted. `musicNextEvent` advances only on success, preserving count/order.
- BEGIN/PLAY/STOP failures never call `sendMusicError(0, ...)`; the actual request seq is echoed.
- STOP is queued; the serial STOP frame is retried until accepted or timed out. The STOP success notification means ESP submitted the frame, not that FPGA executed it.
- PLAY state 2 still means ESP accepted PLAY and is streaming, not FPGA execution confirmation.
- Expected serial logs:
  - `MUSIC TX ... phase=START result=queued`
  - `phase=BEGIN result=sent`
  - `phase=PRELOAD result=done`
  - `phase=PLAY result=sent`
  - `phase=STOP result=queued` then `result=sent`
  - `uart_free=...`, `elapsed_ms=...`, `next_event=N/1404`.

## Flash procedure

- Use the ESP32-C3 board and the matching candidate FPGA; do not flash the FPGA for this ESP-only change.
- Arduino IDE: board `ESP32C3 Dev Module`, USB CDC On Boot enabled, open `fpga_uart_bridge.ino`, verify upload.
- Or use the merged image:
  ```powershell
  esptool.py --chip esp32c3 --port COMx --baud 921600 write_flash 0x0 esp32\fpga_uart_bridge\build\fpga_uart_bridge.ino.merged.bin
  ```
- Open serial at 115200 (USB CDC), confirm the version log and `MUSIC TX` sequence.
- Board test: prepare/PLAY; STOP; PLAY again; STOP; then test while UART is busy. Confirm `next_event` reaches 1404 exactly and STOP only succeeds after `STOP sent`.