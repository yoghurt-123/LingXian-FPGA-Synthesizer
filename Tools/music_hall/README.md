# Music Hall M0 tools

Prototype only. These tools do not modify the FPGA project, default bitstream,
ESP firmware, or App. They do not run PnR and do not program hardware.

## Commands

```powershell
cd E:\EmbeddedCompetition\GowinProjects\text4

# Rebuild the original 8-bar technical demo score (not Let It Be)
node tools\music_hall\generate_demo_score.js

# score.json -> performance.bin + report.json
node tools\music_hall\compile_song.js music_packs\m0_technical_demo\score.json music_packs\m0_technical_demo

# manifest.json (hashes/sizes) and .fpgasong ZIP
powershell -NoProfile -ExecutionPolicy Bypass -File tools\music_hall\build_pack.ps1 `
  -PackDir music_packs\m0_technical_demo `
  -Output music_packs\m0_technical_demo.fpgasong

# Validate manifest hashes, FPGS header, event count, and byte-identical recompilation
node tools\music_hall\validate_pack.js music_packs\m0_technical_demo
```

## Output meaning

- `performance.bin` is the proposed 8-byte timed-event stream. The current
  firmware does not consume it.
- `report.json` checks piano range/16 voices/same-key release, guitar 4-voice
  pool, drum IDs and same-tick velocity, event ordering, density and queue
  estimate.
- `music_packs/m0_technical_demo` is an **original technical demo**, not a
  transcription or arrangement of "Let It Be".

## App catalog test server

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\music_hall\serve_app_catalog.ps1 `
  -Packs music_packs\m0_technical_demo.fpgasong -Port 8080
```

It generates `music_packs\music_hall_serve\catalog.json`, copies the pack, and serves both over HTTP.
Paste the printed catalog URL into the App music-hall catalog setting.
The M0 pack is a technical demo, not Rock Theme 3. iOS ATS may block cleartext HTTP;
use Files import or an HTTPS test server if that happens.

## Non-goals

- No MIDI/MusicXML importer is claimed complete.
- No real echo/delay: A2/A3 are reserved ADC parameters.
- No ESP flash writer, BLE transfer, FPGA timed queue or App UI is implemented
  in M0.
