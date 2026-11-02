# 灵弦复音合成器

基于 FPGA 的实时合成电子乐器，集成钢琴、电吉他与架子鼓音源，支持实体键盘、TTP229 触摸交互、滑杆音效控制、iPad 蓝牙演奏及网页频谱与波形显示。

## 工程目录

- `FPGA/`：RTL、工程文件、约束与构建脚本
- `ESP32/`：BLE/UART 桥接固件
- `iPadApp/`：Swift Playgrounds App 工程
- `DisplayWeb/`：串口可视化网页
- `MusicPacks/`：音乐指令包
- `Tools/`：转换与测试工具
- `Docs/`：协议、接线与使用说明
- `AcceptedBinaries/`：已验收固件与报告

详细说明见 [提交说明](README_提交说明.md)。第三方素材及音乐文件的来源与使用范围以各文件随附说明为准。
