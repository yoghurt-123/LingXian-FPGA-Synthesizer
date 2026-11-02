> **Superseded 2026-10-27:** This is a historical App/hardware requirements note. The frozen wire definition is `MUSIC_HALL_PROTOCOL_V1.md`; the current App handoff is `APP_V1_IMPLEMENTATION_HANDOFF.md`. In particular, PLAY returns ESP transport state 2 (PLAY accepted/streaming), not FPGA execution confirmation, and hardware progress is not implemented (bit18=0). Do not use this note as the current gate.

# 音乐厅 App ↔ 硬件协议确认单（App 侧）

日期：2026-10-26  
App 基线：`iPadInstrumentApp` v0.13.0；音乐厅当前修复版 v0.14.1；目标协议对接版本 v0.14.1  
共享参考：`M0_MUSIC_PACK_FORMAT.md`、`M0_TIMED_PLAYBACK_PROTOCOL_DRAFT.md`

## 1. 当前状态

- App 侧已阅读计划和 M0 文档。
- **M0 线协议仍是草案，当前默认 FPGA 没有定时事件队列/歌曲传输，ESP 没有歌曲缓存接口。**
- App 不会按草案猜线格式后直接对当前硬件启用“播放”；不会把 `PONG`、ATT 写入确认或 BLE 连接成功当成 FPGA 演奏成功。
- App 先完成可独立推进的曲库、下载、校验、缓存、导入、播放页和传输状态机；线协议适配器等待本文件所列冻结项和测试向量。
- 当前没有正式生产曲库 URL，也没有完整 Rock Theme 3 `.fpgasong`。不能用内置样例、假 URL 或占位按钮冒充在线下载。

## 2. 需要硬件聊天框冻结/提供的项目

### 2.1 `.fpgasong` 包格式

请确认最终版本（不能只停留在 M0 draft）：

- `format_version` 最终值。
- 必需文件与可选文件清单；`report.json` 是否必需。
- 文件大小上限、条目数上限、解压总大小上限、是否允许压缩方法 8（deflate）。
- `performance.bin` header 的 magic/version/header size/event size/采样率字段/事件数/时长/CRC/song id 是否有变化。
- 事件类型 1..8、参数 id 0..6 是否冻结；同 tick 排序规则是否仍为“参数 → Note Off → 触发/鼓”。
- `manifest.capabilities_required` 的合法字符串枚举，以及与 CAPS 位的映射。
- 摘要算法是否只使用 SHA-256；包摘要覆盖整文件还是各成员摘要；大小写与十六进制格式。
- 是否允许 `cover.png`、`source.mid`、`source.musicxml`、`LICENSE`、`README` 等附加文件；是否禁止未知文件。
- 空文件、目录条目、符号链接、ZIP64、数据描述符、UTF-8 文件名、Windows 路径的接受策略。

### 2.2 生产能力与曲库

请提供：

- 正式 HTTPS `catalog.json` 地址（不是占位地址）。
- 正式完整 Rock Theme 3 `.fpgasong` 地址、文件大小、SHA-256、版本、时长。
- 曲库 schema：`song_id`、标题、作者、来源、许可、改编说明、封面 URL、所需能力、文件大小、SHA-256、版本。
- 完整 Rock Theme 3 的乐器改编说明：piano/guitar/drums 各自的来源、移除/移调/合并、力度处理、已知缺失。
- 是否允许 App 缓存完整包、封面和来源信息；缓存保留策略。
- 测试包和正式包是否同一格式；测试包是否带 `content_kind` 明示。

### 2.3 BLE 外层与能力查询

请给出最终字节级定义：

- `E2` envelope 的字节布局、最大 `LEN`、ATT MTU 下的分片策略、SEQ 回绕、CRC8 参数。
- 是否每个 chunk 都要 ACK；ACK 是独立通知还是复用 STATUS。
- 能力查询命令、响应字段、版本、实际 CAPS 位、最大包长、最大 chunk、超时。
- 定时播放、批量传输、进度上报、song-owned release 的准确位号。
- App 需要按“真实能力位 + 版本 + 包要求”判定 playable；不能硬编码 `0xFFFF` 全能力。
- 旧固件缺少哪些位时的标准错误/升级提示。

### 2.4 传输与播放状态机

请冻结并给超时值：

```text
查询能力 → BEGIN → DATA(offset...) → COMMIT → PREPARE → PLAY
         ↘ ERROR / CANCELLED / DISCONNECT
播放 → STATUS/PROGRESS → STOPPED
```

