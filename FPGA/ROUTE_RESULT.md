# FPGA routing result

This routing was performed only inside `Submission_Final/FPGA`; the original
`text4` default project and the accepted bitstream were not overwritten.

- Routed FS: `FPGA/impl/pnr/audio_tone_music_hall.fs`
- SHA256: `8DA16F05029A5CCDF64406865E4AE446BD75D8BF959E770EDAC8FB36806F0BA8`
- Size: 20,706,359 bytes
- Resource: CLS `25676/29952`, Logic `40784/59904`, BSRAM `108/118`, DSP `97/118`
- Setup violations: 0; hold violations: 0
- Fmax: audio_clk `53.512 MHz`, sys_clk `66.556 MHz`, usb_clk `110.572 MHz`
- Report: `FPGA/impl/pnr/audio_tone_music_hall.rpt.txt`
- Timing detail: `FPGA/impl/pnr/audio_tone_music_hall_tr_content.html`

The accepted default artifact remains:

`AcceptedBinaries/FPGA/audio_tone.fs`

SHA256 `8982D56EA3FD2302C14539B3BE9A8598500A00A76551090DE54D6835C8CF26C8`

The routed result is a fresh check build and is **not** automatically promoted
to the accepted default.
