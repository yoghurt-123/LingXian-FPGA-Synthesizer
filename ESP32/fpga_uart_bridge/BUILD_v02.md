# v0.2 编译验证

- 已使用本机 Arduino builder、ESP32 core 3.3.12、真实ESP32-C3工具链完成全量编译及链接，退出码0。
- FQBN：esp32:esp32:esp32c3:CDCOnBoot=cdc。
- Flash：644527 / 1310720字节（49%）。
- 静态RAM：19040 / 327680字节（5%）。此数字不包括运行时BLE动态分配，不能作为实际剩余堆空间。
- 新版固件：`build_v02/fpga_uart_bridge.ino.bin`。
- 完整合并固件：`build_v02/fpga_uart_bridge.ino.merged.bin`。
- 编译日志：`compile_v02.log`。存在BLE2902弃用警告，无编译错误。
- 用户使用Arduino打开本目录`.ino`上传即可，不要选择旧`build/`里的v0.1二进制。
- 未执行硬件烧录，未对用户iPad或ESP实物延迟作直接测量。

FPGA无需重新烧录：RTL和测试位流未改。新增仿真测得完整串口请求回复1.11668ms，16项通过。
