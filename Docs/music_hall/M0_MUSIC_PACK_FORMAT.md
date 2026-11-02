> **Superseded 2026-10-27:** Historical M0 draft. The frozen package format is 1.0 and the wire definition is `MUSIC_HALL_PROTOCOL_V1.md`; BEGIN is 40 bytes and E2 reply CRC excludes E2.

# M0 `.fpgasong` / score / performance 格式草案

日期：2026-10-26  
状态：**草稿，未冻结**；当前 FPGA 固件没有定时播放队列和批量传输能力。包内数据只用于 M0 工具验证，不能直接交给 ESP/FPGA 播放。

## 1. 包结构

`.fpgasong` 是 ZIP 容器，解包后至少包含：

```text
manifest.json
score.json
performance.bin
stage.json
```

可选：

```text
cover.png
source.mid
source.musicxml
```

`manifest.json` 记录格式版本、版权/来源、目标能力、文件大小和 SHA256。摘要只说明完整性，不证明来源或授权。导入时必须限制总解压大小、单文件大小和文件数量，拒绝路径穿越，不执行包内脚本。

## 2. `score.json`

保留完整音乐语义，采用整数 tick 和 PPQN；不把 MIDI 的浮点秒直接写入。

```json
{
  "schema_version": "0.1",
  "song_id": "stable-string",
  "title": "display title",
  "composer": "author",
  "rights": "rights/source statement",
  "content_kind": "technical_demo_not_let_it_be",
  "ppqn": 480,
  "time_signature": { "numerator": 4, "denominator": 4 },
  "tempo_map": [{ "tick": 0, "bpm": 72 }],
  "duration_ticks": 15360,
  "tracks": [
    {
      "id": "piano",
      "instrument": "piano",
      "notes": [
        { "start_tick": 0, "duration_ticks": 480, "midi": 60, "velocity": 96 }
      ]
    },
    {
      "id": "guitar",
      "instrument": "guitar",
      "notes": [
        {
          "start_tick": 0,
          "duration_ticks": 480,
          "string": 0,
          "fret": 0,
          "velocity": 96,
          "palm": false,
          "technique": "pluck"
        }
      ]
    },
    {
      "id": "drums",
      "instrument": "drums",
      "hits": [
        { "tick": 0, "drum": 0, "velocity": 96 }
      ]
    }
  ],
  "sections": [
    { "start_bar": 1, "end_bar": 2, "title": "section" }
  ]
}
```

### 钢琴

- `midi` 按标准 MIDI 音高记录；编译器映射到 16 个 NOTE_SEL 键和八度 0/1/2。
- 当前可映射范围约为 C3..D#6 的 16 键窗口；超出即错误，不静默移调。
- `duration_ticks` 产生 Note Off；同键重叠错误，同键快速重触发给出释放余量警告。
- 八度参数是全局 2-bit，必须在对应 Note On 前；同一采样时刻混合八度需要协议/固件确认。

### 吉他

- `string` 0..5 = E2/A2/D3/G3/B3/E4；`fret` 0..12 是半音偏移。
- 当前硬件没有逐音 Note Off；`duration_ticks` 只保留编配意图，performance 只产生 pluck，报告会列出限制。
- 动态池上限按 E2 + 3 个池声部检查；超过即错误。
- 扫弦的微小时差应写入 `start_tick`，播放时不随机改变。
- 和弦预设只能使用当前四个预设；任意弦/品组合必须在输入前转成单音拨弦或报不支持。

### 鼓

- `drum` 0..8；无 duration。
- 同一采样时刻多个鼓共享力度锁存；不同力度应改时间/统一力度，并写入报告。
- 开/闭镲 choke 作为编配约束，不把重复弱音当 echo。

## 3. `performance.bin`

`performance.bin` 是**目标硬件定时事件格式草案**。当前固件不支持；M1 需冻结协议后再实现。

### Header（32 bytes，little-endian）

| 偏移 | 长度 | 字段 |
|---:|---:|---|
| 0 | 4 | magic `FPGS` |
| 4 | 1 | version = 1 |
| 5 | 1 | header size = 32 |
| 6 | 1 | event size = 8 |
| 7 | 1 | flags = 0 |
| 8 | 4 | sample rate numerator = 52500000 |
| 12 | 2 | sample rate denominator = 1088 |
| 14 | 2 | reserved = 0 |
| 16 | 4 | event count |
| 20 | 4 | duration in audio samples |
| 24 | 4 | CRC32 of event records |
| 28 | 4 | song id FNV32 |

