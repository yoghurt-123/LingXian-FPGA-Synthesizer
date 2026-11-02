# Music Hall Delivery Summary — 2026-10-26/27

## Delivered

| Item | Path | Result |
|---|---|---|
| Full song package | `music_packs/rock_theme_3_full.fpgasong` | 17,681 bytes, SHA256 `893F01477B0BBDF117E24FF9B55ABF25518B48C4697D8EAEE48AF59276E2871A` |
| Catalog | `music_packs/catalog.json` | no public URL claimed; file/relative/LAN channel |
| Static server | `tools/music_hall/serve_catalog.js` | tested on `127.0.0.1:8081`, catalog and pack HTTP 200 |
| Full score | `music_packs/rock_theme_3_full/score/score.json` | 1,404 events, 64.9875 s |
| Adaptation report | `music_packs/rock_theme_3_full/adaptation_report.json` | tracks, density, gain, limits |
| Protocol | `docs/music_hall/MUSIC_HALL_PROTOCOL_V1.md` | frozen v1 / FPGA protocol 3 |
| Vectors | `docs/music_hall/protocol_vectors_v1.json` | 8 machine-readable frames |
| Handoff | `docs/music_hall/MUSIC_HALL_HANDOFF_V1.md` | versions, hashes, App obligations |
| FPGA candidate | `candidate_music_hall/impl/pnr/audio_tone_music_hall.fs` | 20,345,231 bytes, SHA256 `7355A942576F93079BAD782466F79A6D37C67A5F312E48B8155069B1D88A36C0` |
| ESP binary | `esp32/fpga_uart_bridge/build/fpga_uart_bridge.ino.bin` | 712,400 bytes, SHA256 `0B090F1E4FA8249B385C040540C0AFD07BB5533D20A64F06C4D96C01D3C01818` |
| ESP merged | `.../fpga_uart_bridge.ino.merged.bin` | SHA256 `9B8A0E63F8ADA1BCC00B337FC59A5B586D25774D1697133FD83A46A5BF195E9F` |
| App source repack | `iPadInstrumentApp/deliveries/FPGA_Instrument_v0_15_8.zip` | 239,375 bytes, SHA256 `494F14A6FDE107EF66C976DFA1AA71A6CA06909AF5AA10949D1AB4ADCDA6CA53` |
| Default | `impl/pnr/audio_tone.fs` | unchanged, `A92125809FEF3AE6A910CD51A92D3AFC4856A3422D55B977168F6E51199B7C70` |

## Verification performed

- Full MIDI: 2/4, 120 BPM, PPQN 480, 62,388 ticks, 64.9875 s.
- Track 3 and 4 are exact duplicates of track 1 from tick 31200; omitted from playback.
- Source has no piano, vocal or independent bass. Piano is an arrangement +12; no bass invented.
- Full package: 1,404 events, max 7 events/50 ms, max 4 concurrent voices, queue 128.
- `node tools\music_hall\validate_pack.js music_packs\rock_theme_3_full` → **PASS** (structure, hashes, compiler byte identity, header).
- `node tools\music_hall\verify_protocol_vectors.js` → **PASS** (shared App/ESP frames, CAPS CRC 0x4C, 40-byte BEGIN, ERROR CRC).
- `tb_song_scheduler` → **PASS** (begin/play, piano/drum/guitar expansion, stop release; no duplicate events).
- Full FPGA PnR: CLS 27,807/29,952 (93%), Logic 49,420/59,904 (83%), Register 24,655/60,780 (41%), BSRAM 99/118 (84%), DSP 82/118 (70%).
- Setup slack **+1.484 ns**, hold TNS 0. Fmax: audio 56.936 MHz, sys 71.910 MHz, USB 108.553 MHz.
- ESP compile: 712,249 sketch bytes / 712,400 binary, static RAM 19,296 bytes.
- Local static HTTP: catalog and package both returned 200.

## Not delivered / not claimed

- **No board acceptance or listening test.** The four-second reference is an offline RTL/short-segment reconstruction, not proof of whole-board sample identity.
- **No hardware progress/position.** The timing-closed FPGA removes the progress path; bit18 is 0. Do not show a verified FPGA position.
- **No pause/seek.**
- **No crash-velocity fix.** The existing six engine ignores the declared crash velocity multiplier.
- **No independent bass**, no vocal, no real delay/echo.
- **No full song WAV** (deliberately; instruction was no WAV generation).
- **No public download URL.** LAN/static and Files import only.
- The App implementation is the separate Swift Playgrounds source package under `iPadInstrumentApp`; this hardware summary does not validate its iPad runtime.
- **Song ownership is partial:** song uses the existing BLE source; physical TTP/USB ownership is protected, but BLE free-play is mutually exclusive. Bit19 is not advertised.

## User-side next action

1. Keep the existing default bitstream; do not replace it yet.
2. If testing the candidate: use `candidate_music_hall/impl/pnr/audio_tone_music_hall.fs` only after accepting that it is a candidate.
3. Build/flash ESP v0.5 only after the matching FPGA candidate is installed.
4. Import the `.fpgasong` in the App (separate chat) or serve locally with `node tools/music_hall/serve_catalog.js` and use the LAN test URL.
5. Validate on hardware with the protocol's stop/disconnect/retrigger cases before promotion.

## New full packs

| Pack | Bytes | SHA256 | Events | Duration |
|---|---:|---|---:|---:|
| `fight_for_better_future.fpgasong` | 26,015 | `37e6c6f19e759ade667edb48ad011fe3e387ee2442f389d1c6caa77ec6053068` | 2,669 | 68.129 s |
| `rock_music_0.fpgasong` | 7,586 | `8e97d9d3071661e241ef277f083fdf2974f2ffa5f9f30255f039f39c108b53bb` | 207 | 32.000 s |
| `rock_theme_3_full.fpgasong` | 17,681 | `893f01477b0bbdf117e24ff9b55abf25518b48c4697d8eaee48af59276e2871a` | 1,404 | 64.988 s |

Catalog has all three entries. Both new packs pass `validate_pack`; no WAV/PCM is included.