# Next Song Source Research — 2026-10-27

Status: **source research only; no `.fpgasong` was created for these copyrighted songs.** The current accepted chain and existing packs are unchanged.

## Bottom line

I did not find a verified, legally usable, downloadable **complete multitrack** source for:

- 《晴天》— 周杰伦
- 《倔强》— 五月天
- Counting Stars — OneRepublic

The accessible HookTheory pages are **chord/theory analyses**, not MIDI, MusicXML or Guitar Pro files. Musicnotes has an official **Counting Stars** sheet-music catalog entry, but it is a sheet-music product, not a verified full-band multitrack MIDI. I did not download or convert fan MIDI, MuseScore arrangements or Guitar Pro tabs whose rights and track lists are unverified.

No track list is claimed below when no actual file was obtained. The conversion rule remains: do not infer a band arrangement from a chord page, audio preview or single-piano score.

## Findings

| Song | Actual accessible source checked | Format / status | Full-band multitrack? |
|---|---|---|---|
| 《晴天》Jay Chou | [HookTheory analysis](https://www.hooktheory.com/theorytab/view/jay-chou/sunny-day) | Theory/chord page; no MIDI/MusicXML download | No |
| 《晴天》Jay Chou | Musicnotes search for “Jay Chou Sunny Day” returned no matching Jay Chou product (only an unrelated “Sunny Day”) | No usable band source | No |
| 《倔强》Mayday | [HookTheory artist entry](https://api.hooktheory.com/theorytab/artist/mayday) | Artist/theory entry; no complete MIDI/MusicXML file | No |
| 《倔强》Mayday | Musicnotes search for “Mayday Stubborn” returned no matching titled sheet | No usable band source | No |
| Counting Stars — OneRepublic | [HookTheory artist entry](https://api.hooktheory.com/theorytab/artist/onerepublic) | Theory/analysis, not a score file | No |
| Counting Stars — OneRepublic | [Musicnotes search](https://www.musicnotes.com/search/go?w=Counting%20Stars); catalog entry [MN0119286](https://www.musicnotes.com/sheetmusic/mtd.asp?ppn=MN0119286) | Official sheet-music product; purchase required; no verified multi-track MIDI | No |

The preceding search is evidence only. A Musicnotes link is not a complete band MIDI and does not grant arrangement/redistribution rights.

## Why I did not “just find a MIDI”

Search results for these titles heavily surface:

- chord/theory pages;
- audio previews/YouTube;
- user-uploaded MuseScore/Ultimate Guitar/Songsterr arrangements;
- unofficial fan MIDI sites.

Those are not acceptable as a verified complete multitrack source under the project rules. In particular, a user-uploaded Guitar Pro/MuseScore file can be incomplete, have a different arrangement, or lack redistribution/arrangement rights; it cannot be presented as an official or verified source. No such file was downloaded or converted.

## Required source acceptance before conversion

A candidate is acceptable only if all of these are supplied or verifiable:

1. Actual downloadable file: `.mid`, `.musicxml`, `.mxl`, `.gp`/`.gpx`, or a licensed stem/score package.
2. Source URL, author/arranger, publisher, license/terms, and date.
3. Complete track list with instrument/program and format.
4. Evidence of the rights needed to make and distribute an FPGA arrangement.
5. Full-song verification: tempo map, meter changes, all sections, drum map, note durations/velocities, duplicates, and end-of-song tail.

If the source is a purchased sheet only, it may be usable for private study, but it is not automatically a full-band MIDI or an arrangement license. Conversion should wait for explicit permission.

## Recommended decision

- **Do not start 《晴天》/《倔强》/Counting Stars** with the current material.
- Choose one of:
  1. User supplies a licensed complete multitrack MIDI/MusicXML/Guitar Pro file with usage rights.
  2. Obtain a written arrangement/redistribution license from the publisher/arranger.
  3. Continue with verified CC0/public-domain sources like the three existing packs.
- If option 1 or 2 is provided, I will run the existing pipeline:
  - full track/program/tempo/meter/CC analysis;
  - explicit drum ID mapping;
  - piano/guitar voice-capacity and range checks;
  - 64 KiB performance limit and event-density checks;
  - package validation without changing the accepted playback firmware.

## Unchanged

- Existing three packs and catalog are untouched.
- No App, ESP or FPGA firmware changes.
- No unlicensed MIDI was downloaded into the repository.
