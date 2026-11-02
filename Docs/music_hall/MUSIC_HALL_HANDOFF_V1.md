# Music Hall Handoff v1 — 2026-10-26

This is the hardware/ESP handoff. The App chat must use the same files, not a locally invented protocol.

## Versions

| Component | Version | Artifact |
|---|---|---|
| Default FPGA | unchanged | `impl/pnr/audio_tone.fs`, SHA256 `A92125809FEF3AE6A910CD51A92D3AFC4856A3422D55B977168F6E51199B7C70` |
| FPGA candidate | music-hall-v1 | `candidate_music_hall/impl/pnr/audio_tone_music_hall.fs`, SHA256 `7355A942576F93079BAD782466F79A6D37C67A5F312E48B8155069B1D88A36C0` |
| ESP | v0.5.3-start-tx | `esp32/fpga_uart_bridge/build/fpga_uart_bridge.ino.bin` |
| App | v0.15.8 source repack | `iPadInstrumentApp/deliveries/FPGA_Instrument_v0_15_8.zip`, 239,375 bytes, SHA256 `494F14A6FDE107EF66C976DFA1AA71A6CA06909AF5AA10949D1AB4ADCDA6CA53` |
| Package format | 1.0 | `music_packs/rock_theme_3_full.fpgasong` |
| Protocol | music-hall-v1 | `docs/music_hall/MUSIC_HALL_PROTOCOL_V1.md` |

The default bitstream was not replaced. Candidate bitstream requires user board acceptance before promotion.
## 2026-10-27 cross-end fixes

- **BEGIN** is now frozen at exactly **40 bytes** (`session32,total32,SHA256[32]`). App no longer sends an 8-byte BEGIN or a 40-byte fallback; ESP accepts only 40 and rejects other lengths. No length guessing.
- **SHA-256** is over `performance.bin` only. BEGIN binds the expected digest; COMMIT carries the same digest and ESP independently computes it over received bytes. COMMIT is authoritative; a mismatch does not create a playable cache.
- **E2 replies** use CRC8 over `TYPE SEQ LEN PAYLOAD`, excluding E2. CAPS_RSP for seq 0 is `0x4C`; STATUS and ERROR use the same rule. The old ERROR CRC length bug was fixed and ESP recompiled.
- **PLAY reply** is ESP transport state 2: PLAY accepted and ESP streaming toward FPGA. It is **not** an FPGA execution acknowledgement. No FPGA ready/execute ack exists; progress remains unavailable (bit18=0).
- PLAY status echoes the PLAY request sequence; the App special case for seq 0 was removed.
- Shared vectors are in `docs/music_hall/protocol_vectors_v1.json`; `node tools/music_hall/verify_protocol_vectors.js` must print `PASS`.
- No FPGA bitstream change was made for these fixes. Default remains `A921...`; candidate remains `7355...`.

## Song

- `rock_theme_3_full.fpgasong`, 17,681 bytes, SHA256 `893F01477B0BBDF117E24FF9B55ABF25518B48C4697D8EAEE48AF59276E2871A`.
- 1404 events, 64.9875 s, 3,135,886 samples.
- Source: Umplix, Rock Theme 3, CC0 1.0, OpenGameArt.
- Source tracks 3/4: exact duplicates of track1 from tick 31200; omitted.
- Piano is an arrangement of the source riff +12; no independent bass exists.
- Master gain Q15 9919 (`0.302653962158`), matching the accepted 4-second reference; no per-track normalization.

## Candidate RTL behavior

- Full PnR: CLS 27,807/29,952 (93%), Logic 49,420/59,904 (83%), Register 24,655/60,780 (41%), BSRAM 99/118 (84%), DSP 82/118 (70%). Setup slack **+1.484 ns**, hold TNS 0. Fmax: audio 56.936 MHz, sys 71.910 MHz, USB 108.553 MHz.
- Candidate `.fs`: 20,345,231 bytes. Default remains unchanged.

- New `song_scheduler.v`: 128 × 64-bit event queue, audio-sample toggle timebase, legacy BLE event expansion, stop/end release. Hardware progress and explicit queue-error counters are not exposed in this timing-closed candidate.
- New UART types 0x30–0x33; existing 0x10 free-play path preserved.
- Music-hall gain is a volume mux active only during a song; free-play volume restores after stop.
- Crash mapping is correct in top: external 5 -> six internal bit0; external 6 -> bit4; internal bit5 is low tom. Do not repeat the old `HIT=5` testbench error.
- Crash velocity multiplier is still not implemented in the existing six engine.
- Guitar has no per-note Note Off; natural decay.
- Pause/seek and hardware progress are not implemented.
- Song and BLE free-play are mutually exclusive; physical TTP/USB ownership is protected. Bit19 is not claimed.
- Hardware progress/position is **not implemented** in this candidate. Bit18 is 0. The App may show transfer/play state but not a verified FPGA position. The ESP source retains a dormant 0xB1 forwarder; the FPGA never emits it.

