// 隔离底鼓工程顶层：C 键 -> drum_engine -> 音量 -> audio_drive(DAC/I2S) + 功放使能。
// 端口与主 top 同名以复用现有 audio.cst；不含钢琴/吉他/过载/演示，避免全工程布线拥塞。
module drum_top (
    input sys_clk,
    inout usb_dp, usb_dm,
    input TTP_SDO,
    output TTP_SCL,
    input key1, key0, rst_n,
    output HP_BCK, HP_WS, HP_DIN, PA_EN,
    output WS2812_DATA,
    output UART_TX
);
    wire clk;
    Gowin_OSC u_osc(.oscout(clk), .oscen(1'b1));   // 标称 52.5MHz
    reg [15:0] startup = 16'd0;
    reg [1:0] reset_sync = 2'b00;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) reset_sync <= 2'b00; else reset_sync <= {reset_sync[0], 1'b1};
    always @(posedge clk)
        if (!reset_sync[1]) startup <= 0; else if (!(&startup)) startup <= startup + 1'b1;
    wire audio_reset_n = &startup;
    wire sample_tick;
    wire signed [15:0] pcm_out;
    audio_drive #(.BCK_HALF_DIV(17)) u_audio(
        .clk(clk), .rst_n(audio_reset_n), .idata(pcm_out), .req(sample_tick),
        .HP_BCK(HP_BCK), .HP_WS(HP_WS), .HP_DIN(HP_DIN));
    audio_amp_control u_amp(.clk(clk), .rst_n(audio_reset_n), .pa_en(PA_EN));
    // USB 键盘（仅取 C 键、力度、音量、Esc、在线）
    wire [15:0] usb_held; wire usb_space, usb_esc, usb_ls;
    wire [2:0] usb_kp; wire [5:0] usb_f; wire [15:0] usb_bend_unused;
    wire usb_vdn, usb_vup; wire usb_c; wire present;
    usb_keyboard u_usb(
        .sys_clk(sys_clk), .audio_clk(clk), .rst_n(audio_reset_n),
        .usb_dp(usb_dp), .usb_dm(usb_dm),
        .held(usb_held), .space_held(usb_space), .f_held(usb_f), .esc_held(usb_esc),
        .kp_held(usb_kp), .lshift(usb_ls),
        .vol_down_held(usb_vdn), .vol_up_held(usb_vup),
        .oct_down_held(), .oct_up_held(), .bend_left_held(), .bend_right_held(),
        .vib_held(), .fret_held(), .b_held(), .pgup_held(), .pgdn_held(), .lctrl_held(),
        .chord_held(), .f7_held(), .c_held(usb_c), .keyboard_present(present));
    // 1-clk 寄存：切断 USB 快照->力度/音量/触发 的长组合链（不影响语义）
    reg [2:0] kp_r; reg ls_r, vup_r, vdn_r, c_r, esc_r, present_r;
    always @(posedge clk or negedge audio_reset_n) begin
        if (!audio_reset_n) begin kp_r<=0; ls_r<=0; vup_r<=0; vdn_r<=0; c_r<=0; esc_r<=0; present_r<=0; end
        else begin kp_r<=usb_kp; ls_r<=usb_ls; vup_r<=usb_vup; vdn_r<=usb_vdn; c_r<=usb_c; esc_r<=usb_esc; present_r<=present; end
    end
    wire [3:0] usb_vel;
    usb_velocity_control u_vel(.kp_held(kp_r), .lshift(ls_r), .velocity(usb_vel));
    // C 上升沿 -> 鼓触发（长按只一次）；Esc/断连取消
    reg c_d;
    always @(posedge clk or negedge audio_reset_n)
        if (!audio_reset_n) c_d <= 1'b0; else c_d <= c_r;
    wire kick_trig = c_r & ~c_d;
    wire signed [15:0] kick_pcm;
    wire kick_active, kick_clip;
    drum_engine u_kick(
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick),
        .trig(kick_trig), .vel(usb_vel), .cancel(esc_r | ~present_r), .test_cfg(2'b11),
        .data(kick_pcm), .active(kick_active), .clip_count());
    // 总音量（F8/F9），Q1.15 gain
    wire [4:0] vol_level; wire [15:0] vol_gain, vol_target;
    usb_volume_control u_vol(
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick), .connected(present_r),
        .vol_up(vup_r), .vol_down(vdn_r), .req_block(1'b0),
        .level(vol_level), .gain(vol_gain), .target(vol_target));
    wire signed [31:0] vol_mul = $signed(kick_pcm) * $signed({1'b0, vol_gain});
    wire signed [23:0] vol_shift = vol_mul >>> 15;
    wire signed [15:0] pcm_scaled = (vol_shift > 24'sd32767) ? 16'sd32767 :
                                    (vol_shift < -24'sd32768) ? -16'sd32768 : vol_shift[15:0];
    assign pcm_out = pcm_scaled;
    assign TTP_SCL = 1'b0;
    assign WS2812_DATA = 1'b0;
    assign UART_TX = 1'b1;
endmodule
