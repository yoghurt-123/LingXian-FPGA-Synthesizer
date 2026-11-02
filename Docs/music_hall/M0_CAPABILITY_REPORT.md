# M0 三乐器能力核验报告

日期：2026-10-26  
范围：只核验 RTL、协议和当前三端源码；未修改默认位流，未烧录，未跑整机 PnR。

## 1. 基线

- 主工程：`E:\EmbeddedCompetition\GowinProjects\text4`
- 默认位流：`impl/pnr/audio_tone.fs`
- SHA256：`A92125809FEF3AE6A910CD51A92D3AFC4856A3422D55B977168F6E51199B7C70`
- 默认资源：CLS 27959/29952、Logic 48992/59904、FF 24188/60780、BSRAM 95/118、DSP 82/118；setup +0.011 ns。
- ESP：`esp32/fpga_uart_bridge`，v0.4，源码 SHA256 `B0DE60B2…`。
- App 源码：`iPadInstrumentApp/FPGA instrument.swiftpm/FPGA instrument.swiftpm`，`AppInfo.swift` 当前写 `0.13.0`；默认交付目录仍是 v0.11.0。M0 未修改 App。
- 音频采样率：`52500000 / 1088 = 48253.676470588 Hz`
  - `src/output/pt8211_tx.v:3,7,21-23`
  - `src/top.v` 的 `audio_drive #(.BCK_HALF_DIV(17))`

## 2. 能力总表

| 项目 | 当前实际能力 | 关键限制 | 源码位置 |
|---|---|---|---|
| 钢琴音高 | 16 个固定 NOTE_SEL 键，基准 C4 到 D#5 的连续 16 半音窗口；支持低/原/高三个八度，等价范围 C3..D#6 | 只有 16 个键类；同一键不能同时保留两个八度 | `src/ble/ble_audio_ctrl.v:145-161,220-225`；`docs/BLE_CONTROL_PROTOCOL.md` 钢琴表；`src/top.v:181-211,573-591` |
| 钢琴复音 | 4 组 × 每组 4 个共享核心声部 = 16 个 NOTE_SEL 声部 | 每个 NOTE_SEL 只能一个活动声部；同键重触发会覆盖/受释放门控 | `src/top.v:526,577,584,591`；`src/tone/piano_modal_group4_shared.v`；`src/tone/piano_modal_shared_core.v:19-33` |
| 钢琴释放 | BLE Note Off 可按 BLE 持有源释放；外部释放渐长约 1024 采样 | 实体 USB/TTP 同键按住时，BLE 释放被抑制；释放期间同键新触发被忽略，约 21 ms | `src/ble/ble_audio_ctrl.v:153-161`；`src/tone/piano_modal_shared_core.v:152,274-290` |
| 钢琴最长音 | 声部自然年龄上限 `NOTE_SAMPLES=78654`，约 1.63 s | 不是无限持音；音符长于自然尾音后仍会结束 | `src/tone/piano_modal_shared_core.v:19,97-100` |
| 钢琴力度 | BLE/USB 4-bit，1..15；输出增益约 `(v+1)/16`，15=1.0 | 13/14 等档不是独立校准；与吉他和鼓同数值不等于等响 | `src/top.v:487-518,545-558`；`src/ble/ble_audio_ctrl.v:149` |
| 钢琴八度参数 | 全局 2-bit：0=低，1=原，2=高；触发时锁存到声部 | 不能在同一个 NOTE_SEL 上同时保留两个八度；同一时刻混合八度的参数必须先于对应触发 | `src/ble/ble_audio_ctrl.v:220-225`；`src/tone/piano_modal_shared_core.v:198-228` |
| 吉他弦 | 6 个请求键：E2/A2/D3/G3/B3/E4 | 低 E2 独立声部；其余 A2..E4 共用 3 个动态池槽 | `src/ble/ble_audio_ctrl.v:170-175`；`src/interaction/guitar_ctrl.v` 的 `pool_note[0:2]`；`src/top.v:292-325,443-451` |
| 吉他品位/音高 | KEY 0..12 作为半音移调/品位偏移；每根弦基准音高 + 偏移 | 不是逐弦独立品位表；全局 fret 锁存于请求；同一时刻不同品位需顺序参数化 | `src/ble/ble_audio_ctrl.v:176-178`；`src/interaction/pitch_bend_ctrl.v:110-118,358-405`；`src/tone/guitar_voice.v:29-30` |
| 吉他复音 | 实际拨弦池：E2 独立 + 3 个动态池槽，最多约 4 个同时手动声部 | 6 根弦不等于 6 个独立声部；满池替换最早声部，替换前有短淡出 | `src/interaction/guitar_ctrl.v` 的 `N_A2..N_E4`、`pool_note[0:2]`；`src/tone/guitar_voice.v` 六槽扫描 |
| 吉他和弦 | 仅 4 个预设：U/C、I/G、O/Dm、P/Am；每次最多 3 音 | 不是任意六弦和弦/指法；已提交和弦是短一发声型，不是新的持续音源 | `src/ble/ble_audio_ctrl.v:182-194`；`src/interaction/guitar_chord_engine.v:81-86`；`docs/BLE_CONTROL_PROTOCOL.md` |
| 吉他力度/闷音 | 每次拨弦 1..15；palm 状态随请求锁存 | palm 是近似闷音行为；和弦只带一个速度；全局制音会清请求 | `src/ble/ble_audio_ctrl.v:170-181`；`src/interaction/guitar_ctrl.v`；`src/tone/guitar_voice.v:28-31,55-65` |
| 吉他音符长度 | 自然衰减约 4 s；无逐音 Note Off | 曲谱的 guitar duration 只能记录意图，不能逐音释放；停止/制音是全局语义 | `src/tone/guitar_voice.v:4,8`；当前协议只有 pluck，无 guitar note-off |
| 吉他表情 | Bend 左/中/右（±2 半音端点）、5 Hz ±50 cent 颤音、glide、20..300 ms slide time | 只作用于最近手动主奏；不是逐弦独立表情；USB 表情键优先于 BLE | `src/ble/ble_audio_ctrl.v:195-207`；`docs/BLE_CONTROL_PROTOCOL.md` 第 5 节；`src/interaction/pitch_bend_ctrl.v` |
| 吉他效果 | Overdrive/Reverb 目标为 0/1，共享全局状态 | 不能逐音自动化；切换需要静音/稳定等待，不能按帧随意切换 | `src/ble/ble_audio_ctrl.v:208-219`；`src/interaction/guitar_ctrl.v` 的 `FX_SETTLE` |
| 鼓 ID | 9 个 one-shot：kick、snare、closed hat、open hat、ride、crash、tom high、tom low、tom mid | 只有 one-shot，无音长/Note Off；同时鼓组的力度由单一锁存值决定 | `src/ble/ble_audio_ctrl.v:164-168`；`src/top.v:630-690`；`docs/BLE_CONTROL_PROTOCOL.md` 第 6 节 |
| 鼓力度 | 1..15；每次触发锁存 | 同一 sample 的多个鼓共享最后锁存力度，不能各自独立等响 | `src/top.v:637-657`；`src/ble/ble_audio_ctrl.v:167` |
| 开/闭镲 | closed hat 置 choke；open hat 释放 choke；重触发 open 可释放 | 不是通用鼓 choke，只针对 hat 路径 | `src/top.v:683-690` |
| 鼓同时性 | 9-bit 触发向量可表达同时鼓组；各引擎有独立声部/共享资源 | 峰值并发和尾音重叠仍需实际压力测试；不能仅凭触发位宣称 9 个同时音已验收 | `src/top.v:630-690`；`src/drum/drum_synth3.v`；`src/drum/six/six_drum_synth.v` |
| A2/A3 | ADC 仅预留归一化目标/有效状态 | 无真实过载强度或回声/延时；重复弱音不等于 Delay | `src/adc/adc_param_bridge.v`；`docs/DEFAULT_VERSION.md` |

