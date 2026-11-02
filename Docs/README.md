# 主工程文档入口

## 音乐厅合奏计划（2026-10-26）

- [音乐包、ESP 缓存、FPGA 定时合奏与 App 音乐厅实施计划](planning/MUSIC_HALL_IMPLEMENTATION_PLAN_20261026.md)：设计方向、分阶段交付和验收要求；计划不代表功能已实现。

## 架子鼓开发最新入口（2026-10-19）

text5 已核对为未加鼓 v7 基线，冻结产品源码与构建产物；以下为本地交接文档，不代表已实现，不推送 GitHub。下文保留的 text4 路径是历史说明。

- [冻结基线与整个架子鼓交接](planning/DRUM_STABLE_BASELINE_HANDOFF.md)
- [对应算法与流水实现](research/DRUM_PIPELINED_IMPLEMENTATION.md)

主工程：`E:\EmbeddedCompetition\GowinProjects\text4`。钢琴、吉他、USB键盘的设计和方案统一在本目录维护。

## 优先阅读

| 文档 | 用途 |
|---|---|
| [USB集成与当前进度](USB_INTEGRATION.md) | 已实现功能、验证记录、位流和上板说明；查看现状先读这一份 |
| [键位映射总方案](planning/KEYMAP_PROPOSAL.md) | 统一操作、钢琴、吉他、品位与表情键位；方案不等于全部已实现 |
| [赛题对照与路线图](planning/FEATURE_ROADMAP.md) | 要求、差距、验收依据；历史进度项需结合最新集成记录 |
| [未完成功能研究与设计](research/EXPRESSION_DESIGN.md) | 前人资料、制音/力度/音量/滑音等设计、实施顺序与验证边界 |
| [Music Hall M0](music_hall/README.md) | 三乐器能力核验、技术样片、包格式和定时播放协议草案 |
| [表达控制数值验证结果](research/EXPRESSION_MODEL_RESULTS.json) | 仅算法模型结果，不代表RTL或上板通过 |
| [数值验证脚本](research/validate_expression_models.py) | 重现模型检查；仍从主工程参数文件读取 |

## USB硬件与连接资料

- [TX35键盘使用阅读](usb/KEYBOARD_GUIDE.md)
- [电脑端USB检测记录](TX35_USB_DETECTION.md) / [原始数据](tx35_usb_detection_20261014.json)
- [独立USB工程测试说明](usb/USB_KEYBOARD_USAGE.md)
- [独立USB工程KEY0](usb/KEY0_USAGE.md)、[KEY1](usb/KEY1_USAGE.md)、[VOFA](usb/VOFA使用说明.md)：属于独立测试工程，不是当前主工程键位。
- [USB底层源码索引](../src/usb/README.md)：随源码保留。

## 主工程早期参考

- [源码布局](reference/SOURCE_LAYOUT.md)
- [音频输出](reference/AUDIO_OUTPUT.md)
- [单次发声](reference/ONE_SHOT.md)
- [KEY0旧说明](reference/KEY0_USAGE.md)
- [VOFA旧说明](reference/VOFA使用说明.md)

这些文件保留历史信息，不能用其旧功能描述覆盖当前USB集成记录。试听WAV、仿真结果、研究脚本仍在原位置，不移动其依赖文件。

## 维护规则

1. 设计与方案只在本目录的正文文件更新；旧位置仅保留跳转，避免出现两份不同正文。
2. 方案、已实现、仿真通过、时序通过、上板验收分开记录；不因搬迁文档改变任何功能状态。
3. 键位和功能方案仅本地保存，本次未推送GitHub。
4. 主工程和USB工程根README保留项目入口；源码旁README、备份文档及第三方资料维持原位置。
5. 新设计文档使用英文文件名、中文内容；新增文档请同步此目录。

## 用户约定（2026-10-16）

以后新增或更新的设计方案、修正方案统一保存在主工程 text4/docs 内，并同步本目录索引，不在USB独立工程或项目根目录另建方案正文。设计研究放 research，键位与路线规划放 planning，修正方案放 fixes（需要时创建）。修正方案应写明问题现象、原因或待验证假设、修改范围、验证结果及遗留项；不要把拟议修复写成已验证完成。文件名使用英文，内容使用中文。

