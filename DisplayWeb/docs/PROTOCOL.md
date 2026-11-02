# FPGA 串口数据接口说明

## 1. 物理接口结论

已验证链路：

```text
FPGA U15 (FPGA_UART.TX)
  -> 板载 FTDI USB JTAG/UART bridge RX
  -> USB 调试/JTAG-UART 口
  -> Windows COM 口（历史为 COM6，不能写死）
```

- 使用 **USB 调试/JTAG-UART**，不是 CH569 USB3。
- CH569 USB3 口需要 HSPI + CH569 USB CDC 固件，不能当普通 UART；本轮网页不依赖它。
- U15：LVCMOS33，PULL_MODE=UP，DRIVE=8，BANK_VCCIO=3.3。
- 串口：8N1，无流控；COM 号由用户在浏览器选择。
- 921600 是电脑设置值；实际 UART 分频为 52.5 MHz / 57 = 921052.6 baud。

## 2. 当前 USB Visualizer 候选帧（2026-10-30）

来源：

```text
GowinProjects/text4/delivery/usb_visualizer_20261030/
  audio_tone_music_hall.fs
  sim/usb_frame.bin
```

当前候选位流 SHA256：

```text
EE24034779285FEB02C9539853C2C06CB99DFABA73E18C177993752C7196A207
```

该帧只由当前 USB visualizer 实例驱动 U15；legacy `vofa_uart` 的 TX 已断开，不会把 JustFloat 和帧协议混在同一引脚。

### 2.1 固定帧头

`usb_frame.bin` 长度 550，SHA256：

```text
285B3781CF4876B4AEB0E37A3759F0E116194441DE2CDCE952493D09FA94C78C
```

前 20 字节：

```text
A5 5A 01 02 01 00 7E BC 00 00 00 01 10 00 10 02 01 00 00 00
```

| 偏移 | 长度 | 字段 | 当前值/说明 |
|---:|---:|---|---|
| 0 | 2 | magic | `A5 5A` |
| 2 | 1 | version | `01` |
| 3 | 1 | type | `02`（wave + spectrum） |
| 4 | 2 | seq | u16 LE，递增；测试向量为 1 |
| 6 | 4 | sample_rate | u32 LE，当前 48254 |
| 10 | 2 | wave_count | u16 LE，当前 256 |
| 12 | 2 | band_count | u16 LE，当前 16 |
| 14 | 2 | payload_len | u16 LE，当前 528 = 256×2 + 16 |
| 16 | 1 | flags | 当前 `01` |
| 17 | 1 | reserved | 0 |
| 18 | 2 | reserved | 0 |
| 20 | 512 | waveform | 256 个 int16 LE = **128 组 `{min,max}`** |
| 532 | 16 | spectrum | 16 个 uint8，低频到高频 |
| 548 | 2 | crc16 | CRC16-CCITT，LE；测试向量字节为 `67 5F`（值 0x5F67） |

### 2.2 波形 min/max 语义

- 512 个原始采样被分为 128 组，每组 4 个采样。
- 每组发送两个 int16：**min 在前，max 在后**。
- 一组在 payload 中的字节序：

```text
min_lo, min_hi, max_lo, max_hi
```

- 128 组在 550 字节帧中连续排列。
- 窗口长度：512 / 48254 = 10.61 ms。
- 网页必须把相邻 int16 识别为 min/max，不能把 256 个值当作普通采样点连线。

### 2.3 16 个 Goertzel 频段

当前候选使用 N=512、矩形窗的 Goertzel（不是 1024 点 FFT）：

```text
band  k   center Hz
0     1     94.2
1     2    188.5
2     4    377.0
3     6    565.5
4     8    754.0
5    11   1036.7
6    15   1413.7
7    20   1884.9
8    27   2544.6
9    35   3298.6
10   46   4335.3
11   60   5654.7
12   78   7351.1
13  100   9424.5
14  120  11309.5
15  145  13665.6
```

`usb_frame.bin` 的频段值：