需要明确：

- BEGIN 的 session ID、总字节数、包摘要、分块大小。
- DATA 的 offset 单位、最大 chunk、期望 ACK、乱序/重复/缺口处理。
- COMMIT 校验哪些内容；成功后状态名。
- PREPARE 是否等待 FPGA `SONG_READY`；预装载完成以什么消息为准。
- PLAY 的 `start_lead_ms`/样本数、t=0 的定义、首包 lead。\n- `MusicHallTransport.play` 必须只在设备确认开始后返回；返回前不得由 App 标记播放或接收 progress。\n- `MusicHallTransport.stop` 只有在设备停止确认后才正常返回；抛错表示停止未确认，App 会继续阻止自由演奏。
- STATUS/PROGRESS 的字段、单位（samples/ms/seconds）、queued/underrun 字段。
- STOP 的 reason、是否等待 FPGA 确认、停止后释放哪些 song-owned 状态。
- 断线、App 后台、重连后的 session/队列清理规则；禁止自动重发旧队列。
- 是否支持暂停、恢复和 seek；若不支持，App 禁用且不伪装。
- 音量控制：是否有 BLE 协议级音量；如果没有，正式说明“设备本地控制”，App 不使用 iPad 音量冒充 FPGA 音量。

### 2.5 测试向量

请在 `docs/music_hall/vectors/`（或指定位置）提供二进制/十六进制和期望结果：

1. 能力查询请求/响应。
2. BEGIN/DATA/ACK/COMMIT/PREPARE/PLAY/STOP 完整成功轨迹。
3. 错误 CRC、错误 SHA、越界 offset、重复 chunk、缺块、超时。
4. 能力不足/旧固件。
5. 拔线/重连；后台/恢复；STOP 后旧 session 包被拒绝。
6. progress/underrun/ready 的真实通知序列。
7. 同一首完整 Rock Theme 3 的包摘要、事件数、时长、chunk 数、首末事件样本时间。

## 3. App 侧已确定原则

- 播放页只负责显示；音符时间来自 FPGA 会话和 progress，App 动画帧不决定音符时间。
- 不通过模拟琴键触摸或逐音 UI Timer 发送歌曲。
- 整曲提前传到 ESP；App 不自行写入 FPGA 内部。
- 下载进度与传输进度分开显示。
- 只把已下载到 App 的包标为“已缓存到 iPad”；设备缓存/预装载另外显示。
- 不在 UI 上偷偷用本地音频替代 FPGA 声音；本地预览和 FPGA 演奏必须标识清楚。
- 返回曲库是否继续播放必须显示；后台/断线/停止必须释放对应会话。
- 自由演奏与音乐厅共享时先停止歌曲并等待停止确认，再允许自由演奏发送控制。

## 4. 联调门禁

只有以下条件全部满足，App 才允许显示“FPGA 演奏”：

1. 设备返回冻结协议版本与真实能力位。
2. `timed-event-queue`、`bulk-performance-transfer`、所需乐器能力均满足。
3. 完整包通过 App 本地 ZIP/大小/路径/摘要/FPGA header/事件范围校验。
4. 传输 COMMIT 和 PREPARE 收到设备真实成功状态。
5. PLAY 后收到带当前 session/play id 的 progress，且 UI 进度由设备位置驱动。
6. STOP 收到确认或明确的会话终止状态。

否则显示具体缺失项和升级提示，不显示“播放中”。

## 5. App v0.14.1 当前实现状态

- 曲库、缓存、文件导入、ZIP/manifest/FPGS 校验、下载进度、播放页、静音舞台预览、传输状态机和设备门禁已在 App 源码实现。v0.14.1 修复 v0.14.0 的 for-in、开始未确认和停止失败问题。
- 真实 transport 仍未注入；`MusicHallTransport` 只定义了适配边界，未猜线协议。
- 当前固件仍无歌曲缓存/定时队列，正式曲库 URL 和完整 Rock Theme 3 包也未提供。
- 因此本轮不能宣称完整歌曲 FPGA 实际播放通过。

## 6. 当前 App 交付边界

- 曲库/下载/缓存/导入/校验/播放页/舞台/状态机是可独立完成的部分。
- 在实际冻结点和向量到达前，硬件播放按钮保持禁用并显示“协议未冻结/固件不支持”，不会用假数据演示成功。
- 收到冻结点后，App 只修改协议适配层、序列化/分块/回包/状态机和对应测试，不重写曲库与播放页。
