> **Superseded 2026-10-27 by `MUSIC_HALL_PROTOCOL_V1.md`.** This file is the historical draft; BEGIN is frozen at 40 bytes, E2 reply CRC excludes E2, and PLAY is ESP streaming state rather than FPGA execution confirmation.

# 音乐厅定时播放协议草案（App / ESP / FPGA 共用）

日期：2026-10-26  
状态：**设计草案，未实现，未冻结**。现有自由演奏 `E0 EVENT KEY VALUE` 路径保持不变；M0 没有修改 ESP、App 或默认 FPGA 位流。

## 1. 分层与所有权

```text
App（导入/曲库/舞台）
  ⇅ BLE music-hall 控制帧（E2）
ESP（持久缓存、校验、分块、流控）
  ⇅ UART timed-event 帧（A5 5A ...）
FPGA（近期事件队列、音频采样定时、原有三乐器音源）
```

- App 不直接驱动 FPGA 音源；ESP 不解释音符；FPGA 不解析 JSON/MIDI/zip。
- 现有即时 4 字节 `E0` 事件仍走原路径，不等待 PONG。
- 音乐厅事件是 **song-owned**；停止时只释放歌曲持有，不释放实体键盘仍按住的音。
- 发送成功 ≠ FPGA 执行；BLE 写入/ATT 确认只证明到达 ESP。
- 能力查询只报告能力，不等于效果状态或队列状态。

## 2. 时间基准

- `Fs = 52500000 / 1088 = 48253.676470588 Hz`。
- FPGA 维护 32-bit audio sample counter；一次 `play_id` 的 `t=0` 定义为 `SONG_PLAY` 指定的未来采样。
- 所有事件时间都是相对 `t=0` 的绝对采样数，不使用 48 kHz 或毫秒近似。
- 源 score tick 到采样数的换算：

```text
sample(tick) = round(tick * 60 * 52500000 / (bpm * ppqn * 1088))
```

tempo map 分段积分；每个事件都从源 tick 绝对值计算，避免逐事件取整累计漂移。

- 建议 `SONG_PLAY` 预留 100 ms 启动 lead；这是传输/队列稳定时间，不改变乐谱时间。
- 32-bit 采样计数可覆盖约 24.7 小时，单曲不会回绕；session 在回绕/重置时递增。

## 3. App ↔ ESP（BLE）

### 3.1 保留既有自由演奏

- 现有 `E0 EVENT KEY VALUE` 四字节立即命令保持不变。
- 旧 App 不需要升级即可继续自由演奏。
- diagnostic ASCII `PING`/`FPGA_STATUS` 等保持。

### 3.2 新音乐厅控制帧

BLE 写使用独立 envelope，避免与四字节即时事件混淆：

```text
E2 TYPE SEQ LEN PAYLOAD[0..LEN-1] CRC8
```

- `E2` 为音乐厅 envelope；`SEQ` 0..255；`LEN` 0..180（且不超过协商 MTU-6）。
- `CRC8` 使用现有 poly `0x07`、init `0x00`，覆盖 `TYPE SEQ LEN PAYLOAD`。
- 每次 BLE 写入一个 envelope；分块不跨写入重组。
- 普通音符仍走 `E0`；音乐厅包传输不走逐音 PONG。

| TYPE | 方向 | 名称 | 关键字段 |
|---:|---|---|---|
| 0x01 | App→ESP | CAPS_REQ | 无 |
| 0x81 | ESP→App | CAPS_RSP | version, caps32, max_pack, max_chunk |
| 0x10 | App→ESP | BEGIN | session32, total_bytes32, pack_hash32 |
| 0x11 | App→ESP | DATA | offset32, bytes |
| 0x12 | App→ESP | COMMIT | pack_hash32 |
| 0x13 | App→ESP | PREPARE | pack_hash32 |
| 0x14 | App→ESP | PLAY | start_lead_ms16, flags |
| 0x15 | App→ESP | STOP | reason8 |
| 0x16 | App→ESP | STATUS_REQ | 无 |
| 0x96 | ESP→App | STATUS | state, session32, received32, stored32 |
| 0x97 | ESP→App | ERROR | code8, detail |

