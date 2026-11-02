# Version Manifest

## FPGA

- Version: accepted 32-band visualizer + accepted guitar OD/A2 candidate
- Default bitstream: `AcceptedBinaries/FPGA/audio_tone.fs`
- SHA256: `8982D56EA3FD2302C14539B3BE9A8598500A00A76551090DE54D6835C8CF26C8`
- Top: `FPGA/src/top.v`
  SHA256 `6397BD44CFC4DFDB4BF1E01337DD3274FD5635B89DB03D2B0243559C112281A7`
- Guitar FX: `FPGA/src/tone/guitar_fx.v`
  SHA256 `F4F77B369B85DAFBD783CB85CA755C12E0D8BB5D15C62643936CEE19ADF0D486`
- A0/A1 baseline: `FPGA/src/filter/adc_filter_audio.v`
  SHA256 `8BB50B3C04536D52E6BDEEF9A5535E45A7CF7E06D2A4327469CAC2B1A8761533`
- Project: `FPGA/audio_tone.gprj`
  SHA256 `D0BB7BBEE30E6954E8D1ACD6CEBA6C87AEFF9E05C0BB29A2A8B4A05A78B8928F`
- P/R: no new P/R was run on the original default project. A separate P/R was run only inside the submission copy; the accepted default was not replaced.
- Routed submission FS: `FPGA/impl/pnr/audio_tone_music_hall.fs` SHA256 `8DA16F05029A5CCDF64406865E4AE446BD75D8BF959E770EDAC8FB36806F0BA8`
- Resource report: CLS `25676/29952`, Logic `40784/59904`, BSRAM `108/118`, DSP `97/118`; setup/hold violations 0.
- Fmax: audio_clk `53.512 MHz`, sys_clk `66.556 MHz`, usb_clk `110.572 MHz`.
- Default bitstream is the accepted artifact `AcceptedBinaries/FPGA/audio_tone.fs`; the fresh submission-copy route is `FPGA/impl/pnr/audio_tone_music_hall.fs` and is not auto-promoted.

## ESP32

- Version: `v0.5.3-start-tx` / music hall
- Source: `ESP32/fpga_uart_bridge/fpga_uart_bridge.ino`
  SHA256 `D0F21E1BB9108C818E1D1AA405AC2F16B64E61409EAA99782365B0125952030F`
- Final application binary: `ESP32/fpga_uart_bridge/build/fpga_uart_bridge.ino.bin`
  SHA256 `0B090F1E4FA8249B385C040540C0AFD07BB5533D20A64F06C4D96C01D3C01818`
- Final merged flash image: `ESP32/fpga_uart_bridge/build/fpga_uart_bridge.ino.merged.bin`
  SHA256 `9B8A0E63F8ADA1BCC00B337FC59A5B586D25774D1697133FD83A46A5BF195E9F`
- Toolchain: Arduino ESP32 core `3.3.12`, FQBN `esp32:esp32:esp32c3:CDCOnBoot=cdc`.
- Wiring/protocol: `ESP32/fpga_uart_bridge/README.md`, `Docs/BLE_CONTROL_PROTOCOL.md`.

## iPad App

- Name: `AURAL 乐器手记`
- Version: `0.17.0`, bundle `29`
- Project: `iPadApp/FPGA instrument.swiftpm`
- Package: `Package.swift`
  SHA256 `EB4C1D736AE7443E75ECF72EC5D2068FE7AC1D0E6C7A17E7986A967A580EC911`
- AppInfo: `AppInfo.swift`
  SHA256 `7266DDA9557242C81F56F17FEDD09B3BFA7746A3BF0C2257D908D08ABB1F0BA8`
- Files: 75; total 19,346,629 bytes.
- `.swiftpm/` and `Resources/` are included. Resource `orbit-motion-loop.mp4` SHA256 `54E0A837E4EBA16F007A3CA045CDC31E211E49DC43D246FB63E87BC9AF0332C8`.
- The current text4 source matched the v0.17.0 delivery source at copy time (71 source/resource entries; no historical delivery copied).

## DisplayWeb

- Package: `instrument-display-web` v1.0.0
- Source: `DisplayWeb/` (external final source was copied read-only)
- `package.json` SHA256 `3CAD9BD5FBD2BBE684C9DC2CD81D186163A8E2A1A482215BA2BF092831F8A44C`
- `package-lock.json` SHA256 `F9E8E9F515D2B2B8810AB108FA256A5237F21F8FBA988AAD827AC2769DF5B4A1`
- Built JS: `dist/assets/index-CoPCuTsD.js` SHA256 `AE4A52D1989BE4C56CC0CA1EBE7E962A2CD94143760D7B62F7D2ECAE99C5CC53`
- Built CSS: `dist/assets/index-C25oNH1s.css` SHA256 `43D8400E03F206BA7A296EE2E0B1379799B1C2202F0DFB1EE406015D411EF0E9`
- Default photos: 8 in `public/photos/` and 8 in `dist/photos/`.
- Source README still contains a historical 16-band description; the parser is `MAX_BANDS=64` and the final default FPGA is 32-band. See `DisplayWeb/SUBMISSION_NOTE.md`.
- The external web source was not modified; only the copied README startup path was made relative.

## MusicPacks

- `MusicPacks/` contains the generated `.fpgasong` catalog and the validated Back in Black package.
- `MusicPacks/back_in_black_20261031.fpgasong`
  SHA256 `60EFC56358E35AC946E741C2D3044A2DDC9E80B59FD69C072E423877CFE0C1E6`
- No source video/audio or PCM payload is included.
