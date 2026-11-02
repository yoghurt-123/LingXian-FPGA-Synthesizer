# BLE 表情完整版：已验收，包含在当前默认版本中

- BLE 表情完整版已由用户上板验收，并保留在当前默认位流中。
- 当前默认已升级为 ADC 滑杆滤波版：`impl/pnr/audio_tone.fs`
  SHA256 `A92125809FEF3AE6A910CD51A92D3AFC4856A3422D55B977168F6E51199B7C70`。
- BLE 表情验收原件仍为 `9A0C4DA3BDD96C73B4D8B76D56E09A576C570EE7DA5FE5A447841F9AF10CBD6A`
  （`20,273,311` 字节），已完整备份，可作为回退版本。
- App：v0.11.0（`iPadInstrumentApp/deliveries/FPGA_Instrument_v0_11_0`）。
- ESP：v0.4（`esp32/fpga_uart_bridge`）。
- BLE 验收基线资源：CLS 27788/29952、Logic 47983、FF 23528、
  BSRAM 93、DSP 81；setup +1.634 ns、TNS 0、audio Fmax 57.425 MHz。
- 当前 ADC 滤波默认新增资源：CLS 27959、BSRAM 95、DSP 82；
  setup 仅 +0.011 ns，详见 `DEFAULT_VERSION.md`。
- 未完成项仍保留：长 PCM、释放尾音、全力度/长并发，
  以及完整 BLE/TTP/USB 交叉验证；不要写成全部通过。
- 本阶段未修改 ESP/App，未自动烧录硬件，未写 Flash。
