# App v0.11.0 已上板验收

App v0.11.0 已完成 BLE 表情完整版上板验收；以下为对接参考，协议以
`BLE_CONTROL_PROTOCOL.md` 为准。默认 FPGA 为 `impl/pnr/audio_tone.fs`
（9A0C…），ESP 为 v0.4。
# App vNext Handoff — BLE Expression Candidate

Do not change the App in this hardware phase. This is the interface the App
should implement after the hardware candidate is accepted.

## Source of truth

`E:\EmbeddedCompetition\GowinProjects\text4\docs\BLE_CONTROL_PROTOCOL.md`

Event numbers, key codes, ranges, CRC and capability bits must be copied from
that document, not invented in the App.

## Compatibility

- Old App v0.10.2 packets `E0 01/02/03/04/05/06` remain accepted.
- New events are additive.
- The ESP still accepts ASCII `PING`, `FPGA_PING`, `FPGA_STATUS`, `STATUS`,
  `BLE_RELEASE`, `ALL_OFF`.
- Capability query is `E1 00` (or ASCII `FPGA_STATUS`). The ESP returns
  `CAPS;<version>;<8hex-caps>;<status>` from the FPGA, e.g.
  `CAPS;2;0000FFFF;0`. Do not hard-code a mask in the App; inspect it.

## App packet

Exactly four bytes to RX:

```text
E0 EVENT KEY VALUE
```

ESP adds sequence/CRC. Music events are not acknowledged; do not wait for a
PONG between notes. Keep App-to-ESP ordering; the ESP preserves it.

## Required order rules

- Guitar: send `GTR_FRET` and `GTR_PALM` before `GTR_PLUCK`; pluck carries its
  string and velocity. The FPGA latches current fret/palm with the request.
- Chord: `CHORD_SELECT` then `CHORD_TRIGGER`; select alone is silent.
  `CHORD_RELEASE` cancels a not-yet-committed BLE trigger. A committed chord
  is the original short one-shot pattern, not a sustained source.
- Piano: send `PIANO_OCT` before `PIANO_NOTE_ON`; octave is latched at the
  trigger. Use `NOTE_OFF` for BLE-owned notes.
- Damping/pedal: `DAMP=1` gives the old release-on-note-off behavior;
  `DAMP=0` leaves natural decay. With damping on, `PEDAL=1` defers BLE
  note-off releases until `PEDAL=0` or `PEDREL`.
- BLE release (`0x05`) releases BLE notes/pending notes and continuous BLE
  expression state, not physical USB/TTP notes and not shared FX targets.
- `ALL_OFF` (`0x06`) is the existing global panic/kill and is separate.
- BLE disconnect/session restart must not replay old notes.

## Event examples

```text
E0 21 03 00       set fret 3
E0 22 01 00       palm mute on
E0 20 00 0C       pluck E2 string at velocity 12
E0 23 00 00       select U/C chord, no sound
E0 24 00 0F       trigger selected chord at velocity 15
E0 25 00 00       cancel pending BLE chord trigger
E0 26 01 00       bend left (-2 semitones)
E0 27 01 00       vibrato on
E0 28 01 00       glide on
E0 29 0A 00       slide time 10 (200 ms)
E0 2A 01 00       overdrive target on
E0 2B 01 00       reverb target on
E0 30 02 00       piano high octave, latched next note
E0 31 01 00       BLE damping on
E0 32 01 00       BLE delayed release on
E0 33 00 00       release pending BLE pedal notes
```

## What the App must show as global

- Overdrive/reverb are shared guitar effects.
- Bend/vibrato/glide/slide/fret targets are shared expression state; USB
  expression keys have priority while active.
- The FPGA does not provide independent per-source guitar DSP chains.

## Hardware acceptance tooling

- BLE path: App or nRF Connect writes the four-byte packets.
- USB path: ESP CDC commands in `BLE_CONTROL_PROTOCOL.md`; use
  `tools\ble_expression_test.ps1` with the actual COM port. Do not open the
  Arduino serial monitor and the script at the same time.
- USB injection is evidence for the ESP/UART path, not proof of BLE radio/
  App behavior. Record both separately.

## Pending before App integration

- Candidate PnR is complete; listening/hardware test remains.
- Hardware BLE + USB same-note/source interleaving.
- Chord release behavior acceptance (one-shot pattern semantics).
- Piano damping/pedal hardware behavior with physical USB/TTP.
- Full nine-drum/piano/guitar long PCM.