## 3. 协议现状

- App 自由演奏仍使用 4 字节 `E0 EVENT KEY VALUE`；ESP 增加 UART 帧。
- UART 帧：`A5 5A TYPE SEQ LEN PAYLOAD CRC8`，事件帧 `TYPE=0x10`、`LEN=3`。
  - `src/ble/ble_ctrl_proto.v:16,110`
- **没有时间戳**，没有批量乐谱传输，FPGA 只接收即时事件。
- 当前能力回复仍硬编码 `CAPS=0x0000FFFF`：
  - `src/ble/ble_ctrl_proto.v:129-148`
  - 这违反“不得固定返回全能力掩码”的约束，M1 必须改为真实能力位。
- 当前 BLE 事件源的释放/所有权：
  - `src/ble/ble_audio_ctrl.v` 的 `release_all_ble` 只释放 BLE 持有；物理同键仍保护。
  - 音乐厅需要新增“song owner”，不能把实体键盘仍在按住的音当成歌曲音释放。
- 现有队列 `ble_event_fifo` 仅 16 项、24-bit/项：
  - `src/top.v` 的 `ble_event_fifo #(.WIDTH(24), .ADDR_BITS(4))`
  - 不能直接沿用为整首音乐队列；M1 需要独立的定时事件队列。

## 4. 对 M0 编配的直接结论

1. 钢琴可以承担旋律与双音/少量和声，但必须使用 16 键窗口；同键跨八度不能重叠，同键快速重触发至少留约 21 ms 释放余量。当前技术样片只使用两个钢琴声部。
2. 吉他不能直接按“六弦独立复音”编写；实际应把 E2 低音和最多 3 个动态池声部视为 4 声部上限。四音以上吉他织体、任意六弦指法和逐音长释放必须改写或标记不支持。
3. 鼓的 9 个 ID 足够首曲的节奏骨架，但同一采样时刻不同鼓不能独立设力度；需要把同组力度统一，或在时间上稍微错开并明确这是编配变化。
4. 原曲贝斯不能默认由当前钢琴覆盖：钢琴最低约 C3，吉他最低 E2；低音线可能低于 E2 或需要跨弦/移调。M1 需按授权乐谱逐音判定，不能静默删音。
5. 真正的 Echo/Delay 未实现；A3 只是预留 ADC 参数。音乐包不得把重复弱触发标为“回声”。

## 5. 未完成

- 本报告没有对 9 鼓同时/长并发、真实混音峰值和整曲长 PCM 做上板验证。
- 没有把当前 App v0.13.0 源码与默认 v0.11.0 交付强行对齐；M0 不修改 App。
- 没有授权乐谱，因此没有生成《Let It Be》的音符数据或准确转录。
