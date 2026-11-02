// USB键盘接入封装：只使用新的独立分区快照（piano/guitar/chord/drum/fret/f/nav）。
// 旧 usb_key_snapshot 的混合 held 字段不再实例化，避免新旧快照混用。
// 沿用已验证USB工程的12MHz主机及PLL初始化；字段全部在音频域按已提交原子快照输出。
module usb_keyboard(
    input sys_clk, input audio_clk, input rst_n,
    inout usb_dp, inout usb_dm,
    output [15:0] piano_held, output [5:0] guitar_held, output [3:0] chord_held,
    output [8:0] drum_held, output [12:0] fret_held,
    output [11:0] f_held, output [7:0] nav_held,
    output lshift, output lctrl, output rctrl, output space_held, output esc_held,
    output keyboard_present
);
    wire usb_clk, pll_locked;
    Gowin_PLL u_pll(.clkin(sys_clk),.clkout0(usb_clk),.lock(pll_locked),
        .mdclk(sys_clk),.reset(!rst_n));
    // 锁定丢失异步拉低，两级同步释放；仅同步器清零脚允许时序例外。
    reg [1:0] lock_release=0;
    always @(posedge usb_clk or negedge pll_locked)
        if(!pll_locked) lock_release<=0;
        else lock_release<={lock_release[0],1'b1};
    reg [15:0] startup=0;
    always @(posedge usb_clk)
        if(!lock_release[1] || !rst_n) startup<=0;
        else if(!(&startup)) startup<=startup+1'b1;
    wire usb_reset_n=&startup;
    wire [1:0] device_type;
    wire report, connection_error;
    wire [63:0] raw_report;
    usb_hid_host u_host(.usbclk(usb_clk),.usbrst_n(usb_reset_n),
        .usb_dp(usb_dp),.usb_dm(usb_dm),.typ(device_type),.report(report),
        .conerr(connection_error),.dbg_hid_report(raw_report),
        .key_modifiers(),.key1(),.key2(),.key3(),.key4(),
        .mouse_btn(),.mouse_dx(),.mouse_dy(),.game_l(),.game_r(),.game_u(),.game_d(),
        .game_a(),.game_b(),.game_x(),.game_y(),.game_sel(),.game_sta());
    wire [15:0] z_piano; wire [5:0] z_guitar; wire [3:0] z_chord; wire [8:0] z_drum;
    wire [12:0] z_fret; wire [11:0] z_f; wire [7:0] z_nav;
    wire z_ls,z_lc,z_rc,z_space,z_esc,z_conn;
    usb_zones_snapshot u_zones(.usb_clk(usb_clk),.audio_clk(audio_clk),.rst_n(rst_n),
        .ready(usb_reset_n),.typ(device_type),.report(report),.raw(raw_report),
        .piano(z_piano),.guitar(z_guitar),.chord(z_chord),.drum(z_drum),.fret(z_fret),
        .f(z_f),.nav(z_nav),
        .lshift(z_ls),.lctrl(z_lc),.rctrl(z_rc),.space(z_space),.esc(z_esc),.connected(z_conn));
    // 在线标志打一拍：切断 lock_sync→各字段掩码→各声部CE 的长组合链；
    // 标志晚1拍建立（约19ns），断连/重连语义不变，不可感。
    reg [1:0] lock_sync=0;
    always @(posedge audio_clk or negedge rst_n)
        if(!rst_n) lock_sync<=0;
        else lock_sync<={lock_sync[0],pll_locked};
    reg keyboard_present_r;
    always @(posedge audio_clk or negedge rst_n)
        if(!rst_n) keyboard_present_r<=1'b0;
        else keyboard_present_r<=z_conn && lock_sync[1];
    assign keyboard_present=keyboard_present_r;
    assign piano_held  = keyboard_present ? z_piano  : 16'b0;
    assign guitar_held = keyboard_present ? z_guitar : 6'b0;
    assign chord_held  = keyboard_present ? z_chord  : 4'b0;
    assign drum_held   = keyboard_present ? z_drum   : 9'b0;
    assign fret_held   = keyboard_present ? z_fret   : 13'b0;
    assign f_held      = keyboard_present ? z_f       : 12'b0;
    assign nav_held    = keyboard_present ? z_nav     : 8'b0;
    assign lshift      = keyboard_present ? z_ls      : 1'b0;
    assign lctrl       = keyboard_present ? z_lc      : 1'b0;
    assign rctrl       = keyboard_present ? z_rc      : 1'b0;
    assign space_held  = keyboard_present ? z_space   : 1'b0;
    assign esc_held    = keyboard_present ? z_esc     : 1'b0;
endmodule