- `BEGIN` 前 App 从 `.fpgasong` 中取出 `performance.bin`；ESP 只缓存紧凑事件，不解析 score/stage。
- 建议 App 分块 128 bytes（默认 BLE 20-byte 写入则使用 16 bytes），ESP 回 **每块/每窗口** ACK；不得每个音符等待 PONG。
- `COMMIT` 后 ESP 校验总长度、SHA256、performance header/magic/CRC，失败整包丢弃。
- `PREPARE` 才允许把事件写入 FPGA 预装载；`PLAY` 才建立未来的 t=0。
- `STOP` 作废当前 session；ESP 同时通知 FPGA，并丢弃尚未发送的旧块。
- ESP 支持一个活动 session；新 session 会先停旧 session，旧 `play_id` 永远拒绝。

## 4. ESP ↔ FPGA（UART）

沿用现有帧：

```text
A5 5A TYPE SEQ LEN PAYLOAD CRC8
```

- 现有即时 `TYPE=0x10` 三字节事件保持。
- 新增音乐厅类型（草案，最终值 M1 冻结）：

| TYPE | 方向 | 名称 | PAYLOAD |
|---:|---|---|---|
| 0x30 | ESP→FPGA | SONG_BEGIN | play_id32, pack_hash32, event_count32, flags32 |
| 0x31 | ESP→FPGA | SONG_EVENT | 1–2 个 8-byte performance event |
| 0x32 | ESP→FPGA | SONG_PREPARE | play_id32, start_lead_samples32 |
| 0x33 | ESP→FPGA | SONG_PLAY | play_id32, start_lead_samples32, flags32 |
| 0x34 | ESP→FPGA | SONG_STOP | play_id32, reason8, reserved |
| 0x35 | ESP→FPGA | SONG_CREDIT_REQ | play_id32 |
| 0xB0 | FPGA→ESP | SONG_READY | play_id32, queue_free16, state8 |
| 0xB1 | FPGA→ESP | SONG_PROGRESS | play_id32, position32, queued16, underruns16 |
| 0xB2 | FPGA→ESP | SONG_ERROR | play_id32, code8, detail8 |
| 0xB3 | FPGA→ESP | SONG_CREDIT | play_id32, queue_free16 |

- `SONG_EVENT` 的 payload 是 `performance.bin` 的 8-byte 事件原样；一帧 1 或 2 个事件，`LEN=8/16`。事件绝对采样时间不变。
- UART 115200 8N1 理论 11520 B/s；当前 9-byte 即时帧约 0.78 ms。音乐厅不按理论带宽证明同步，必须预发送。
- FPGA 只保存近期事件，不解析 MIDI/JSON；队列按事件时间排序。
- ESP 每次最多在途一个受 credit 限制的事件批次；FPGA 在队列水位低时发 credit。
- **不逐音 PONG**：ESP 不等每个音符执行；只使用批量 credit、progress 和 error。
- 旧 session 的 event/progress/stop 一律丢弃。

## 5. 队列与预取

M0 技术样片实测/编译估算：

- 最大 50 ms 事件组：7 events
- 最大事件密度：12 events/s
- 最大同刻组：7 events
- 最大并发：5（piano 2 + guitar 2 + drums 3）
- 建议 FPGA 队列：**128 slots × 8 bytes = 1 KiB**，作为草案；M1 必须用真实 UART/BLE 抖动和最长突发替代。

预取建议：

- ESP 先发送前 0.5–1.0 s 事件，或直到 FPGA 队列达到高水位；不要一次发送整首。
- `SONG_PLAY` 的启动 lead 至少覆盖一次 BLE→ESP→UART 传递和队列稳定；草案 100 ms。
- 队列低于低水位时 FPGA 发 `SONG_CREDIT`；ESP 提前补充，不依赖两套时钟长期漂移。
- 若最密集段仍不够，优先增大 ESP 预取和 FPGA 队列，不能随机加速播放或把错过音符集中补奏。

## 6. 播放/停止状态机

建议状态：

```text
IDLE → TRANSFER → STORED → PREPARED → PLAYING → STOPPED/ERROR
```

