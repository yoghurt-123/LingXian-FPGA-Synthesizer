# v0.2 延迟排查与修订

用户现象：iPad 调试工具中两次 PONG 显示间隔可超过一分钟。

## 已确认的代码证据

- FPGA 独立测试 RTL 未改变。2026-10-24 重新运行测试，正常请求开始到接收完回复为 1116680 ns（1.11668 ms，测试含发送端字节间隔），16 项测试全部通过。日志：`../../GowinProjects/ble_uart_link_test/sim/latency_check_20261024.log`。这证明仿真中的处理速度，不是实际板上 BLE 往返测量。
- 桥接程序没有一分钟的轮询定时器，FPGA 回复超时为600ms。
- 本机 ESP32 core 3.3.12 的 `cores/esp32/HWCDC.cpp` 默认 `tx_timeout_ms=100`，USB TX 主机背压路径最多连续等待20次：一次 write 可累积约2秒。桥接程序在请求/回复路径里调用多次 Serial.print，包括逐字节十六进制日志。主机不及时读走 USB 数据时，多次 write 有累积延迟风险，且会推迟 UART 解析与 BLE notify。
- 修订：Serial.begin 后设置 Serial.setTxTimeoutMs(0)，日志缓冲满时允许丢日志，通信不等日志。加入 BLE RX uptime 时间及 UART RTT 毫秒日志，版本改为v0.2。线上UART协议、UUID、引脚和FPGA位流不变。

## 结论边界

修复了一个可导致长延迟的确定软件风险；尚未在用户实物复现缓冲背压，不能断言已唯一证明一分钟现象的根因。不能仅凭 nRF Connect 界面刷新认定 BLE 本身延迟。实际还需重新上传v0.2并在App测量。

## 复测

1. 上传本目录 fpga_uart_bridge.ino 修订版，工具仍选 ESP32C3 Dev Module、USB CDC Enabled。
2. FPGA继续使用已通过回显的独立测试位流；无需重跑整机PnR。
3. 在nRF Connect中断开设备；App v0.9.0主页进入蓝牙连接，扫描、连接，等待通知订阅成功。
4. 先测试ESP，再测试FPGA，每次等待完成后再次点击。记录10次往返耗时。
5. 对比串口监视器打开和关闭两种情况。正常程序不应依赖电脑是否读取USB日志。
6. App 3秒无匹配回复会报错并断开，防止无序旧回复被当作新请求结果。

App支持的是链路测试。FPGA独立测试位流没有音源，App演奏键尚不能驱动FPGA。