```text
210,28,4,24,37,191,15,5,2,1,0,0,0,0,0,0
```

### 2.4 刷新和带宽

- 20 帧/s 标称；550 × 20 = 11,000 B/s，远低于 921600 8N1 的约 92,160 B/s。
- 传输只在完整快照后发送；上一帧 busy 时跳过新采集。
- 当前候选是 **min/max envelope**，不是原始逐点 PCM。

### 2.5 已验证/未验证边界

已验证：

- 帧头、序号、计数、采样率、长度、CRC16、min/max 顺序的 RTL 仿真。
- `usb_frame.bin` 的头/长度/CRC/Fixture 内容与网页解析测试。
- PnR 完成，Setup/Hold 0/0；但当前交付 README 说明声明的 full-scale 1 kHz 频谱判定仍有 band 0 泄漏问题，频谱验收未通过。
- 没有完成真实板卡 U15/FTDI 连续多帧验证。

网页不能把未验证的频谱说成“硬件已验证”；它只如实显示收到的 16 个频段。

## 3. Legacy 音频格式（JustFloat）

仍保留兼容，用于旧音频位流：

- UART 921600 8N1（实际 921052.6）。
- 每 8 字节一帧：

```text
float32 LE PCM (value == signed PCM16)
00 00 80 7F
```

- 采样率约 6031.71 frames/s（48,253.7 S/s，decimation 8）。
- 没有 FPGA 频谱，网页只显示 waveform + `NO FFT`，不伪造频谱。
- 没有音源活动时可能停发；超过 1.6 s 网页显示“数据中断”。

## 4. ADC 文本格式（不是音频）

- 115200 8N1，约 8 Hz。
- 正常：

```text
adc:mV0,mV1,mV2,mV3
```

示例：`adc:0000,0582,1128,1674`

- 心跳：`ADC_TEST_ALIVE seq=00001`
- 错误：`ADC_ERR addr=0x48 stage=00002 errors=00003`
- 网页只作为 ADC 遥测显示数值/状态，不绘制音频波形或频谱。

## 5. 网页识别与严格校验

1. 首字节 `A5 5A` → 二进制帧模式。
2. **当前候选签名**：`type=2`、`wave_count=256`、`band_count=16` → 128 组 min/max + 16 bands。
3. 其他奇偶/计数组合按 raw PCM 兼容路径处理（用于旧帧），但不会把当前候选误读为 256 个逐点采样。
4. VOFA 帧尾 `00 00 80 7F` → legacy PCM。
5. ADC 文本 → ADC 遥测。
6. 未识别/错误数据只保留有界缓冲，显示协议不匹配；不生成假波形。

### CRC 严格性

- CRC16-CCITT：初值 `0xFFFF`，多项式 `0x1021`，不反射。
- 覆盖 0 到 `20+payload_len-1` 的所有字节。
- CRC 不匹配时整帧丢弃，不显示该帧的波形/频谱。
- 网页诊断会显示错误码、帧偏移、帧长度、wave/band 计数、expected/actual CRC。
- **不放宽 CRC，不用演示数据替代失败帧。**

### 原始字节预览

网页诊断面板提供有界 RX hex/ASCII 预览（默认最近 2 KiB），包含帧头、payload 和 CRC；用于人工核对 `usb_frame.bin` 和现场串口数据。

## 6. 未来的通用帧扩展

如果 FPGA 团队新增通用协议，保持现有 header/CRC 规则；建议把 `type=2 + 256/16` 固定为当前 min/max 候选，其他计数保留 raw PCM 或新增明确 type，避免隐式歧义。

## 7. CH569/HSPI

本轮不改 CH569 固件，不使用 CH569 USB3 口。若后续采用，需要单独实现 FPGA HSPI 帧发送与 CH569 USB CDC 接收，不能把它当 UART。

## 8. 素材与运行

- 网页不依赖云端；照片在本地导入，串口数据只在本机浏览器处理。
- COM 号、FTDI 驱动、串口占用是 Windows/硬件侧问题，网页只显示可理解的错误。