- `TRANSFER`：App→ESP 分块，CRC/SHA 校验。
- `STORED`：ESP 完整包通过校验；未发送事件。
- `PREPARED`：FPGA 已接收前一批事件，但 t=0 尚未开始。
- `PLAYING`：FPGA sample counter 到达 t=0；允许 progress/credit。
- `STOPPED`：作废未来事件，释放 song-owned 音符；保留物理按住音。
- `ERROR`：坏 CRC、序号缺口、能力不兼容、欠载、session 不符；不自动补奏。

停止语义：

1. FPGA 立即丢弃所有 `time > now` 的 song 事件。
2. 释放 song 拥有的 piano/guitar song 状态；不触碰物理 USB/TTP 仍按住的同键。
3. 鼓是 one-shot，不做“未来音符”回放；已发出的尾音按既有引擎自然衰减/全局 panic 规则处理。
4. ESP 清空发送窗口，递增 session；旧包不可在重连后复活。
5. 物理自由演奏仍可继续；`ALL_OFF` 仍是独立的全局 panic，不等于歌曲停止。

## 7. 欠载、断线、重连和旧包

- **欠载**：FPGA 在应执行时刻没有事件，立即进入 `ERROR/UNDERRUN`，停止歌曲并释放 song 音符；不回放错过事件，不把后续音符压缩到下一拍。
- **BLE 断线**：ESP 停止发送并进入 STOP；按用户既定“手机失联安全停止”记录；不擅自离线继续。
- **UART 断线/超时**：FPGA 在超时后停止并释放 song-owned 音符；ESP 重连必须新建 session。
- **重连**：App 重新查询能力、重新 BEGIN；旧 session/package hash 被拒绝。
- **旧数据包**：session/play_id 与 pack_hash 必须匹配；序号缺口/过期时间窗直接丢弃并报错。
- **心跳**：音乐厅播放期间继续使用短 heartbeat；心跳不等于播放时间，也不为每个音符 ACK。

## 8. 能力位与兼容

当前 `src/ble/ble_ctrl_proto.v:137-138` 仍硬编码 `CAPS=0x0000FFFF`，这是待修问题。M1 必须返回真实能力；App 不得硬编码全能力。

建议新增音乐厅能力位（草案，最终布局 M1 冻结）：

| bit | 含义 |
|---:|---|
| 16 | timed event queue |
| 17 | bulk performance transfer |
| 18 | progress report |
| 19 | song-owned release |
| 20 | seek（M0=0，未实现） |
| 21 | real echo/delay（M0=0，未实现） |

现有 bit0..15 继续描述钢琴/鼓/吉他/和弦/表情/效果/释放等已有能力。未知能力必须拒绝，不静默降级。

## 9. 同刻事件顺序与参数

- 同一采样时刻：**参数 → Note Off → 触发/鼓**。
- 吉他：fret/palm 必须先于 pluck；和弦 select 先于 trigger。
- 钢琴：八度参数先于对应 Note On；同一时刻混合八度的可行性要由 M1 队列/音源验证，不能假定。
- 同一组事件全部入队后再提交；FPGA 目标是在同一音频采样周期执行整组。若不能，M1 必须测量实际采样差并报告。
- 扫弦的故意时间差由 score 明确写为不同 tick；播放时不得随机化。

## 10. 不改变自由演奏

- `E0` 即时事件、实体键盘、TTP、USB、BLE 自由演奏、ADC 旁路逻辑继续保留。
- 音乐厅只是新增带时间的 source；不得用模拟触摸/模拟 UI 点击来播放。
- 实体输入与歌曲同键时，释放 gate 必须保留物理所有权；停止不能误释放物理音。

## 11. M1 必须验证

- 真实 BLE MTU、分块 ACK、ESP flash 分区和坏包。
- UART 队列水位、credit、最密集段不丢事件、抖动/延迟实测。
- 同组提交的采样级同步、参数先后和钢琴跨八度/同键释放。
- 欠载、断线、重连、停止、旧包、后台切换。
- 吉他共享效果和鼓同刻力度的边界。
- 真实混音峰值/削波；不以非零 PCM 代替音色/同步验收。
