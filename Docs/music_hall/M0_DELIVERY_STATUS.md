# 音乐厅 M0 交付状态

日期：2026-10-26  
基线：默认 `impl/pnr/audio_tone.fs`，SHA256 `A92125809FEF3AE6A910CD51A92D3AFC4856A3422D55B977168F6E51199B7C70`。  
本阶段没有改默认位流、没有烧录、没有跑整机 PnR、没有改 ESP/App。

## 1. 已完成

| 交付 | 状态 | 文件 |
|---|---|---|
| 三乐器 RTL 能力核验 | 完成 | `docs/music_hall/M0_CAPABILITY_REPORT.md` |
| 《Let It Be》来源/版本/授权审查 | 完成，结论为缺授权乐谱 | `docs/music_hall/M0_LET_IT_BE_SOURCE_REVIEW.md` |
| 8 小节三乐器改编结构稿 | 完成分工/结构，未写受版权保护音符 | `docs/music_hall/M0_ARRANGEMENT_PLAN.md` |
| `.fpgasong`/score/performance 草案 | 完成 | `docs/music_hall/M0_MUSIC_PACK_FORMAT.md`、`music_packs/schemas/` |
| 三端定时播放协议草案 | 完成设计，未实现 | `docs/music_hall/M0_TIMED_PLAYBACK_PROTOCOL_DRAFT.md` |
| 转换/校验工具 | 完成原型并通过样例 | `tools/music_hall/` |
| 原创技术样片包 | 完成并通过校验 | `music_packs/m0_technical_demo/`、`music_packs/m0_technical_demo.fpgasong` |
| 能力/密度/并发/队列报告 | 完成技术样片版本 | `music_packs/m0_technical_demo/report.json` |

## 2. 技术样片结果

- 原创 8 小节，不是《Let It Be》；
- 72 BPM、4/4、PPQN 480；
- 200 个 performance events；
- 26.667 s；
- 最大事件密度 12 events/s；
- 最密 50 ms 组 7 events；
- 最大同刻组 7 events；
- 最大并发 piano 2 / guitar 2 / drums 3，总计 5；
- performance 1,632 bytes；
- 128 个 8-byte FPGA 队列槽为草案估算；
- 编译/校验错误 0；唯一警告是吉他 duration 仅编配意图，硬件无逐音 Note Off；
- 包内明确 `content_kind=technical_demo_not_let_it_be`；包 SHA256 `0B8A258EA6461918A3B98FC12884101F3C651506B22D6A8D578D84830B3C44E6`，performance SHA256 `C35B8B13184BA99EC1F5EC51742A53095746975B4BEEB621E808DE202D9A9843`。

## 3. 没有完成/不能宣称

1. **《Let It Be》没有音符数据、没有 performance.bin、没有准确 8 小节试听。** 缺授权 MusicXML/MIDI/核对乐谱；没有从官方音频或商品预览转录音符。
2. **没有改 FPGA 定时播放**：当前固件没有 `FPGS` 解析、近期事件队列、song-owned release 或 sample 调度器。
3. **没有改 ESP**：没有音乐包分区、BLE 传输、SHA 校验、滚动缓存或 credit 流控。
4. **没有改 App**：没有音乐厅导入/传输/播放舞台；App 源码当前为 v0.13.0，默认交付为 v0.11.0，M0 不强行合并。
5. **没有真实 Echo/Delay**：A2/A3 仍只是 ADC 预留参数。
6. 没有整机 PnR、没有硬件烧录、没有长 PCM/三乐器并发/混音峰值上板验收。
7. 当前固件能力查询仍硬编码 `CAPS=0x0000FFFF`，列入 M1 必修项。

## 4. 仅为设计

- BLE `E2` 音乐厅 envelope、ESP 分块/窗口 ACK、UART `SONG_*` 类型和能力位；
- FPGA 128-slot 事件队列和 100 ms 启动 lead；
- 定时事件同组提交、song owner 释放、欠载/断线/旧包规则；
- ESP flash 缓存布局和 App 音乐厅页面。

## 5. 下一阶段改动点

### FPGA

- 新增独立 `music_event_queue`/`music_scheduler`，不沿用 16 项 BLE 即时 FIFO。
- 为钢琴/吉他/鼓增加 song-owned 状态与释放门控；停止歌曲不释放物理同键。
- 实现真实 capability 位与 `SONG_READY/PROGRESS/CREDIT/ERROR` 回复。
- 以 audio sample counter 为唯一播放时钟；实测同组提交和队列水位。
- 在独立候选接入，M2 才做整机 PnR；默认 A921 保持不动。

### ESP

- 选择并实测 flash 分区；实现音乐包缓存、SHA256、分块窗口 ACK、断点/重传。
- 实现 UART `SONG_*` 发送、credit 和欠载处理；日志保持非阻塞。
- 不把 ATT 写入确认当作 FPGA 执行。

### App

- 在 App v0.13.0 基础上实现 Files 导入、manifest/能力校验、传输进度、停止/重连。
- 舞台动画用本地播放时钟并由 FPGA progress 校正，不能用 BLE 到达时间驱动音符。
- 不在 App 内自定义另一套事件编号；以本协议和 `BLE_CONTROL_PROTOCOL.md` 为源。

### 曲目

- 取得有授权的《Let It Be》MusicXML/MIDI 或核对乐谱；
- 先录连续 8 小节，检查钢琴同键/八度、吉他 4 声部池、鼓同刻力度和贝斯音域；
- 再扩到 60–90 秒，逐项报告移调/换八度/删音。

## 6. 文件索引

- 能力：`docs/music_hall/M0_CAPABILITY_REPORT.md`
- 曲目来源：`docs/music_hall/M0_LET_IT_BE_SOURCE_REVIEW.md`
- 编配结构：`docs/music_hall/M0_ARRANGEMENT_PLAN.md`
- 包格式：`docs/music_hall/M0_MUSIC_PACK_FORMAT.md`
- 协议：`docs/music_hall/M0_TIMED_PLAYBACK_PROTOCOL_DRAFT.md`
- 工具：`tools/music_hall/README.md`
- 样例：`music_packs/m0_technical_demo.fpgasong`
- 原始技术样片目录：`music_packs/m0_technical_demo/`
