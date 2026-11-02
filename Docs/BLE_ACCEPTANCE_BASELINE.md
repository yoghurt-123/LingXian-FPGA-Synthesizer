# BLE Acceptance Baseline

- App: v0.10.2
- ESP: v0.3
- FPGA bitstream: `candidate_ble_uart/impl/pnr/audio_tone_ble_uart.fs`
- SHA256: `3534217A8C1B0EF81E2064C0FE327F063F016A36B1E2E937B0C0FE8BE5AF9714`
- User hardware acceptance: passed basic BLE performance chain.
- Full archive: `E:\EmbeddedCompetition\backups\ble_uart_accepted_20261025_0500\`
- `docs/DEFAULT_VERSION.md` still describes the older 4B195D nine-drum default
  and is not the BLE acceptance baseline.

This baseline is kept for rollback and as the source tree for
`candidate_ble_expression`. The legacy root `E:\EmbeddedCompetition\esp32`
ESP copy is not used for new work; the new ESP path is
`text4\esp32\fpga_uart_bridge`.

Known not fully validated in this baseline: strict full-top release-tail
numeric zero, complete source-interleaving matrix, full long PCM, real
capability reporting, and the expression controls added next.
