# Music hall static catalog / download channel

## Actual files

- Catalog: `music_packs/catalog.json`
- `music_packs/fight_for_better_future.fpgasong` — 26,015 bytes, SHA256 `37e6c6f19e759ade667edb48ad011fe3e387ee2442f389d1c6caa77ec6053068`
- `music_packs/rock_music_0.fpgasong` — 7,586 bytes, SHA256 `8e97d9d3071661e241ef277f083fdf2974f2ffa5f9f30255f039f39c108b53bb`
- `music_packs/rock_theme_3_full.fpgasong` — 17,681 bytes, SHA256 `893f01477b0bbdf117e24ff9b55abf25518b48c4697d8eaee48af59276e2871a`

No public URL is published by this repository. The catalog therefore contains `public_url: null` and must not be presented as an online store.

## Local / LAN test channel

From `E:\EmbeddedCompetition\GowinProjects\text4`:

```powershell
node tools\music_hall\serve_catalog.js
```

The server listens on port 8081 (unless `PORT` is set). Test locally:

```powershell
Invoke-WebRequest http://127.0.0.1:8081/music_packs/catalog.json
Invoke-WebRequest http://127.0.0.1:8081/music_packs/fight_for_better_future.fpgasong -OutFile $env:TEMP\fight.fpgasong
Invoke-WebRequest http://127.0.0.1:8081/music_packs/rock_music_0.fpgasong -OutFile $env:TEMP\rock.fpgasong
```

For an iPad on the same LAN, replace `127.0.0.1` with the PC's actual LAN IP and allow inbound TCP 8081 in the firewall. That LAN URL is a test channel, not a public release.

## Import fallback

The App must also support Files import of each `.fpgasong`, because a LAN URL may not be reachable and the package must be checked before caching to ESP.

## Integrity and limits

- App verifies package SHA256, manifest version and required capabilities.
- App sends only `performance.bin` to ESP, not WAV, PCM, ZIP or stage assets.
- Fight for Better Future uses all source drums (414 hits), tempo 155.000 BPM, 4/4; required capabilities include piano/guitar/drums.
- Rock Music uses source guitar + drums (135 + 39 events), tempo 120 BPM, 4/4, no piano because the source has no independent piano/bass/synth; required capabilities are guitar/drums.
- Never place a fabricated URL in the catalog.