## 当前实施交接

- [统一操作：总音量实施规格（F8/F9修订版）](planning/UNIFIED_CONTROLS_VOLUME_HANDOFF.md)：F8减/F9加、17档、1024采样平滑；实现与验证状态见 USB_INTEGRATION.md。
- [统一操作：力度实施规格（修订版）](planning/UNIFIED_CONTROLS_VELOCITY_HANDOFF.md)：已完成并上板验收。
- [统一操作：Esc与钢琴Space实施规格](planning/UNIFIED_CONTROLS_STOP_HANDOFF.md)：已完成并上板验收。
- [修正记录：力度轮](fixes/20261017_velocity_round_fixes.md)
- [修正记录：总音量轮](fixes/20261017_volume_round_fixes.md)
- [修正记录：八度轮](fixes/20261017_octave_round_fixes.md)
- [修正记录：吉他局部时序优化](fixes/20261017_timing_optimization.md)
- [修正记录：左右弯音轮](fixes/20261018_bend_round_fixes.md)
- [修正记录：钢琴幅度RAM化](fixes/20261018_piano_amplitude_ram_fixes.md)
- [修正记录：V颤音](fixes/20261018_vibrato_round_fixes.md)
- [修正记录：B滑音/时间/最小品位](fixes/20261018_slide_fret_fixes.md)
- [修复记录：上板与离线听感差异定位](fixes/20261018_backend_alignment_fixes.md)
- [修复记录：B/V状态灯与左Ctrl闷音（时序阻断）](fixes/20261018_bv_ctrl_fixes.md)
- [修复记录：池槽索引独立修复与B/C单独接回](fixes/20261018_pool_index_fix.md)
- [修复记录：颤音±50/Ctrl/踏板/和弦（D隔离）](fixes/20261018_vib50_ctrl_de_fixes.md)
- 表情试听WAV（吉他合成输出，非最终DAC链路）：[docs/expression_preview](expression_preview/README.md)（含文件顺序、参数、采样率与数值核验）
- [修正记录：Esc/Space轮](fixes/20261016_stop_round_fixes.md)

- [统一操作：力度预设与Shift重音实施规格](planning/UNIFIED_CONTROLS_VELOCITY_HANDOFF.md)：Esc/钢琴Space用户已验收后的下一批，含元数据锁存、音源增益复用及回归测试。

- 力度方案修订：右侧小键盘1/2/3按住即时生效，全松默认75%；[实现与测试规则](planning/UNIFIED_CONTROLS_VELOCITY_HANDOFF.md)。

- [统一操作：总音量实施规格](planning/UNIFIED_CONTROLS_VOLUME_HANDOFF.md)：2026-10-17力度用户已验收后的下一批，F8/F9、有限时长平滑、与Esc/VOFA配合。

- [统一操作：Z/X钢琴八度实施规格](planning/UNIFIED_CONTROLS_OCTAVE_HANDOFF.md)：总音量候选版后的下一批；总音量上板状态仍待用户反馈。
- [连续音高表情：顺序修正与分批交接](planning/EXPRESSION_CONTROLS_HANDOFF.md)：弯音→颤音→滑音/时间；完整品位/和弦不插队。
- [左/右弯音实施设计](planning/PITCH_BEND_DESIGN.md)：已实施（见 [修正记录](fixes/20261018_bend_round_fixes.md)），仿真/时序通过、**上板待验收**。
- 八度轮状态（2026-10-17）：精简集成仿真通过、时序通过，**上板待测**；实现机制与时序返工见 [修正记录：八度轮](fixes/20261017_octave_round_fixes.md)。总音量（F8/F9）仍**上板待测**，其候选位流备份保留。
- 局部时序优化（2026-10-17）：吉他衰减码两级流水，等价性测试逐位一致、短回归通过；Fmax 52.632→52.957MHz。
- 左右弯音（2026-10-18）：数值/单元/单声部/主工程短回归通过；后期修正记录见 [弯音轮](fixes/20261018_bend_round_fixes.md)。
- 钢琴幅度RAM化（Stage1，2026-10-18）：逐样本等价、CLS 92.8%→86%、Fmax 52.513→52.685MHz；位流01:46:40（02B88FAC…），详见 [修正记录](fixes/20261018_piano_amplitude_ram_fixes.md)。
- V颤音（Stage2，2026-10-18）：单元通过、构建通过（53.163MHz）；主工程集成并入Stage3回归；位流02:45:09（559DB484…），详见 [修正记录](fixes/20261018_vibrato_round_fixes.md)。
- B滑音/时间/最小品位（Stage3，2026-10-18）：单元/等价/主工程短回归全部通过；构建53.844MHz（slack +0.476ns，CLS 87%，BSRAM 73）；最新候选 `stage3_slide_fret_20261018_033855`。所有新功能**上板待验收**。八度/总量仍上板待验收。