## ESP v0.5.3-start-tx behavior

- PLAY start is a non-blocking state machine: BEGIN → preload events → PLAY. Each frame is retried from the main loop when UART has insufficient write space.
- Start timeout is 3 s; stop timeout is 2 s. The App 4 s timeout is unchanged. No added delays or buffer enlargement.
- `sendSongEvent()` returns success. `musicNextEvent` advances only after a successful UART write; failed events are retried in order.
- STOP is queued and retried. ESP replies STOP success only after the STOP frame has been accepted by the UART driver; this is an ESP submission, not an FPGA execution confirmation.
- START/STOP/phase/UART-free/result/elapsed/next-event logs are emitted. Expected successful sequence: `START queued`, `BEGIN sent`, `PRELOAD done`, `PLAY sent`; STOP: `STOP queued`, `STOP sent`.

- Keeps E0 immediate events, PING/QUERY and USB test mode.
- Adds E2 binary transfer: caps/begin/data/commit/prepare/play/stop/status. No FPGA progress frame is emitted.
- Stores performance in SPIFFS `/music_perf.bin`; maximum 65536 bytes; checks length, SHA256 and allocation. Legacy NVS `music/perf` is migrated once and then removed, freeing NVS pages.
- Preloads ~1 s then streams ~1.5 s ahead; never waits for per-note PONG.
- Stops on new session, BLE disconnect and STOP.
- Binary: 712,400 bytes; sketch space 712,249/1,310,720 (54%); static RAM 19,296/327,680 (5%).
- Binary SHA256: `0B090F1E4FA8249B385C040540C0AFD07BB5533D20A64F06C4D96C01D3C01818`.
- Merged SHA256: `9B8A0E63F8ADA1BCC00B337FC59A5B586D25774D1697133FD83A46A5BF195E9F`.

## Files the App needs

- `music_packs/catalog.json`
- `music_packs/rock_theme_3_full.fpgasong`
- `docs/music_hall/MUSIC_HALL_PROTOCOL_V1.md`
- `docs/music_hall/protocol_vectors_v1.json`
- `docs/music_hall/STATIC_CATALOG.md`

## Required App behavior

1. Download or import the whole `.fpgasong`; verify manifest SHA256 and required capabilities.
2. Extract `performance.bin`; send it through E2 BEGIN/DATA/COMMIT; do not send WAV/PCM or the ZIP to ESP.
3. Only call PREPARE/PLAY after ESP reports stored/prepared.
4. Do not display a hardware playback position: it is not implemented. Use ESP STATUS/state only; never use BLE notification arrival time as the audio clock.
5. Show error/underrun explicitly; do not silently skip notes.
6. Do not expose pause/seek as working. Stop and restart are supported.
7. Free-play must be left before song playback; physical keyboard remains independent.

## Not completed / not claimed

- No board acceptance, no listening test on hardware.
- No full-song PCM equivalence claim. The accepted 4 s file is an offline RTL/short reconstruction reference.
- No independent bass, no vocal, no real echo/delay, no crash-velocity fix.
- No pause/seek.
- No public URL published. LAN/static channel instructions only; the catalog contains no fake URL.
- App implementation is owned by the App chat.

## Full song packs added 2026-10-27

- **Fight for Better Future [Rock/Metal]** — `music_packs/fight_for_better_future.fpgasong`, 26,015 bytes, SHA256 `37e6c6f19e759ade667edb48ad011fe3e387ee2442f389d1c6caa77ec6053068`; 68.129 s; 2,669 events; 155.000 BPM, 4/4; source MIDI `939a374f...82E43`; CC0, nene.
- **Rock Music** — `music_packs/rock_music_0.fpgasong`, 7,586 bytes, SHA256 `8e97d9d3071661e241ef277f083fdf2974f2ffa5f9f30255f039f39c108b53bb`; 32.000 s; 207 events; 120 BPM, 4/4; source MIDI `82c2fda1...9BAEB`; CC0, Umplix.
- **Rock Theme 3** remains `music_packs/rock_theme_3_full.fpgasong`, 17,681 bytes, SHA256 `893f01477b0bbdf117e24ff9b55abf25518b48c4697d8eaee48af59276e2871a`.

Fight arrangement: rhythm guitar remains on the FPGA guitar; Lead/Bass/Synth/Strings are adapted onto piano; Left Guitar is an exact duplicate of Right Guitar and is not double-triggered. Rock Music uses only its guitar and drums; its track 3 is an exact duplicate of track 1 and the source has no independent piano/bass/synth, so piano is intentionally unused rather than duplicated. Detailed track/CC/program/tempo/drum/collision reports are in each pack's `analysis_report.json` and `analysis.json`.