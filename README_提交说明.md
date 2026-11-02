# Submission_Final — 文件整理提交副本

整理日期：2026-11-01  
唯一工作目录：`E:\EmbeddedCompetition\GowinProjects\text4`  
本目录是**只读原工程的副本**；原 `text4`、外部 `InstrumentDisplayWeb`、默认位流和所有历史备份均未被移动、覆盖或删除。本次没有修改原工程 RTL、引脚、时序、协议或 App 逻辑；后续只在 `Submission_Final/FPGA` 副本内执行了一次独立 P/R，未改动原默认位流。

## 版本

- FPGA：当前已验收默认版本，位流 SHA256 `8982D56EA3FD2302C14539B3BE9A8598500A00A76551090DE54D6835C8CF26C8`
- ESP32：`fpga_uart_bridge` v0.5.3-start-tx；源文件 SHA256 `D0F21E1BB9108C818E1D1AA405AC2F16B64E61409EAA99782365B0125952030F`
- iPad App：`AURAL 乐器手记` v0.17.0，bundle `29`，Paper Orbit；当前 text4 源码与 v0.17 交付源码一致
- DisplayWeb：`instrument-display-web` v1.0.0；外部最终版只读复制，未修改原目录

详细哈希见 `VERSION_MANIFEST.md` 和根目录 `SHA256SUMS.txt`。

## 目录

```text
Submission_Final/
  FPGA/                  RTL、gprj、约束、构建脚本、综合网表
  ESP32/                 ESP32-C3 Arduino 源程序、说明和最终 bin
  iPadApp/               v0.17.0 .swiftpm 完整工程、Package.swift、.swiftpm、Resources
  DisplayWeb/            最终网页源码、dist、默认照片、测试和说明
  MusicPacks/            已生成的 .fpgasong 与 catalog.json
  Tools/                 music_hall 工具和 BLE 测试脚本
  Docs/                  协议、接线、版本、音乐厅和操作说明
  AcceptedBinaries/      已验收 FPGA 位流及 P/R 报告
  README_提交说明.md
  VERSION_MANIFEST.md
  SHA256SUMS.txt
```

## 使用

### FPGA

- 工程：`FPGA/audio_tone.gprj`
- 构建脚本：`FPGA/build_syn.tcl`、`FPGA/streamfix_pnr_place2.tcl`
- 默认位流：`AcceptedBinaries/FPGA/audio_tone.fs`
- P/R 报告：`AcceptedBinaries/FPGA/audio_tone_music_hall.rpt.txt`
- 报告中的绝对路径是验收时的构建来源记录，不是运行依赖。
- 本次仅复制，没有重新综合或 PnR。

### ESP32

`ESP32/fpga_uart_bridge/README.md`，板卡 `ESP32C3 Dev Module`，Arduino core `3.3.12`，FQBN `esp32:esp32:esp32c3:CDCOnBoot=cdc`。  
最终合并固件：`ESP32/fpga_uart_bridge/build/fpga_uart_bridge.ino.merged.bin`。  
构建脚本中的 Arduino 工具链路径属于本机环境配置；源文件和构建输出已改为 `$PSScriptRoot` 相对路径。

### iPad App

打开：

`iPadApp/FPGA instrument.swiftpm`

`Package.swift` 直接位于该目录，`.swiftpm/`、`Resources/` 和全部 Swift 源文件均已保留。未使用历史 `deliveries/` 或备份 App。

### DisplayWeb

进入 `DisplayWeb/` 后：

```powershell
npm install
npm run build
```

或直接双击 `start.bat` 使用已构建的 `dist/`。默认 8 张照片已同时保存在 `public/photos/` 和 `dist/photos/`，运行时不需要原外部图片目录。  
`DisplayWeb/SUBMISSION_NOTE.md` 说明网页源码 README 中仍保留的 16-band 历史描述，实际最终 FPGA 为 32-band，解析器支持最多 64 bands。

## 路径修正和说明

仅在提交副本中：

- `DisplayWeb/README.md` 的启动目录改为 `cd .\DisplayWeb`。
- `ESP32/.../build_esp.ps1` 的 `$Source`、`$Build` 改为 `$PSScriptRoot` 相对路径。
- ESP README 的文档/工具引用改为提交目录内相对路径。

仍保留的绝对路径：

- FPGA P/R 报告中的原始构建路径：验收来源证据，不是运行依赖。
- 历史文档中的备份/候选路径：历史说明，不参与运行或构建。
- ESP 构建脚本中的 Arduino 工具链路径：本机工具链配置，按 README 安装后替换。
- App 一处源码说明字符串中的历史路径：仅 UI 文字，不是文件依赖。

## 未收录

- `backups/`、失败候选、旧交付包、历史 App deliveries、重复压缩包。
- `node_modules`、工具安装包、临时缓存、大体积仿真波形和重复日志。
- 用户视频原始文件、音乐包制作源视频/音频、旧网页测试 artifacts。
- 未纳入任何未验收的 FPGA 候选修改。

## 检查结果

- FPGA gprj：74 个文件条目，副本中缺失 0。
- FPGA include/readmemh 依赖：已检查，未发现缺失。
- App：75 个文件，19,346,629 bytes；Package.swift、`.swiftpm`、6 个 Resources 齐全。
- Web：默认照片 `dist/photos/` 8 张、`public/photos/` 8 张；dist 资源齐全；无 node_modules。
- Web 静态服务检查：复制目录启动 `server.mjs`，`/`、默认照片和构建 JS 均返回 HTTP 200。
- 默认 FPGA 位流复制前后 SHA256 一致：8982…C6C8。
- FPGA 副本独立 P/R：完成，FS SHA256 8DA16…0BA8，资源与时序同验收报告，未替换默认。
- 目录总大小约 92.98 MB（374 个文件），低于 200 MB。
- 本机没有 `rar.exe`/WinRAR，7-Zip 不能生成 RAR；按要求交付整理目录，不改 ZIP 后缀冒充 RAR。