### Event（8 bytes）

| 偏移 | 长度 | 字段 |
|---:|---:|---|
| 0 | 4 | absolute time in audio samples from play start |
| 4 | 1 | type |
| 5 | 1 | a |
| 6 | 1 | b |
| 7 | 1 | flags |

Type:

| 值 | 事件 | a | b | flags |
|---:|---|---|---|---|
| 1 | piano note on | key 0..15 | velocity 1..15 | 0 |
| 2 | piano note off | key 0..15 | 0 | 0 |
| 3 | drum one-shot | drum 0..8 | velocity 1..15 | 0 |
| 4 | guitar pluck | string 0..5 | velocity 1..15 | fret bits0..3, palm bit4 |
| 5 | guitar chord | preset 0..3 | velocity 1..15 | palm bit4 |
| 6 | parameter | parameter id | value | 0 |
| 7 | release all song notes | 0 | 0 | 0 |
| 8 | all-off/panic | 0 | 0 | 0 |

Parameter ids（草案）：0 piano octave，1 guitar fret，2 guitar palm，3 overdrive，4 reverb，5 BLE damping，6 pedal delay。

- 时间使用**绝对采样数**，不是增量 tick/毫秒；避免累计取整漂移。
- 同一采样时刻的 flags bit5=group start、bit6=group end；组内顺序固定为参数 → Note Off → 触发/鼓。
- 不等待逐音 PONG；FPGA 只回进度、credit 或错误。
- `performance.bin` 的 CRC 只验证事件区；包 manifest 再验证文件 SHA256。

## 4. 时间转换

目标播放时钟：

```text
Fs = 52500000 / 1088 = 48253.676470588 Hz
sample(tick) = round(tick * 60 * 52500000 / (bpm * ppqn * 1088))
```

- 每个事件的采样时间都从源 tick 绝对计算；tempo map 分段积分，不按 48 kHz 近似。
- 当前技术样片：72 BPM、PPQN 480、8 小节 = 15360 ticks，编译为 1,286,765 samples，约 26.667 s。
- 同一时刻事件不随播放随机抖动；扫弦有意时间差必须写进 score。

## 5. `manifest.json`

至少包含：

```json
{
  "format": "fpgasong",
  "format_version": "0.1",
  "song_id": "stable-string",
  "title": "...",
  "composer": "...",
  "rights": "...",
  "content_kind": "technical_demo_not_let_it_be",
  "target": {
    "sample_rate_num": 52500000,
    "sample_rate_den": 1088,
    "ppqn": 480,
    "firmware_support": "draft-not-supported-by-current-firmware"
  },
  "capabilities_required": [
    "piano", "guitar-pluck", "drums", "timed-event-queue", "bulk-song-transfer"
  ],
  "files": {
    "score.json": { "bytes": 0, "sha256": "..." }
  },
  "limitations": []
}
```

- 未知能力或损坏文件必须拒绝，不能静默删音。
- 包可以带 `source.mid`/`source.musicxml`，但必须单独记录来源和授权；M0 样片没有第三方源文件。

## 6. 工具原型与样例

工具：

- `tools/music_hall/generate_demo_score.js`：生成原创技术样片。
- `tools/music_hall/compile_song.js`：score → performance + report。
- `tools/music_hall/build_pack.js` / `build_pack.ps1`：生成 manifest 并打 ZIP。
- `tools/music_hall/validate_pack.js`：校验 manifest、SHA256、performance 和可重编译一致性。

样例：

- `music_packs/m0_technical_demo/`
- `music_packs/m0_technical_demo.fpgasong`
- 内容明确为**原创技术样片，不是《Let It Be》**。

样片编译结果：

- events：200
- duration：26.667 s
- 最密 50 ms：7 events
- 最大并发：piano 2、guitar 2、drums 3，总计 5
- performance：1,632 bytes
- 最密同刻组：7 events
- 建议 FPGA 队列：128 slots × 8 bytes；M1 必须用实测替代这个估算
- 错误：0
- 警告：1（吉他 duration 没有逐音 Note Off）

## 7. 尚未完成

- 协议未冻结；当前固件没有 `FPGS` 解析器、定时队列或 song-owner 释放。
- 尚未实现 ESP 分区/滚动缓存和 App 导入。
- 没有授权《Let It Be》score；没有为其生成 performance。
- 真实 Echo/Delay 未实现，A2/A3 仍只是 ADC 预留；不能用重复弱音冒充。
