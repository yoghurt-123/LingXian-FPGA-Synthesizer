# App Music Hall V1 Implementation Handoff — v0.15.4

Date: 2026-10-27  
App version: **v0.15.4** (source package; no Xcode build on Windows)  
Consumed artifacts:

- `MUSIC_HALL_PROTOCOL_V1.md`
- `protocol_vectors_v1.json`
- `MUSIC_HALL_HANDOFF_V1.md`
- `music_packs/catalog.json`
- `music_packs/rock_theme_3_full.fpgasong`
- `STATIC_CATALOG.md`

## Fixed in v0.15.1/v0.15.4

1. **BEGIN is always 40 bytes.** The old 8-byte short BEGIN and the 40-byte fallback loop were removed from `MusicHallBLETransport.swift`. It now sends exactly:
   `session32 + total_bytes32 + performance_sha256[32]`.
   ESP v0.5 now accepts only `len == 40`; other lengths return a protocol error. No length guessing.
2. **SHA-256 semantics are explicit.** The digest is over `performance.bin` only (not ZIP/score/stage/WAV). The same digest is carried in BEGIN and COMMIT. ESP stores the BEGIN digest and requires it to equal both the COMMIT digest and the digest it computes over received bytes. COMMIT is authoritative for received bytes.
3. **E2 reply CRC is fixed and audited.** CRC8 covers `TYPE SEQ LEN PAYLOAD`; it does **not** include the `E2` byte. Fixed ESP replies:
   - CAPS_RSP: CRC over type/seq/len/9-byte payload. For seq 0 the frozen result is **0x4C**.
   - STATUS: CRC over type/seq/len/10-byte payload.
   - ERROR: CRC over type/seq/len/1-byte payload (previous length was off by one).
   - PROGRESS forwarder (dormant): same rule.
   The App encoder/parser already uses `bytes[1...]`; it was audited, not changed to a second rule.
4. **PLAY reply is explicitly ESP transport state.** ESP state `2` means “PLAY accepted and ESP started streaming toward FPGA”. It is **not** an FPGA execution acknowledgement. The FPGA candidate has no ready/execution acknowledgement and no hardware progress. App labels and status messages were changed; the playback timeline remains explicitly estimated.
5. **PLAY status sequence** now echoes the PLAY request sequence; the old unconditional `seq=0` and the App `acceptsSequenceZero` PLAY exception were removed.

## Shared vector verification

`docs/music_hall/protocol_vectors_v1.json` includes:

- BLE CAPS_REQ / CAPS_RSP (CRC **0x4C** for seq 0)
- BLE BEGIN exactly 40 payload bytes
- BLE DATA, COMMIT (same SHA-256), STATUS, PLAY_STATUS, ERROR, STOP
- UART SONG_BEGIN / SONG_PLAY / SONG_EVENT / SONG_STOP

Run from the project root:

```powershell
node tools\music_hall\verify_protocol_vectors.js
```

Expected: `PASS all shared protocol vectors`. This validates the shared wire bytes and the ESP/App CRC rule; it is not an iPad runtime test.

## Versions and hashes

- App: **v0.15.4** source package; this ZIP is a source repack, not an Xcode-compiled IPA.
- ESP: v0.5.3-start-tx, binary SHA256 `0B090F1E4FA8249B385C040540C0AFD07BB5533D20A64F06C4D96C01D3C01818`; merged `9B8A0E63F8ADA1BCC00B337FC59A5B586D25774D1697133FD83A46A5BF195E9F`.
- FPGA candidate: unchanged from `7355A942576F93079BAD782466F79A6D37C67A5F312E48B8155069B1D88A36C0`; **no FPGA bitstream change in this fix**.
- Package: `893F01477B0BBDF117E24FF9B55ABF25518B48C4697D8EAEE48AF59276E2871A`, 17,681 bytes.
- Default FPGA: `A92125809FEF3AE6A910CD51A92D3AFC4856A3422D55B977168F6E51199B7C70`; unchanged.

## Fixed in v0.15.3/v0.15.4

1. **Actual stage.json format.** `score/stage.json` uses `start_bar`/`end_bar`. `MusicHallStageSection` now stores `startBar`/`endBar`, and the decoder also accepts legacy `bar_start`/`bar_end`/`barStart`/`barEnd` without combining a manual underscore key with `.convertFromSnakeCase` incorrectly. All stage consumers were updated.
2. **Specific pack decode errors.** Manifest, score and stage decoding now report the actual file name, missing field, codingPath and DebugDescription instead of a generic JSON error.
3. **CAPS v3 support.** `CAPS;3;...` is accepted alongside `CAPS;2`; `isReady`, status text, free-play routing, `PerformanceWireEncoder`, piano/guitar/drum gating and the three game paths use the real capability mask. Unknown versions, reserved status and missing base bits remain rejected. Legacy `FPGA_STATUS;1` is unchanged.
4. **Real pack regression path.** The source test bundle includes `TestAssets/rock_theme_3_full.fpgasong` and a test that extracts and validates the actual manifest, score, stage and performance. A second test covers legacy stage keys and a third checks decode error context. These are source tests, not executed on Windows.

## Preserved protections

- STOP/CANCEL/connection-loss still invalidate the App session and prevent old queue replay.
- Free-play remains separate and blocked while a hardware song session is active/unconfirmed.
- Capability bits: bit16 timed queue, bit17 bulk transfer; bit18 progress false; bit19 song-owned release false.
- No public URL; LAN/static and Files import only.
- Pause/seek/remote volume remain disabled.

## Not claimed

- No Swift compilation on Windows and no iPad runtime.
- No real BLE upload/COMMIT/PREPARE/PLAY/STOP or listening test on board.
- No FPGA execution confirmation or hardware progress.
- No complete hardware acceptance.
