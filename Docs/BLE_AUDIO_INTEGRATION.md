# BLE Audio Integration (candidate_ble_uart)

Status: implementation candidate, not yet promoted to the accepted default.

## Baseline

- Accepted default source and bitstream are in `text4/impl/pnr/audio_tone.fs`.
- Default SHA256:
  `4B195D55590184C9804CFD10AB576C52D689E17E2FC45CB1CAC0DF3F29302088`
- The default bitstream was not modified by this candidate work.
- Pre-change backup:
  `backups/main_pre_ble_uart_20261024_2245/`

## Candidate location

`E:\EmbeddedCompetition\GowinProjects\text4\candidate_ble_uart`

The candidate is a complete copy of the accepted source plus:

- `src/ble/uart_rx.v`, `src/ble/ble_uart_tx.v`: 115200 8N1 PHY.
- `src/ble/ble_ctrl_proto.v`: UART frame/CRC parser, events, query, replies.
- `src/ble/ble_event_fifo.v`: 16?24-bit asynchronous event FIFO.
- `src/ble/ble_audio_ctrl.v`: audio-clock event decoder, BLE source/release
  ownership, heartbeat timeout.
- `src/top.v`: BLE UART pins, FIFO, source merge, mixer input pipeline.
- `src/tone/piano_modal_shared_core.v` and
  `src/tone/piano_modal_group4_shared.v`: BLE source and per-voice release
  extension. Audio synthesis parameters and algorithm are unchanged.
- `src/constraints/audio.cst`: D19/E19 only; C18/C19 touch and U15 waveform
  UART remain untouched.

## Clock domains

- UART/parser: existing 50 MHz `sys_clk` (V22).
- Audio: existing 52.5 MHz `clk`.
- Control crosses through the asynchronous event FIFO, not a one-cycle pulse.
- FIFO depth 16, width 24 bits (`EVENT, KEY, VALUE`); parser overflow is
  reported by the capability/status query.

## Source / release behavior

- BLE piano note-on triggers the existing piano voice with BLE ownership.
- BLE note-off releases only BLE-owned notes. If touch (`touch_keys`) or USB
  currently holds the same note, the FPGA does not release it.
- BLE release-all releases only BLE-held notes.
- Global all-off uses the existing panic/kill semantics.
- BLE disconnect/session reset clears BLE state; ESP also sends release-all.
- Heartbeat every 500 ms; FPGA timeout 2 s releases BLE state on ESP/UART
  loss. Long notes are not cut while heartbeats continue.
- Drums are one-shot. Guitar uses the existing string trigger/decay chain; BLE
  guitar value is validated but guitar does not add a new source-owned release
  in this first integration.

## UART pins

- ESP GPIO21/TX -> FPGA D19 (`ble_uart_rx`).
- ESP GPIO20/RX <- FPGA E19 (`ble_uart_tx`).
- Common ground J13 pin 12.
- 115200 8N1. Do not connect ESP 5V/3.3V.

## Protocol

See `docs/BLE_CONTROL_PROTOCOL.md`. App events use `E0 EVENT KEY VALUE` over
BLE; ESP wraps them in UART type `0x10`; diagnostic PING remains `0x01/0x81`.

## Mixer timing

The piano velocity scaling and all mixer operands are registered before the
signed 22-bit sum. This adds one common mixer clock of latency but aligns all
piano/guitar/drum paths. The accepted signed mix gains/widths are unchanged.
The candidate full PnR completed: CLS 27402/29952 (+287 vs accepted), BSRAM
93, DSP 81, setup +0.046 ns, TNS 0, audio Fmax 52.628 MHz. Candidate FS:
`candidate_ble_uart/impl/pnr/audio_tone_ble_uart.fs`, SHA256
`3534217A8C1B0EF81E2064C0FE327F063F016A36B1E2E937B0C0FE8BE5AF9714`.

## Verification performed

- UART/FIFO/adapter event unit: bad CRC silent; BLE note-on/off held state.
- Adapter + shared piano group: BLE note-on produces PCM, note-off clears.
- Full candidate top: bad CRC silent; BLE piano note-on produces PCM; BLE
  note-off clears held; BLE drum and guitar produce PCM; release-all clears
  held. A strict full-top PCM zero check 1.7k samples after note-off still saw
  a small residual (418); the isolated adapter+group reaches zero, so the
  longer release-tail capture remains pending.
- Existing top routing/control regression with BLE ports:
  `S2_ROUTING_PASS (six top included)`.

## Not verified / pending

- Full nine-drum + piano + guitar long PCM capture and listening.
- BLE ESP hardware end-to-end; actual D19/E19 wiring and power-cycle.
- Guitar BLE velocity ownership; first integration retains existing guitar
  slot velocity.
- Candidate full PnR/timing result is complete; audio Fmax margin is only
  0.128 MHz and the full-top release tail still needs a longer capture.
- No default replacement and no hardware programming in this step.

