# Default Version - 2026-10-31 (32-band USB visualizer + guitar OD/A2)

## Status

The accepted 32-band USB visualizer build with the accepted guitar default-
overdrive and A2-strength candidate is now the default main-project bitstream.
The accepted candidate FS was copied into the default path; the default project
was also synthesized and placed/routed as a build check. The checked build hash
is recorded below, but the default path keeps the accepted candidate FS.

- Default FS:
  `E:\EmbeddedCompetition\GowinProjects\text4\impl\pnr\audio_tone.fs`
- SHA256:
  `8982D56EA3FD2302C14539B3BE9A8598500A00A76551090DE54D6835C8CF26C8`
- Accepted source archive:
  `E:\EmbeddedCompetition\GowinProjects\text4\candidate_usb_visualizer_32band_success_20261030`
- Accepted guitar candidate:
  `E:\EmbeddedCompetition\GowinProjects\text4\candidate_guitar_od_a2_20261031`
- Accepted candidate delivery:
  `E:\EmbeddedCompetition\GowinProjects\text4\delivery\guitar_od_a2_20261031`
- Default-project routing-check output (preserved, not default):
  `backups\main_pre_guitar_od_a2_20261031\audio_tone_music_hall_routed_13A14.fs`
  SHA256 `13A14E2720E21B5C30171769BBA6991547A1D3C7E2471BC9896E5E485E418DB2`
- Main top: `src/top.v` SHA256
  `6397BD44CFC4DFDB4BF1E01337DD3274FD5635B89DB03D2B0243559C112281A7`
- Main visualizer: `src/visualizer/usb_visualizer.v` SHA256
  `1D96C60BFE14819164827F8F4A4305DA0526480293E2CAD0FE40A8DC21AB5CA9`
- Guitar phase RAM source: `src/tone/guitar_voice.v` SHA256
  `5E48B78E88EC676D3C3878B6C8663AE7D3D9D7C4183C466A2B87571FA7DAFE1D`
- Guitar FX source: `src/tone/guitar_fx.v` SHA256
  `F4F77B369B85DAFBD783CB85CA755C12E0D8BB5D15C62643936CEE19ADF0D486`
- EF4C audio baseline SHA256:
  `EF4C8D8AA9276063CDDEEA189850AC10D453832EC15E0884DA0017EF3F5088AB`

## Resource and timing

From the default-project build-check P/R report (accepted candidate has the same resource/timing class):

- CLS: 25,676 / 29,952 (86%)
- Logic: 40,784 / 59,904 (69%)
- Register: 20,652 / 60,780 (34%)
- BSRAM: 108 / 118 (92%)
- DSP: 97 / 118 (83%)
- Setup violated endpoints: 0
- Hold violated endpoints: 0
- Fmax: audio_clk 53.512 MHz (constraint 52.5), sys_clk 66.556 MHz,
  usb_clk 110.572 MHz
- PnR warning: `sys_clk_d` uses generic clock routing; timing has no violations.

## USB visualizer protocol

- UART pin U15, 921600 8N1, 52.5 MHz / 57 divider.
- Type `0x02` framed protocol, magic `A5 5A`, version `01`.
- `wave_count=256`: 128 interleaved min/max int16 pairs.
- `band_count=32`; `payload_len=544`; total frame 566 bytes.
- Sample rate field: 48254.
- Goertzel, 512-sample window, 32 unique log-spaced bins from 94.2 Hz to 18.28 kHz.
- Bin spacing 94.2 Hz; 32 bands do not increase physical low-frequency resolution.
- Amplitude is a 0..255 log-magnitude-like Goertzel power level, not dBFS.
- Center-frequency metadata:
  `delivery\usb_visualizer_32band_20261030\spectrum_bands_32.json`
- The existing web parser accepts up to 64 bands; old 16-band type-2 frames remain
  compatible. The webpage's min/max interpretation remains a separate display
  adaptation.

The legacy `vofa_uart` remains instantiated for `vofa_frame_done`/stop behavior,
but its TX pin is disconnected. Only the visualizer drives U15.

## Files/configuration

The main project now contains the 32-band source and configuration copied from the
accepted archive:

- `src/top.v`
- `src/visualizer/usb_visualizer.v`
- `src/tone/guitar_voice.v` (phase RAM optimization)
- the remaining audio source and ROM/initialization files
- `src/constraints/audio.cst`
- `src/constraints/timing.sdc`
- `audio_tone.gprj`
- `build_syn.tcl`
- `streamfix_pnr_place2.tcl`

Project file check: 74 file entries, 0 missing; the `.mem`, `.hex`, and `.vh`
source data remain present.

## Rollback

Pre-guitar-OD default backup:

- `E:\EmbeddedCompetition\GowinProjects\text4\backups\main_pre_guitar_od_a2_20261031`

Pre-route default backup (accepted copied bitstream `8B9D...`):

- `E:\EmbeddedCompetition\GowinProjects\text4\backups\main_default_pre_route_20261031`

Previous pre-promotion backup:

- `E:\EmbeddedCompetition\GowinProjects\text4\backups\main_pre_32band_promote_20261030`
- Old default FS: `impl/pnr/audio_tone.fs` SHA256
  `A92125809FEF3AE6A910CD51A92D3AFC4856A3422D55B977168F6E51199B7C70`
- Old main top SHA256:
  `018A10C0A790248DCC5A32AEE5A0451CDF05CC6992D2801733C691C6C75E5E36`

To roll back, restore that backup's `src/`, project/build files, and old default FS.
The accepted 16-band powerfix build is also preserved at:
`delivery\usb_visualizer_20261030_powerfix`
(SHA256 `7D20E8F49E02A11A762B7A66F32858570C39194E7EFDC697745CE441B272C834`).
The EF4C fallback remains:
`candidate_adc_fx34\impl\pnr\audio_tone_music_hall.fs`
(SHA256 `EF4C8D8AA9276063CDDEEA189850AC10D453832EC15E0884DA0017EF3F5088AB`).

## Hardware/verification boundary

- No hardware programming was performed by this promotion.
- No new PnR was run for the promotion; the accepted FS was copied byte-for-byte.
- The FTDI/COM zero-byte issue is not claimed as solved. Windows currently does not
  enumerate the FTDI debug UART in this session; COM selection remains user-side.
- The accepted 32-band module tests cover 1 kHz, 2 kHz, 1 kHz + 2 kHz, silence,
  multiple amplitudes, four consecutive windows, CRC, and min/max ordering.
- Real-board 32-band reception still needs user acceptance.
- Rainbow colors, display heights, and drum visual effects remain webpage-side.
