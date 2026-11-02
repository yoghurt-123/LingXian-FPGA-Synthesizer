> **设计与方案统一入口：**[主工程文档目录](docs/README.md)。以下包含早期工程说明，当前功能请以目录中的USB集成记录为准。

2026-09-19 更新：已添加 USB 串口 JustFloat 输出，详见 [VOFA使用说明](VOFA使用说明.md)。下文保留原音频工程说明，原版源码和位流位于 backup_before_vofa_20260919。

# Tang Mega 60K：FPGA 内部生成音频采样值

本工程从 Sipeed 官方 TangMega-138KPro-example 的 `audio/audio_sinewave` 移植到 Tang Mega 60K NEO Dock。默认输出约 440 Hz 正弦测试音，左右声道相同，无需 SD 卡、音频文件、外接 ADC 或处理器。

## 打开与使用

1. 用 Gowin IDE V1.9.12.03 打开 `C:\GowinProjects\TangMega60K_audio_tone\audio_tone.gprj`。
2. 目标芯片沿用之前 LED 工程：`GW5AT-LV60PG484AC1/I0`，B 版。
3. 可直接使用已编译的 `impl/pnr/audio_tone.fs`，或重新执行综合、布局布线、生成下载文件。工程已配置 CPU、SSPI 为普通 IO。
4. 在 Gowin Programmer 中选择这份 `.fs`，先下载到 SRAM 测试。这里未自动向开发板下载。
5. 从底板 3.5 mm 耳机接口收听，或使用底板扬声器接口 J27/J28。默认采样幅度为满幅的 1/8。
6. KEY.2 按下时复位并关闭功放，松开后约 1.25 ms 自动重新开始。正常上电无需按键。

请在英文路径编译。此电脑上的高云命令行工具无法正确处理 `E:\嵌入式赛题` 中文路径。

## 信号链

内部 OSCA（标称 52.5 MHz）→ 采样节拍 → 32 位相位累加器 → 官方 256 点正弦查找表 → 16 位有符号 PCM → PT8211 串行接口 → 板载 DAC、功放 → 耳机/扬声器。

- BCK：52,500,000 / 34 ≈ 1.544118 MHz。
- 每帧左右声道各 16 位，共 32 位；采样率约 48,253.676 Hz，不是严格 48 kHz。
- 正弦波：相位步进 39,163,557，标称频率约 440 Hz。实际频率受内部振荡器误差影响。
- 仅在一帧开始时推进一次相位，同时锁存该帧采样值，左右声道共享此值。
- PT8211 使用 **16 位右对齐 LSBJ**，不是标准 I2S 的一位延迟格式。WS=0 是右声道，WS=1 是左声道。
- 数据和 WS 在 BCK 下降沿更新，DAC 在上升沿接收，按 MSB 到 LSB 顺序发送。

## 文件与修改方法

| 文件 | 用途 |
| --- | --- |
| `src/top.v` | 顶层、上电复位、功放使能、频率和音量参数 |
| `src/sine_wave.v` | FPGA 内部相位累加器与正弦采样表 |
| `src/audio_driver.v` | PT8211 双声道串行发送 |
| `src/audio.cst` | 60K 实际引脚及电平 |
| `src/timing.sdc` | 内部主时钟约束 |
| `src/gowin_osc/gowin_osc.v` | 沿用之前 60K LED 工程的内部振荡器 IP |
| `sim/` | 自动校验的 ModelSim 测试与运行脚本 |
| `official_reference/` | 下载的官方原始工程，供对照，不参与本工程编译 |
| `docs/` | 仿真记录和验证说明 |

在 `src/top.v` 修改 `PHASE_STEP`，计算公式：

`PHASE_STEP = round(目标频率 × 2^32 × 1088 / 52500000)`

修改 `VOLUME_SHIFT` 可改变幅度：3 为 1/8，4 为 1/16，数值越大声音越小。必须重新编译并下载后生效。

## 已核对的引脚

依据本地 `Tang_Mega_NEO_Dock-60K_31004_Schematics.pdf` 第 7、10 页：

| 信号 | FPGA 引脚 | 说明 |
| --- | --- | --- |
| HP_BCK | Y17 | 音频位时钟，3.3 V |
| HP_WS | AB17 | 声道选择，3.3 V |
| HP_DIN | AA16 | DAC 串行数据，3.3 V |
| PA_EN | AB16 | **低电平开启**功放，3.3 V |
| rst_n | Y12 | KEY.2，低电平复位，1.5 V，内部上拉 |

## 验证结果与范围

2026-09-19：Gowin V1.9.12.03 综合、布局布线及位流生成成功。内部 52.5 MHz 时钟的 setup/hold TNS 均为 0，工具报告 Fmax 为 254.331 MHz。占用 119 个逻辑资源、92 个寄存器、1 个 BSRAM。

ModelSim 10.5b 仿真通过：从输出引脚解码 1628 个立体声帧，对比正弦采样数据，检查每声道 16 位、左右一致、每 1088 个主时钟一个采样以及复位后重启。

尚未进行开发板实测、模拟音质测量或外部 DAC 引脚的板级时序测量。SDC 验证内部时钟路径，未建立外部 DAC 的输入延迟模型。接收时序已通过 RTL 仿真核对。

## 官方来源与改动

- 官方例程：https://github.com/sipeed/TangMega-138KPro-example/tree/main/audio/audio_sinewave
- 本地 60K 官方仓库的 `audio_i2s` 和 `audio_sd` 目录只有 TBD，因此选用同厂商其他板型的实际音频例程。
- 保留官方 256 点采样表，改为采样节拍驱动的 DDS；重写发送逻辑，消除跨时钟取样和分频误差问题。
- 替换为 60K 器件、引脚、电平和复位极性，修正 60K NEO 底板功放低有效使能。
- 原始工程文件保留其版权声明；移植版为修改作品，不代表官方发布或官方验证。
- PT8211 厂商资料：https://www.princeton.com.tw/en-us/Products/Multi-Media-Audio/Digital-to-Analog-Converter

## 命令行编译与仿真

编译：用本机 Gowin `gw_sh.exe` 执行工程根目录下的 `build.tcl`。

仿真：进入 `sim` 目录，执行 `vsim -c -do run.do`。仿真器命令需已加入 PATH，或使用本机完整路径。

