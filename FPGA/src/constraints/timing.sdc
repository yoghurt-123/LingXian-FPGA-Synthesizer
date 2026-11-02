create_clock -name audio_clk -period 19.047619 [get_pins {u_osc/osc_inst/OSCOUT}]
set_false_path -from [get_ports {rst_n}]

# USB独立时钟；音频保持原52.5MHz约束。
create_clock -name sys_clk -period 20 [get_ports {sys_clk}]
create_generated_clock -name usb_clk -source [get_ports {sys_clk}] -multiply_by 6 -divide_by 25 [get_pins {u_usb_keyboard/u_pll/u_pll_0/PLLA_inst/CLKOUT0}]
set_clock_groups -asynchronous -group [get_clocks {audio_clk}] -group [get_clocks {sys_clk}]
set_clock_groups -asynchronous -group [get_clocks {audio_clk}] -group [get_clocks {usb_clk}]
# PLL锁定只对两级复位释放同步器的异步清零脚有跨域路径；其他sys/usb路径仍正常检查。
# 综合会给寄存器加后缀（如 lock_release_0_s0），用通配符只匹配这两级同步器的 CLEAR，不扩大屏蔽范围。
set_false_path -from [get_clocks {sys_clk}] -to [get_pins {u_usb_keyboard/lock_release_*/CLEAR}]