- [八度后推进：局部时序优化与后续品位](planning/POST_OCTAVE_OPTIMIZATION_HANDOFF.md)：保护候选基线、定位吉他关键路径、分层验证；Z/X与F8/F9仍待上板验收。

- [连续音高表情详细交接（顺序修正）](planning/EXPRESSION_CONTROLS_HANDOFF.md)：局部优化后依次弯音、颤音、滑音及时间；覆盖此前先做完整品位的安排。

- [钢琴声部无损资源优化研究](research/PIANO_RESOURCE_OPTIMIZATION.md)：官方RAM限制、幅度/相位RAM化与分组共享方案；仅设计研究，未改RTL。

- [夜间连续推进任务书（2026-10-18授权）](planning/OVERNIGHT_ADVANCEMENT_HANDOFF.md)：钢琴幅度RAM化 → V颤音 → B滑音/时间与最小品位；分阶段自主推进、保存通过候选、硬件待验收。

- [钢琴幅度RAM独立验收](fixes/20261018_piano_ram_independent_acceptance.md)：源码/网表/原始报告核查及新增扫描边界短测通过，PCM未发现差异；硬件听感待用户确认。

- [剩余键盘映射自主交接](planning/REMAINING_KEYMAP_HANDOFF.md)：当前WAV/特殊音完善完成后执行；状态提示、Ctrl闷音、QWER/JKL、F7可选钢琴阻尼与Ctrl踏板，分阶段自主验证。

- [表情试听对齐与V提示快速完善](planning/EXPRESSION_POLISH_FAST_HANDOFF.md)：复用原PCM只跑后级链路，加入实际颤音生效提示，局部验证后必要一轮构建。

- [音效完善与剩余映射统一自主执行规格](planning/POLISH_AND_KEYMAP_MASTER_HANDOFF.md)：最新主入口，含后级回放对比算法、B/V提示、Ctrl闷音、和弦FIFO/调度、可选踏板及局部验证策略。

- [最新修订：取消动态灯效并继续映射](planning/RESUME_WITHOUT_DYNAMIC_LED_HANDOFF.md)：覆盖旧B/V/F7灯效门槛；±50音分颤音候选 → Ctrl → 和弦扫弦 → 可选踏板，自主分批验证。

- [D和弦专项修复方法](planning/CHORD_D_REPAIR_HANDOFF.md)：源码确认的映射/FIFO/取消问题、三槽准备及统一提交、时序定位与短测试。

- [最后一轮键位收尾执行清单](planning/FINAL_KEYMAP_CLOSEOUT_HANDOFF.md)：先完成E边界和D小修，再做真实音源短测与有证据的时序修复；明确复用、构建预算和剩余项交付。

- [过载回归优先排查与赛题功能取舍](planning/AUDIO_REGRESSION_AND_SCOPE_HANDOFF.md)：用户反馈过载/F5/F6异常；优先逐级音频定位，再修表情，最后评估四和弦精简方案。

- [最新范围：删F5、统一F6听感并接入四强力和弦](planning/DEMO_SIMPLIFICATION_AND_CHORD_HANDOFF.md)：明确实际删除范围、F6前段保留与后段编排、QWER/JKL实施顺序及验证边界。

## Default version (2026-10-26, ADC slider filter)
- Accepted default bitstream and rollback: [DEFAULT_VERSION.md](DEFAULT_VERSION.md)
