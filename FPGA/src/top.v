// TTP229固定钢琴 + USB三乐器并奏（钢琴/吉他/和弦/鼓）。
// TTP KEY1..KEY7 = C4 D4 E4 F4 G4 A4 B4，KEY8 = C5，KEY9 = D5，
// KEY10 = C#4，KEY11 = D#4，KEY12 = F#4，KEY13 = G#4，KEY14 = A#4，
// KEY15 = C#5，KEY16 = D#5；始终只触发钢琴，不再有吉他触摸分支。
// USB：钢琴 A-L=白键、Z-M=黑键；吉他 QWERTY；和弦 UIOP；鼓小键盘1..9；
//      Home/End八度，F1/F2力度，F10颤音，F11滑音，PgUp/PgDn滑音时间，
//      左/右箭头弯音，左Ctrl吉他闷音，右Ctrl钢琴踏板延迟释放，F6吉他演示。
// S2：删除钢琴/吉他互斥mode及板载KEY0/KEY1演奏、模式切换和钢琴歌曲；三乐器独立接受输入。
// 彩灯：无吉他发声=绿；吉他清音=蓝；吉他过载=紫。任一声道发声时VOFA输出同一份混音。
// 每个音一个独立发声实例，未按键的通道静音，各键互不干扰。
module top #(parameter integer BEND_RAMP = 1448, parameter integer VIB_RAMP = 965) (
    input sys_clk,
    input ble_uart_rx,
    output ble_uart_tx,     // 板载50MHz晶振V22，仅供USB时钟初始化
    inout usb_dp, usb_dm,    // 板载USB-A数据线H13/G13，选择开关置FPGA
    input TTP_SDO,          // 触摸模块串行数据，接 C18
    output TTP_SCL,         // 触摸模块时钟，接 C19
    input rst_n,            // 板载 KEY.2，低电平复位，内部上拉
    output HP_BCK,
    output HP_WS,
    output HP_DIN,
    output PA_EN,
    output WS2812_DATA,     // 板载彩灯数据，J16，上电显示绿色
    output UART_TX,
    input key_filter_n,
    inout adc_scl,
    inout adc_sda
);
    // 提前声明跨段使用信号，兼容ModelSim；只移动声明，不改变原控制逻辑。
    wire [1:0] led_color;         // 彩灯颜色：0=绿(钢琴) 1=蓝(吉他清音) 2=紫(吉他过载)
    wire [2:0] demo_wr_slot; wire [3:0] demo_wr_note;
    wire demo2_wr_en, demo2_mute_req, demo2_pool_rst;
    wire [5:0] demo2_trig, demo2_fade, demo2_pluck_mute;
    wire [2:0] demo2_wr_slot; wire [3:0] demo2_wr_note;
    wire pulse_c5, act_c5;
    wire clk;
    Gowin_OSC u_osc(.oscout(clk), .oscen(1'b1)); // 标称时钟 52.5 MHz

    // 利用寄存器初值实现上电复位。
    reg [15:0] startup = 16'd0;
    reg [1:0] reset_sync = 2'b00;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) reset_sync <= 2'b00;
        else reset_sync <= {reset_sync[0], 1'b1};
    always @(posedge clk)
        if (!reset_sync[1]) startup <= 0;
        else if (!(&startup)) startup <= startup + 1'b1;
    wire audio_reset_n = &startup;
    // USB接入：新分区快照；S2无mode，钢琴/吉他/和弦/鼓独立接受输入。
    wire [15:0] usb_piano_held;
    wire [5:0]  usb_guitar_held;
    wire [3:0]  usb_chord_held;
    wire [8:0]  usb_drum_held;
    wire [12:0] usb_fret_held;
    wire [11:0] usb_f_held;
    wire [7:0]  usb_nav_held;
    wire usb_lshift, usb_lctrl_held, usb_rctrl_held, usb_space_held, usb_esc_held;
    wire usb_f1, usb_f2, usb_f3, usb_f4, usb_f5, usb_f6, usb_f7, usb_f8, usb_f9, usb_f10, usb_f11, usb_f12;
    wire usb_home, usb_end, usb_nav_up, usb_nav_down, usb_left, usb_right, usb_pgdn, usb_pgup;
    wire [3:0] usb_vel_eff;
    wire [15:0] piano_pedal_rel; wire piano_pedal_on;
    wire [5:0] gtr_trig_mute;
    // D和弦执行器（UIOP选并三音齐奏；六弦走独立guitar_held）
    wire [5:0] ch_trig, ch_trig_mute, ch_fade; wire [23:0] ch_trig_fret;
    wire chord_wr, chord_hold, chord_mute; wire [1:0] ch_wr_slot; wire [3:0] ch_wr_note, ch_wr_vel; wire [15:0] ch_overflow;
    reg [3:0] ch_note0, ch_note1, ch_note2, ch_vel0, ch_vel1, ch_vel2;
    wire [3:0] expr_fret_sel, expr_fret_eff; wire expr_b_on; wire [4:0] expr_time_sel; wire [13:0] expr_slide_n;
    wire [23:0] gtr_trig_fret;
    wire [4:0] vol_level;
    wire [15:0] vol_gain, vol_target;
    wire [1:0] oct_sel, oct_sel_next, usb_trig_oct;
    wire usb_keyboard_present;
    wire demo2_active;
    // 统一停止控制线（提前声明，esc/space由USB保持位驱动，全部门控在本拍生效）
    wire stop_cancel_now, stop_block, piano_rel_req, kill_commit, fx_clear, rev_clear_req, vofa_hold;
    wire gtr_rev_clear_done, vofa_frame_done;
    wire vofa_tx_unused;
    wire [15:0] panic_gain;
    wire filter_on;
    wire adc_params_ok;
    wire [8:0] adc_a2;
    wire gtr_drive_slider = filter_on && adc_params_ok;
    wire piano_inhibit = usb_space_held | stop_block | stop_cancel_now;  // Space/Esc：拒绝新手弹钢琴
    wire piano_play_ok = ~piano_inhibit;                                 // TTP固定钢琴起音门控
    wire gtr_inhibit = usb_space_held | stop_block;                      // Space/Esc：拒绝新手弹吉他
    // TTP固定钢琴触发（bit0..15与NOTE_SEL一致）
    wire [15:0] ttp_piano_trig, piano_trig_all, piano_src_usb;
    // 新快照特殊键集中切片（位序只在 usb_hid_zones/usb_zones_snapshot 定义）。
    assign usb_f1=usb_f_held[0];  assign usb_f2=usb_f_held[1];  assign usb_f3=usb_f_held[2];
    assign usb_f4=usb_f_held[3];  assign usb_f5=usb_f_held[4];  assign usb_f6=usb_f_held[5];
    assign usb_f7=usb_f_held[6];  assign usb_f8=usb_f_held[7];  assign usb_f9=usb_f_held[8];
    assign usb_f10=usb_f_held[9]; assign usb_f11=usb_f_held[10];assign usb_f12=usb_f_held[11];
    assign usb_home=usb_nav_held[0];  assign usb_end=usb_nav_held[1];
    assign usb_nav_up=usb_nav_held[2];assign usb_nav_down=usb_nav_held[3];
    assign usb_left=usb_nav_held[4];  assign usb_right=usb_nav_held[5];
    assign usb_pgdn=usb_nav_held[6];  assign usb_pgup=usb_nav_held[7];
    // USB功能键请求线
    wire usb_fx_req, usb_rev_req;
    wire usb_d2_start, usb_d2_stop;
    usb_keyboard u_usb_keyboard(.sys_clk(sys_clk),.audio_clk(clk),.rst_n(audio_reset_n),
        .usb_dp(usb_dp),.usb_dm(usb_dm),
        .piano_held(usb_piano_held),.guitar_held(usb_guitar_held),.chord_held(usb_chord_held),
        .drum_held(usb_drum_held),.fret_held(usb_fret_held),.f_held(usb_f_held),.nav_held(usb_nav_held),
        .lshift(usb_lshift),.lctrl(usb_lctrl_held),.rctrl(usb_rctrl_held),
        .space_held(usb_space_held),.esc_held(usb_esc_held),
        .keyboard_present(usb_keyboard_present));
    // ★F11滑音开关/PageUp-Down时间/最小品位选择（S2无mode；Esc/Space同拍忽略选择）
    guitar_expression_keys u_expr(.clk(clk),.rst_n(audio_reset_n),
        .connected(usb_keyboard_present),.block(stop_cancel_now|gtr_inhibit),
        .fret_held(usb_fret_held),.glide_key(usb_f11),.pgup(usb_pgup),.pgdn(usb_pgdn),
        .fret_sel(expr_fret_sel),.fret_eff(expr_fret_eff),.b_on(expr_b_on),
        .time_sel(expr_time_sel),.slide_samples(expr_slide_n));
    // USB手动力度选择：F1降档/F2升档+左Shift重音；默认中档11，与迁移前听感一致。
    usb_velocity_control u_usb_velocity(.clk(clk),.rst_n(audio_reset_n),
        .connected(usb_keyboard_present),.f_down(usb_f1),.f_up(usb_f2),
        .lshift(usb_lshift),.velocity(usb_vel_eff));
    // USB钢琴：按下沿转单拍触发；与TTP固定钢琴在同一声部入口合并。
    wire [15:0] usb_piano_trig;
    usb_piano_keys u_usb_piano_keys(.clk(clk),.rst_n(audio_reset_n),
        .connected(usb_keyboard_present),.blocked(piano_inhibit),
        .held(usb_piano_held),
        .octave(oct_sel_next),.trig(usb_piano_trig),.trig_oct(usb_trig_oct));
    // USB吉他：六根空弦按下沿转单拍拨弦；Space/断连产生制音清理脉冲。
    wire [5:0] usb_gtr_pluck; wire usb_gtr_space_mute, usb_gtr_disc_mute;
    usb_guitar_keys u_usb_guitar_keys(.clk(clk),.rst_n(audio_reset_n),
        .connected(usb_keyboard_present),.blocked(gtr_inhibit | stop_cancel_now),
        .held(usb_guitar_held),.space(usb_space_held),
        .pluck(usb_gtr_pluck),.space_mute(usb_gtr_space_mute),.disc_mute(usb_gtr_disc_mute));
    // USB功能键：F3效果、F4混响、F6演示2启停（F5按既有范围保留为空）；S2后无mode门控。
    usb_func_keys u_usb_func_keys(.clk(clk),.rst_n(audio_reset_n),
        .connected(usb_keyboard_present),.key({usb_f6,usb_f4,usb_f3}),
        .space(usb_space_held),.demo2_active(demo2_active),
        .cancel_now(stop_cancel_now),.blocked(stop_block),
        .fx_req(usb_fx_req),.rev_req(usb_rev_req),
        .demo2_start(usb_d2_start),.demo2_stop(usb_d2_stop));
    // 彩灯颜色在吉他声部状态声明后统一赋值（无吉他=绿，清音=蓝，过载=紫）。
    status_led u_status_led(.clk(clk),.rst_n(audio_reset_n),.color_sel(led_color),.led_data(WS2812_DATA));
    wire sample_tick;
    // 钢琴踏板：F7开关；右Ctrl延迟释放，左Ctrl只留给吉他闷音，互不串联。
    piano_pedal_ctrl u_pedal(.clk(clk),.rst_n(audio_reset_n),.sample_tick(sample_tick),
        .f7_held(usb_f7),.usb_held(usb_piano_held),.pedal_mod(usb_rctrl_held),
        .clear_req(usb_space_held | usb_esc_held | ~usb_keyboard_present),
        .pedal_on(piano_pedal_on),.rel_pulse(piano_pedal_rel));
    // sample_tick 扇出大：给吉他链路（voice/fx/reverb）单独打一拍再驱动，切断长线扇出路径；
    // 整条吉他链路同步延迟 1 个时钟（≈19ns），不影响音色与事件时序。
    reg sample_tick_gtr;
    always @(posedge clk or negedge audio_reset_n)
        if (!audio_reset_n) sample_tick_gtr <= 1'b0;
        else sample_tick_gtr <= sample_tick;
    reg signed [15:0] pcm_sample; // 混音结果打一拍后送 DAC 与 VOFA（两者共用同一份 PCM）

    // ------------------------------------------------------------------
    // TTP229十六路触摸键：每路各自消抖；S2起固定钢琴，不再有吉他触摸分支。
    // ------------------------------------------------------------------
    wire pulse_re, pulse_mi, pulse_fa, pulse_sol, pulse_la, pulse_si;
    wire touch_do;
    wire [15:0] touch_keys;
    // 空闲 2.5ms，大于协议复位间隔；整轮扫描约 2.66ms。
    ttp229_reader #(.POLL_CLKS(131250)) u_touch (
        .clk(clk), .rst_n(audio_reset_n), .sdo(TTP_SDO), .scl(TTP_SCL),
        .keys(touch_keys), .keys_valid()
    );
    // 稳定 3ms 才触发，可排除一次孤立错误扫描；松开稳定 10ms 重新允许。
    // ★触摸键消抖调整位置：各实例的 .PRESS_CLKS(157500)=3ms，松开时间用模块默认值。
    //   每个键独立一个实例、独立消抖，多键同时触摸互不影响（和弦演奏依赖这一点）。
    // KEY1 -> Do，KEY2..KEY7 -> Re Mi Fa Sol La Si。
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key1 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[0]), .pulse(touch_do)
    );
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key2 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[1]), .pulse(pulse_re)
    );
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key3 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[2]), .pulse(pulse_mi)
    );
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key4 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[3]), .pulse(pulse_fa)
    );
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key5 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[4]), .pulse(pulse_sol)
    );
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key6 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[5]), .pulse(pulse_la)
    );
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key7 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[6]), .pulse(pulse_si)
    );
    // KEY9：改为高一个八度的 Re（D5，NOTE_SEL=8，参数由 tone (54).wav 拟合）。
    // 原"一键 C 和弦试听"入口取消；多键同时按下仍由各键独立触发组成和弦。
    wire pulse_d5;
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key9 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[8]), .pulse(pulse_d5)
    );
    // KEY10/KEY11：C#4 / D#4，与其它触摸键同样的独立消抖。
    wire pulse_cs4, pulse_ds4;
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key10 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[9]), .pulse(pulse_cs4)
    );
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key11 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[10]), .pulse(pulse_ds4)
    );
    // KEY12/KEY13/KEY14：F#4 / G#4 / A#4，各自独立消抖。
    wire pulse_fs4, pulse_gs4, pulse_as4;
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key12 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[11]), .pulse(pulse_fs4)
    );
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key13 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[12]), .pulse(pulse_gs4)
    );
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key14 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[13]), .pulse(pulse_as4)
    );
    // KEY15/KEY16：C#5 / D#5（最后两个升音），各自独立消抖。
    wire pulse_cs5, pulse_ds5;
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key15 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[14]), .pulse(pulse_cs5)
    );
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key16 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[15]), .pulse(pulse_ds5)
    );
    // TTP固定钢琴：bit0..15与NOTE_SEL一致；同拍TTP优先于USB，供声部来源管理。
    assign ttp_piano_trig = {pulse_ds5,pulse_cs5,pulse_as4,pulse_gs4,pulse_fs4,
                             pulse_ds4,pulse_cs4,pulse_d5,pulse_c5,pulse_si,pulse_la,
                             pulse_sol,pulse_fa,pulse_mi,pulse_re,touch_do};
    wire [15:0] ttp_piano_ok = ttp_piano_trig & {16{piano_play_ok}};
    wire [15:0] piano_src_ble;
    wire [15:0] ble_piano_trig, ble_piano_rel, ble_piano_held;
    wire [63:0] ble_piano_vel;
    wire [1:0] ble_piano_oct;
    wire ble_damp_on, ble_pedal_delay;
    wire [8:0] ble_drum_pulse;
    wire [3:0] ble_drum_vel;
    wire [5:0] ble_gtr_pluck;
    wire [3:0] ble_gtr_fret, ble_gtr_vel;
    wire ble_gtr_palm;
    wire [1:0] ble_chord_sel;
    wire ble_chord_sel_we, ble_chord_trig, ble_chord_release;
    wire [3:0] ble_chord_vel;
    wire ble_chord_palm;
    wire [1:0] ble_bend;
    wire ble_vib, ble_glide;
    wire [4:0] ble_slide_time;
    wire ble_fx_set, ble_fx_target, ble_rev_set, ble_rev_target;
    wire ble_all_off;
    wire [23:0] ble_ev_wdata, ble_ev_rdata;
    wire ble_ev_we, ble_ev_full, ble_ev_empty, ble_ev_re, ble_ev_overflow;
    wire [63:0] song_perf;
    wire song_uart_we;
    wire song_ev_we;
    wire [2:0] song_cmd;
    wire [31:0] song_play_id, song_event_count, song_duration_samples, song_lead_samples;
    wire [23:0] song_ev_data;
    wire song_active;

    ble_ctrl_proto u_ble_ctrl(
        .sys_clk(sys_clk), .rst_n(rst_n),
        .uart_rx(ble_uart_rx), .uart_tx(ble_uart_tx),
        .ev_data(ble_ev_wdata), .ev_we(ble_ev_we), .ev_full(ble_ev_full),
        .overflow(ble_ev_overflow),
        .song_perf(song_perf), .song_we(song_uart_we), .song_cmd(song_cmd),
        .song_play_id(song_play_id), .song_event_count(song_event_count),
        .song_duration_samples(song_duration_samples), .song_lead_samples(song_lead_samples)
    );

    reg audio_tick_toggle;
    always @(posedge clk or negedge audio_reset_n)
        if (!audio_reset_n) audio_tick_toggle <= 1'b0;
        else if (sample_tick) audio_tick_toggle <= ~audio_tick_toggle;

    song_scheduler #(.QUEUE_AW(7)) u_song_sched(
        .sys_clk(sys_clk), .sys_rst_n(rst_n), .audio_tick_toggle(audio_tick_toggle),
        .in_perf(song_perf), .in_we(song_uart_we), .in_cmd(song_cmd),
        .in_play_id(song_play_id), .in_event_count(song_event_count),
        .in_duration_samples(song_duration_samples), .in_lead_samples(song_lead_samples),
        .ev_full(ble_ev_full), .ev_data(song_ev_data), .ev_we(song_ev_we),
        .song_active(song_active)
    );
    wire ble_fifo_we = ble_ev_we | song_ev_we;
    wire [23:0] ble_fifo_wdata = song_ev_we ? song_ev_data : ble_ev_wdata;

    ble_event_fifo #(.WIDTH(24), .ADDR_BITS(4)) u_ble_fifo(
        .wclk(sys_clk), .wrst_n(rst_n), .we(ble_fifo_we), .wdata(ble_fifo_wdata),
        .full(ble_ev_full),
        .rclk(clk), .rrst_n(audio_reset_n), .re(ble_ev_re),
        .rdata(ble_ev_rdata), .empty(ble_ev_empty)
    );
    ble_audio_ctrl u_ble_audio(
        .clk(clk), .rst_n(audio_reset_n),
        .ev_empty(ble_ev_empty), .ev_data(ble_ev_rdata), .ev_re(ble_ev_re),
        .touch_keys(touch_keys), .usb_piano_held(usb_piano_held),
        .ble_piano_trig(ble_piano_trig), .ble_piano_rel(ble_piano_rel),
        .ble_piano_held(ble_piano_held), .ble_piano_vel(ble_piano_vel),
        .ble_piano_oct(ble_piano_oct), .ble_damp_on(ble_damp_on),
        .ble_pedal_delay(ble_pedal_delay),
        .ble_drum_pulse(ble_drum_pulse), .ble_drum_vel(ble_drum_vel),
        .ble_gtr_pluck(ble_gtr_pluck), .ble_gtr_fret(ble_gtr_fret),
        .ble_gtr_vel(ble_gtr_vel), .ble_gtr_palm(ble_gtr_palm),
        .ble_chord_sel(ble_chord_sel), .ble_chord_sel_we(ble_chord_sel_we),
        .ble_chord_trig(ble_chord_trig), .ble_chord_vel(ble_chord_vel),
        .ble_chord_palm(ble_chord_palm), .ble_chord_release(ble_chord_release),
        .ble_bend(ble_bend), .ble_vib(ble_vib), .ble_glide(ble_glide),
        .ble_slide_time(ble_slide_time),
        .ble_fx_set(ble_fx_set), .ble_fx_target(ble_fx_target),
        .ble_rev_set(ble_rev_set), .ble_rev_target(ble_rev_target),
        .ble_all_off(ble_all_off)
    );

    assign piano_trig_all = ttp_piano_ok | usb_piano_trig | ble_piano_trig;
    assign piano_src_usb = usb_piano_trig & ~ttp_piano_ok;
    assign piano_src_ble = ble_piano_trig & ~ttp_piano_ok & ~usb_piano_trig;
    wire kill_all = kill_commit | ble_all_off;
    // ------------------------------------------------------------------
    // 吉他声部控制与音源（定点、无浮点、无录音ROM，与离线试听脚本同一参数）。
    // 吉他手动输入只来自USB QWERTY/UIOP/F3/F6；TTP固定钢琴，不再映射吉他。
    // ------------------------------------------------------------------
    wire [5:0] ctrl_trig, ctrl_fade;
    wire ctrl_mute, gtr_drv, gtr_fx_wanted, gtr_active, gtr_ctrl_active;
    wire signed [15:0] gtr_raw, pcm_guitar;
    wire [2:0] gtr_low_note;   // 清音增益选择：1=A2 2=D3 3=G3 4=B3 0=其他（只进清音分支）
    wire [5:0] gtr_slot_busy;
    wire gtr_solo_wr; wire [1:0] gtr_solo_slot; wire [3:0] gtr_solo_note; wire [3:0] gtr_solo_vel;
    wire gtr_e2_vel_wr; wire [3:0] gtr_e2_vel;
    // 单音弦池槽音色寄存器（仅当槽空闲时由 ctrl 写入；发声中不改变，避免变音）
    reg [3:0] gtr_pool_note0 = 4'd3;   // 池槽0 -> A2
    reg [3:0] gtr_pool_note1 = 4'd4;   // 池槽1 -> D3
    reg [3:0] gtr_pool_note2 = 4'd5;   // 池槽2 -> G3
    // ★本轮：手动拨弦的每槽力度字段（触摸/板载默认15，USB用F1/F2+左Shift选择；演示分支仍用自身力度）
    reg [3:0] gtr_pool_vel0 = 4'd15; reg [3:0] gtr_pool_vel1 = 4'd15; reg [3:0] gtr_pool_vel2 = 4'd15;
    reg [3:0] gtr_e2_vel_r = 4'd15;
    always @(posedge clk or negedge audio_reset_n)
        if (!audio_reset_n) begin
            gtr_pool_vel0 <= 4'd15; gtr_pool_vel1 <= 4'd15; gtr_pool_vel2 <= 4'd15;
            gtr_e2_vel_r <= 4'd15;
        end else begin
            if (gtr_e2_vel_wr) gtr_e2_vel_r <= gtr_e2_vel;
            if (gtr_solo_wr) begin
                case (gtr_solo_slot)
                    2'd0: gtr_pool_vel0 <= gtr_solo_vel;
                    2'd1: gtr_pool_vel1 <= gtr_solo_vel;
                    default: gtr_pool_vel2 <= gtr_solo_vel;
                endcase
            end
        end
    always @(posedge clk or negedge audio_reset_n)
        if (!audio_reset_n) begin
            gtr_pool_note0 <= 4'd3; gtr_pool_note1 <= 4'd4; gtr_pool_note2 <= 4'd5;
        end else if (demo2_wr_en) begin
            case (demo2_wr_slot)  // 第二首演示同样用槽号 3/4/5
                3'd3: gtr_pool_note0 <= demo2_wr_note;
                3'd4: gtr_pool_note1 <= demo2_wr_note;
                default: gtr_pool_note2 <= demo2_wr_note;
            endcase
        end else if (gtr_solo_wr) begin
            case (gtr_solo_slot)
                2'd0: gtr_pool_note0 <= gtr_solo_note;
                2'd1: gtr_pool_note1 <= gtr_solo_note;
                default: gtr_pool_note2 <= gtr_solo_note;
            endcase
        end
    // 演示播放器1已删除；演示2只由USB F6启停。
    wire [5:0] gtr_trig_raw = demo2_active ? demo2_trig : ctrl_trig;
    // 和弦槽0..2字段：引擎写；E2单音/和弦触发时恢复各自原字段
    always @(posedge clk or negedge audio_reset_n) begin
        if (!audio_reset_n) begin ch_note0 <= 4'd0; ch_note1 <= 4'd1; ch_note2 <= 4'd2; ch_vel0 <= 4'd15; ch_vel1 <= 4'd15; ch_vel2 <= 4'd15; end
        else begin
            if (gtr_e2_vel_wr) begin ch_note0 <= 4'd0; ch_vel0 <= gtr_e2_vel; end
            if (gtr_trig_raw[1]) ch_note1 <= 4'd1;
            if (gtr_trig_raw[2]) ch_note2 <= 4'd2;
            if (chord_wr) begin
                case (ch_wr_slot)
                    2'd0: begin ch_note0 <= ch_wr_note; ch_vel0 <= ch_wr_vel; end
                    2'd1: begin ch_note1 <= ch_wr_note; ch_vel1 <= ch_wr_vel; end
                    default: begin ch_note2 <= ch_wr_note; ch_vel2 <= ch_wr_vel; end
                endcase
            end
        end
    end
    guitar_chord_engine u_chord(.clk(clk),.rst_n(audio_reset_n),.sample_tick(sample_tick),
        .chord_key(usb_chord_held),.vel_now(usb_vel_eff),.ctrl_in(usb_lctrl_held),
        .ble_select_we(ble_chord_sel_we),.ble_select(ble_chord_sel),
        .ble_trigger(ble_chord_trig & ~(demo2_active | gtr_inhibit)),
        .ble_vel(ble_chord_vel),.ble_palm(ble_chord_palm),.ble_release(ble_chord_release),
        .cancel(gtr_inhibit | demo2_active),
        .slot_busy(gtr_slot_busy),.ch_bases({ch_note2,ch_note1,ch_note0}),
        .chord_wr(chord_wr),.wr_slot(ch_wr_slot),.wr_note(ch_wr_note),.wr_vel_meta(ch_wr_vel),
        .ch_trig(ch_trig),.ch_trig_fret(ch_trig_fret),.ch_trig_mute(ch_trig_mute),.ch_fade(ch_fade),
        .chord_hold(chord_hold),.fx_ready(gtr_fx_wanted == gtr_drv),.chord_mute_req(chord_mute),.chord_overflow(ch_overflow));
    wire [5:0] gtr_trig = stop_block ? 6'b0 : gtr_trig_raw;
    wire [5:0] gtr_fade = ctrl_fade | (demo2_active ? demo2_fade : 6'b0);
    wire gtr_mute = ctrl_mute | demo2_mute_req | chord_mute;

    // ---- 演示播放器2（USB F6启停；板载KEY0/模式切换已删除）----
    wire [23:0] demo2_vel;
    wire demo2_start = usb_d2_start;
    wire demo2_stop  = usb_gtr_space_mute | usb_d2_stop | stop_cancel_now | stop_block;
    demo_player2 u_demo2 (
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick),
        .start(demo2_start), .stop(demo2_stop), .slot_busy(gtr_slot_busy),
        .active(demo2_active), .trig(demo2_trig),
        .wr_en(demo2_wr_en), .wr_slot(demo2_wr_slot), .wr_note(demo2_wr_note),
        .fade_req(demo2_fade), .vel_sel(demo2_vel), .pluck_mute(demo2_pluck_mute),
        .mute_req(demo2_mute_req), .pool_rst(demo2_pool_rst)
    );
    // 演示独占吉他手动；钢琴和鼓仍可同时演奏。Space/Esc期间拒绝新手弹。
    wire gtr_play_ok = ~(demo2_active | gtr_inhibit);
    wire [5:0] gtr_trig_usb;
    wire [23:0] gtr_pluck_vel = {6{usb_vel_eff}};
    guitar_ctrl u_gtr_ctrl (
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick),
        .pluck_vel(gtr_pluck_vel),
        .ble_pluck(ble_gtr_pluck & {6{gtr_play_ok & ~stop_block}}),
        .ble_fret(ble_gtr_fret), .ble_vel(ble_gtr_vel), .ble_palm(ble_gtr_palm),
        .ble_fx_set(ble_fx_set & ~stop_block), .ble_fx_value(ble_fx_target),
        .pluck_solo(gtr_play_ok ? usb_gtr_pluck[0] : 1'b0),    // USB Q=E2
        .pluck_a2(gtr_play_ok ? usb_gtr_pluck[1] : 1'b0),      // USB W=A2（第5弦空弦）
        .pluck_d3(gtr_play_ok ? usb_gtr_pluck[2] : 1'b0),      // USB E=D3（第4弦空弦）
        .pluck_g3(gtr_play_ok ? usb_gtr_pluck[3] : 1'b0),      // USB R=G3（第3弦空弦）
        .pluck_b3(gtr_play_ok ? usb_gtr_pluck[4] : 1'b0),      // USB T=B3（第2弦空弦）
        .pluck_e4(gtr_play_ok ? usb_gtr_pluck[5] : 1'b0),      // USB Y=E4（第1弦空弦）
        .pluck_usb(gtr_play_ok ? usb_gtr_pluck : 6'b0),        // USB手动来源（供弯音主奏绑定）
        .fret_in(expr_fret_eff),                               // 本拍有效品位（同报告选品优先）
        .ctrl_in(usb_lctrl_held),                              // 左Ctrl掌根闷音（随USB请求锁存）
        .mute_key(usb_gtr_space_mute | (usb_gtr_disc_mute & ~demo2_active) | stop_block),
        .pool_reset(demo2_pool_rst),
        .fx_key(usb_fx_req),                                   // USB F3=清音/过载
        .slot_busy(gtr_slot_busy),
        .fade_req(ctrl_fade), .solo_wr(gtr_solo_wr), .solo_slot(gtr_solo_slot), .solo_note(gtr_solo_note),
        .solo_vel(gtr_solo_vel), .e2_vel_wr(gtr_e2_vel_wr), .e2_vel(gtr_e2_vel),
        .voice_active(gtr_active),
        .trig(ctrl_trig), .trig_usb(gtr_trig_usb), .trig_fret(gtr_trig_fret), .trig_mute(gtr_trig_mute),
        .voice_mute(ctrl_mute), .chord_hold(chord_hold),
        .drv_sel(gtr_drv), .fx_wanted(gtr_fx_wanted)
    );
    function [13:0] ble_slide_n_of;
        input [4:0] t;
        begin
            case (t)
                5'd1: ble_slide_n_of = 14'd965;
                5'd2: ble_slide_n_of = 14'd1930;
                5'd3: ble_slide_n_of = 14'd2895;
                5'd4: ble_slide_n_of = 14'd3860;
                5'd5: ble_slide_n_of = 14'd4825;
                5'd6: ble_slide_n_of = 14'd5790;
                5'd7: ble_slide_n_of = 14'd6756;
                5'd8: ble_slide_n_of = 14'd7721;
                5'd9: ble_slide_n_of = 14'd8686;
                5'd10: ble_slide_n_of = 14'd9651;
                5'd11: ble_slide_n_of = 14'd10616;
                5'd12: ble_slide_n_of = 14'd11581;
                5'd13: ble_slide_n_of = 14'd12546;
                5'd14: ble_slide_n_of = 14'd13511;
                default: ble_slide_n_of = 14'd14476;
            endcase
        end
    endfunction
    wire usb_expr_active = usb_left | usb_right | usb_f10 | usb_f11 | (|usb_fret_held);
    wire gtr_bend_left_eff = usb_expr_active ? usb_left : (ble_bend == 2'd1);
    wire gtr_bend_right_eff = usb_expr_active ? usb_right : (ble_bend == 2'd2);
    wire gtr_vib_eff = usb_f10 | ble_vib;
    wire gtr_b_on_eff = usb_expr_active ? expr_b_on : ble_glide;
    wire [3:0] gtr_fret_sel_eff = usb_expr_active ? expr_fret_sel : ble_gtr_fret;
    wire [13:0] gtr_slide_samples_eff = usb_expr_active ? expr_slide_n : ble_slide_n_of(ble_slide_time);
    // BLE expression is used when no physical expression key is active.
    // USB expression keys retain priority; this is documented in the protocol.
    // ★吉他弯音：左右箭头(±2半音)只作用于最近实际被接受的USB/BLE手动主奏；倍率在采样间隙统一更新。
    wire [143:0] gtr_slot_ratio;
    pitch_bend_ctrl #(.RAMP_SAMPLES(BEND_RAMP),.VIB_RAMP(VIB_RAMP)) u_pitch_bend(
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick),
        .bend_left(gtr_bend_left_eff), .bend_right(gtr_bend_right_eff), .vib_hold(gtr_vib_eff),
        .connected(1'b1), .gtr_inhibit(gtr_inhibit),
        .demo(demo2_active), .kill(kill_all),
        .trig({6{~stop_block}} & (gtr_trig | ch_trig)), .trig_usb(gtr_trig_usb & {6{~stop_block}}), .trig_fret(gtr_trig_fret | ch_trig_fret),
        .b_on(gtr_b_on_eff), .fret_sel(gtr_fret_sel_eff), .slide_samples(gtr_slide_samples_eff),
        .slot_ratio(gtr_slot_ratio));
    guitar_voice u_guitar (
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick_gtr),
        .trig({6{~stop_block}} & (gtr_trig | ch_trig)), .mute(gtr_mute), .kill(kill_all), .fade_req(gtr_fade | ch_fade),
        .vel_sel(demo2_active ? demo2_vel :
                  {gtr_pool_vel2, gtr_pool_vel1, gtr_pool_vel0, ch_vel2, ch_vel1, ch_vel0}), // 手动：每槽字段(槽0=E2)
        .pluck_mute(demo2_active ? demo2_pluck_mute : gtr_trig_mute),
        .note_sel({gtr_pool_note2, gtr_pool_note1, gtr_pool_note0, ch_note2, ch_note1, ch_note0}), // 槽0=E2 槽1=B2 槽2=E3 槽3..5=池(A2/D3/G3/B3 动态)
        .slot_ratio(gtr_slot_ratio),
        .active(gtr_active), .data(gtr_raw), .low_note(gtr_low_note), .slot_busy(gtr_slot_busy)
    );
    // 清音增益选择打一拍再进效果链，切断 guitar_voice→guitar_fx 的长组合路径（增益切换滞后 1 采样，不可闻）
    reg [2:0] gtr_low_note_r;
    always @(posedge clk or negedge audio_reset_n)
        if (!audio_reset_n) gtr_low_note_r <= 3'd0;
        else gtr_low_note_r <= gtr_low_note;
    guitar_fx u_gtr_fx (
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick_gtr),
        .in(gtr_raw), .clear(fx_clear), .drv_sel(gtr_drv),
        .drive_idx(adc_a2), .drive_slider(gtr_drive_slider),
        .clean_note(gtr_low_note_r), .data(pcm_guitar)
    );
    // ---- 吉他混响（KEY11 触摸键或 USB F4 切换；默认旁路，不影响干声）----
    reg gtr_rev_sel;
    always @(posedge clk or negedge audio_reset_n)
        if (!audio_reset_n) gtr_rev_sel <= 1'b0;
        else begin
            if (usb_rev_req) gtr_rev_sel <= ~gtr_rev_sel;
            if (ble_rev_set) gtr_rev_sel <= ble_rev_target;
        end
    wire signed [15:0] gtr_rev_out;
    guitar_reverb u_gtr_rev (
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick_gtr),
        .in(pcm_guitar), .rev_on(gtr_rev_sel),
        .clear_req(rev_clear_req), .clear_done(gtr_rev_clear_done),
        .data(gtr_rev_out)
    );
    // 彩灯：无吉他发声=绿；吉他清音=蓝；吉他过载=紫（S2无模式色）。
    assign led_color = gtr_active ? (gtr_fx_wanted ? 2'd2 : 2'd1) : 2'd0;

    // ------------------------------------------------------------------
    // 钢琴发声通道：NOTE_SEL 0..15 与 USB 白/黑键、TTP 16键共用。
    //   白键: A=C4 S=D4 D=E4 F=F4 G=G4 H=A4 J=B4 K=C5 L=D5
    //   黑键: Z=C#4 X=D#4 C=F#4 V=G#4 B=A#4 N=C#5 M=D#5
    //   piano_trig_all[n] = TTP(同拍优先) | USB；TTP固定原八度/力度15，USB携带F1/F2力度与Home/End八度。
    //   piano_src_usb[n] 随触发进入声部；踏板释放只作用于USB-owned声部，避免杀TTP音。
    // ------------------------------------------------------------------
    wire [3:0] velp_re   = piano_src_usb[1]  ? usb_vel_eff : piano_src_ble[1]  ? ble_piano_vel[7:4]   : 4'd15;
    wire [3:0] velp_mi   = piano_src_usb[2]  ? usb_vel_eff : piano_src_ble[2]  ? ble_piano_vel[11:8]  : 4'd15;
    wire [3:0] velp_fa   = piano_src_usb[3]  ? usb_vel_eff : piano_src_ble[3]  ? ble_piano_vel[15:12] : 4'd15;
    wire [3:0] velp_sol  = piano_src_usb[4]  ? usb_vel_eff : piano_src_ble[4]  ? ble_piano_vel[19:16] : 4'd15;
    wire [3:0] velp_la   = piano_src_usb[5]  ? usb_vel_eff : piano_src_ble[5]  ? ble_piano_vel[23:20] : 4'd15;
    wire [3:0] velp_si   = piano_src_usb[6]  ? usb_vel_eff : piano_src_ble[6]  ? ble_piano_vel[27:24] : 4'd15;
    wire [3:0] velp_c5   = piano_src_usb[7]  ? usb_vel_eff : piano_src_ble[7]  ? ble_piano_vel[31:28] : 4'd15;
    wire [3:0] velp_d5   = piano_src_usb[8]  ? usb_vel_eff : piano_src_ble[8]  ? ble_piano_vel[35:32] : 4'd15;
    wire [3:0] velp_cs4  = piano_src_usb[9]  ? usb_vel_eff : piano_src_ble[9]  ? ble_piano_vel[39:36] : 4'd15;
    wire [3:0] velp_ds4  = piano_src_usb[10] ? usb_vel_eff : piano_src_ble[10] ? ble_piano_vel[43:40] : 4'd15;
    wire [3:0] velp_fs4  = piano_src_usb[11] ? usb_vel_eff : piano_src_ble[11] ? ble_piano_vel[47:44] : 4'd15;
    wire [3:0] velp_gs4  = piano_src_usb[12] ? usb_vel_eff : piano_src_ble[12] ? ble_piano_vel[51:48] : 4'd15;
    wire [3:0] velp_as4  = piano_src_usb[13] ? usb_vel_eff : piano_src_ble[13] ? ble_piano_vel[55:52] : 4'd15;
    wire [3:0] velp_cs5  = piano_src_usb[14] ? usb_vel_eff : piano_src_ble[14] ? ble_piano_vel[59:56] : 4'd15;
    wire [3:0] velp_ds5  = piano_src_usb[15] ? usb_vel_eff : piano_src_ble[15] ? ble_piano_vel[63:60] : 4'd15;
    wire [3:0] velp_modal= piano_src_usb[0]  ? usb_vel_eff : piano_src_ble[0]  ? ble_piano_vel[3:0]   : 4'd15;
    wire [1:0] octp_re = piano_src_usb[1] ? usb_trig_oct : piano_src_ble[1] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_mi = piano_src_usb[2] ? usb_trig_oct : piano_src_ble[2] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_fa = piano_src_usb[3] ? usb_trig_oct : piano_src_ble[3] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_sol = piano_src_usb[4] ? usb_trig_oct : piano_src_ble[4] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_la = piano_src_usb[5] ? usb_trig_oct : piano_src_ble[5] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_si = piano_src_usb[6] ? usb_trig_oct : piano_src_ble[6] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_c5 = piano_src_usb[7] ? usb_trig_oct : piano_src_ble[7] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_d5 = piano_src_usb[8] ? usb_trig_oct : piano_src_ble[8] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_cs4 = piano_src_usb[9] ? usb_trig_oct : piano_src_ble[9] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_ds4 = piano_src_usb[10] ? usb_trig_oct : piano_src_ble[10] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_fs4 = piano_src_usb[11] ? usb_trig_oct : piano_src_ble[11] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_gs4 = piano_src_usb[12] ? usb_trig_oct : piano_src_ble[12] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_as4 = piano_src_usb[13] ? usb_trig_oct : piano_src_ble[13] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_cs5 = piano_src_usb[14] ? usb_trig_oct : piano_src_ble[14] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_ds5 = piano_src_usb[15] ? usb_trig_oct : piano_src_ble[15] ? ble_piano_oct : 2'd1;
    wire [1:0] octp_modal = piano_src_usb[0] ? usb_trig_oct : piano_src_ble[0] ? ble_piano_oct : 2'd1;
    // 各USB钢琴声部起音锁存的力度码（供输出级缩放；见混音前的vm_*/pcm_*_v）
    wire [3:0] vlat_re, vlat_mi, vlat_fa, vlat_sol, vlat_la, vlat_si, vlat_c5, vlat_d5;
    wire [3:0] vlat_cs4, vlat_ds4, vlat_fs4, vlat_gs4, vlat_as4, vlat_cs5, vlat_ds5, vlat_modal;
    wire act_re, act_mi, act_fa, act_sol, act_la, act_si, act_modal;
    wire signed [15:0] pcm_re, pcm_mi, pcm_fa, pcm_sol, pcm_la, pcm_si, pcm_modal;
    // R4单组：NOTE_SEL 0..3共享一组64x32幅度RAM；其余声部仍独立。
    wire [63:0] g0_data; wire [3:0] g0_act; wire [15:0] g0_vel;
    piano_modal_group4_shared #(.N0(0),.N1(1),.N2(2),.N3(3)) u_piano_g0(
        .clk(clk),.rst_n(audio_reset_n),.sample_tick(sample_tick),
        .trig(piano_trig_all[3:0]),.src_usb(piano_src_usb[3:0]),.src_ble(piano_src_ble[3:0]),
        .vel({velp_fa,velp_mi,velp_re,velp_modal}),
        .octave({octp_fa,octp_mi,octp_re,octp_modal}),
        .rel_req(piano_rel_req),.rel_usb(piano_pedal_rel[3:0]),.rel_ble(ble_piano_rel[3:0]),.kill(kill_all),
        .data(g0_data),.active(g0_act),.vel_out(g0_vel));
    assign {pcm_fa,pcm_mi,pcm_re,pcm_modal} = g0_data;
    assign vlat_modal=g0_vel[3:0]; assign vlat_re=g0_vel[7:4];
    assign vlat_mi=g0_vel[11:8];   assign vlat_fa=g0_vel[15:12];
    assign act_modal=g0_act[0]; assign act_re=g0_act[1];
    assign act_mi=g0_act[2];    assign act_fa=g0_act[3];
        // KEY5：Sol 同样改用低存储合成结构（NOTE_SEL=4，参数由 G4.wav 拟合）。
        // KEY6：La 同样改用低存储合成结构（NOTE_SEL=5，参数由 A4.wav 拟合）。
        // KEY7：Si 同样改用低存储合成结构（NOTE_SEL=6，参数由 B4.wav 拟合）。
    
    // 触摸 KEY8：改为高一个八度的 Do（C5，NOTE_SEL=7，参数由 tone (52).wav 拟合）。
    // 原"真实录音起音 + DDS 尾音"参考音已归档到 archive/key8_reference（含恢复说明），
    // 归档后原录音 ROM 不参与综合、不占用片内 RAM。
    wire signed [15:0] pcm_c5;
    key_press_pulse #(.PRESS_CLKS(157500)) u_touch_key8 (
        .clk(clk), .rst_n(audio_reset_n), .key_n(~touch_keys[7]), .pulse(pulse_c5)
    );
        // 触摸 KEY9：高一个八度的 Re（D5，NOTE_SEL=8，参数由 tone (54).wav 拟合）。
    wire act_d5;
    wire signed [15:0] pcm_d5;
        // 触摸 KEY10：升 Do（C#4，NOTE_SEL=9，参数由 tone (41).wav 拟合）。
    wire act_cs4;
    wire signed [15:0] pcm_cs4;
        // 触摸 KEY11：升 Re（D#4，NOTE_SEL=10，参数由 tone (43).wav 拟合）。
    wire act_ds4;
    wire signed [15:0] pcm_ds4;
        // 触摸 KEY12：升 Fa（F#4，NOTE_SEL=11，参数由 tone (46).wav 拟合）。
    wire act_fs4;
    wire signed [15:0] pcm_fs4;
        // 触摸 KEY13：升 Sol（G#4，NOTE_SEL=12，参数由 tone (48).wav 拟合）。
    wire act_gs4;
    wire signed [15:0] pcm_gs4;
        // 触摸 KEY14：升 La（A#4，NOTE_SEL=13，参数由 tone (50).wav 拟合）。
    wire act_as4;
    wire signed [15:0] pcm_as4;
        // 触摸 KEY15：高八度升 Do（C#5，NOTE_SEL=14，参数由 tone (53).wav 拟合）。
    wire act_cs5;
    wire signed [15:0] pcm_cs5;
        // 触摸 KEY16：高八度升 Re（D#5，NOTE_SEL=15，参数由 tone (55).wav 拟合）。
    wire act_ds5;
    wire signed [15:0] pcm_ds5;
    // R4推广：NOTE_SEL 4..7 / 8..11 / 12..15 各共享一组64x32幅度RAM。
    wire [63:0] g1_data,g2_data,g3_data;
    wire [3:0] g1_act,g2_act,g3_act;
    wire [15:0] g1_vel,g2_vel,g3_vel;
    piano_modal_group4_shared #(.N0(4),.N1(5),.N2(6),.N3(7)) u_piano_g1(
        .clk(clk),.rst_n(audio_reset_n),.sample_tick(sample_tick),
        .trig(piano_trig_all[7:4]),.src_usb(piano_src_usb[7:4]),.src_ble(piano_src_ble[7:4]),
        .vel({velp_c5,velp_si,velp_la,velp_sol}),
        .octave({octp_c5,octp_si,octp_la,octp_sol}),
        .rel_req(piano_rel_req),.rel_usb(piano_pedal_rel[7:4]),.rel_ble(ble_piano_rel[7:4]),.kill(kill_all),
        .data(g1_data),.active(g1_act),.vel_out(g1_vel));
    piano_modal_group4_shared #(.N0(8),.N1(9),.N2(10),.N3(11)) u_piano_g2(
        .clk(clk),.rst_n(audio_reset_n),.sample_tick(sample_tick),
        .trig(piano_trig_all[11:8]),.src_usb(piano_src_usb[11:8]),.src_ble(piano_src_ble[11:8]),
        .vel({velp_fs4,velp_ds4,velp_cs4,velp_d5}),
        .octave({octp_fs4,octp_ds4,octp_cs4,octp_d5}),
        .rel_req(piano_rel_req),.rel_usb(piano_pedal_rel[11:8]),.rel_ble(ble_piano_rel[11:8]),.kill(kill_all),
        .data(g2_data),.active(g2_act),.vel_out(g2_vel));
    piano_modal_group4_shared #(.N0(12),.N1(13),.N2(14),.N3(15)) u_piano_g3(
        .clk(clk),.rst_n(audio_reset_n),.sample_tick(sample_tick),
        .trig(piano_trig_all[15:12]),.src_usb(piano_src_usb[15:12]),.src_ble(piano_src_ble[15:12]),
        .vel({velp_ds5,velp_cs5,velp_as4,velp_gs4}),
        .octave({octp_ds5,octp_cs5,octp_as4,octp_gs4}),
        .rel_req(piano_rel_req),.rel_usb(piano_pedal_rel[15:12]),.rel_ble(ble_piano_rel[15:12]),.kill(kill_all),
        .data(g3_data),.active(g3_act),.vel_out(g3_vel));
    assign {pcm_c5,pcm_si,pcm_la,pcm_sol}=g1_data;
    assign {pcm_fs4,pcm_ds4,pcm_cs4,pcm_d5}=g2_data;
    assign {pcm_ds5,pcm_cs5,pcm_as4,pcm_gs4}=g3_data;
    assign {vlat_c5,vlat_si,vlat_la,vlat_sol}=g1_vel;
    assign {vlat_fs4,vlat_ds4,vlat_cs4,vlat_d5}=g2_vel;
    assign {vlat_ds5,vlat_cs5,vlat_as4,vlat_gs4}=g3_vel;
    assign {act_c5,act_si,act_la,act_sol}=g1_act;
    assign {act_fs4,act_ds4,act_cs4,act_d5}=g2_act;
    assign {act_ds5,act_cs5,act_as4,act_gs4}=g3_act;
        // ★力度输出级缩放（本轮）：各USB钢琴声部按起音锁存力度码 (vel+1)/16 缩放；
    //   满档15时×16>>4恒等（与声部内部满幅逐位一致），弱/中档为整数舍入；声部内部保持原结构不扰动时序。
    //   增益为16位有符号正数（1..16），与有符号PCM相乘；不可把(vel+1)当5位有符号（16会变-16）。
    wire signed [15:0] vk_re  = $signed({12'b0,vlat_re})  + 16'sd1;  wire signed [31:0] vm_re  = pcm_re  * vk_re;   wire signed [15:0] pcm_re_v  = vm_re  >>> 4;
    wire signed [15:0] vk_mi  = $signed({12'b0,vlat_mi})  + 16'sd1;  wire signed [31:0] vm_mi  = pcm_mi  * vk_mi;   wire signed [15:0] pcm_mi_v  = vm_mi  >>> 4;
    wire signed [15:0] vk_fa  = $signed({12'b0,vlat_fa})  + 16'sd1;  wire signed [31:0] vm_fa  = pcm_fa  * vk_fa;   wire signed [15:0] pcm_fa_v  = vm_fa  >>> 4;
    wire signed [15:0] vk_sol = $signed({12'b0,vlat_sol}) + 16'sd1;  wire signed [31:0] vm_sol = pcm_sol * vk_sol;  wire signed [15:0] pcm_sol_v = vm_sol >>> 4;
    wire signed [15:0] vk_la  = $signed({12'b0,vlat_la})  + 16'sd1;  wire signed [31:0] vm_la  = pcm_la  * vk_la;   wire signed [15:0] pcm_la_v  = vm_la  >>> 4;
    wire signed [15:0] vk_si  = $signed({12'b0,vlat_si})  + 16'sd1;  wire signed [31:0] vm_si  = pcm_si  * vk_si;   wire signed [15:0] pcm_si_v  = vm_si  >>> 4;
    wire signed [15:0] vk_c5  = $signed({12'b0,vlat_c5})  + 16'sd1;  wire signed [31:0] vm_c5  = pcm_c5  * vk_c5;   wire signed [15:0] pcm_c5_v  = vm_c5  >>> 4;
    wire signed [15:0] vk_d5  = $signed({12'b0,vlat_d5})  + 16'sd1;  wire signed [31:0] vm_d5  = pcm_d5  * vk_d5;   wire signed [15:0] pcm_d5_v  = vm_d5  >>> 4;
    wire signed [15:0] vk_cs4 = $signed({12'b0,vlat_cs4}) + 16'sd1;  wire signed [31:0] vm_cs4 = pcm_cs4 * vk_cs4;  wire signed [15:0] pcm_cs4_v = vm_cs4 >>> 4;
    wire signed [15:0] vk_ds4 = $signed({12'b0,vlat_ds4}) + 16'sd1;  wire signed [31:0] vm_ds4 = pcm_ds4 * vk_ds4;  wire signed [15:0] pcm_ds4_v = vm_ds4 >>> 4;
    wire signed [15:0] vk_fs4 = $signed({12'b0,vlat_fs4}) + 16'sd1;  wire signed [31:0] vm_fs4 = pcm_fs4 * vk_fs4;  wire signed [15:0] pcm_fs4_v = vm_fs4 >>> 4;
    wire signed [15:0] vk_gs4 = $signed({12'b0,vlat_gs4}) + 16'sd1;  wire signed [31:0] vm_gs4 = pcm_gs4 * vk_gs4;  wire signed [15:0] pcm_gs4_v = vm_gs4 >>> 4;
    wire signed [15:0] vk_as4 = $signed({12'b0,vlat_as4}) + 16'sd1;  wire signed [31:0] vm_as4 = pcm_as4 * vk_as4;  wire signed [15:0] pcm_as4_v = vm_as4 >>> 4;
    wire signed [15:0] vk_cs5 = $signed({12'b0,vlat_cs5}) + 16'sd1;  wire signed [31:0] vm_cs5 = pcm_cs5 * vk_cs5;  wire signed [15:0] pcm_cs5_v = vm_cs5 >>> 4;
    wire signed [15:0] vk_ds5 = $signed({12'b0,vlat_ds5}) + 16'sd1;  wire signed [31:0] vm_ds5 = pcm_ds5 * vk_ds5;  wire signed [15:0] pcm_ds5_v = vm_ds5 >>> 4;
    wire signed [15:0] vk_mod = $signed({12'b0,vlat_modal}) + 16'sd1; wire signed [31:0] vm_mod = pcm_modal * vk_mod; wire signed [15:0] pcm_modal_v = vm_mod >>> 4;
    // ------------------------------------------------------------------
    // 混音：18 路有符号 PCM 先按 21 位符号扩展相加（最坏 18x32767=589806，
    // ---- 三音鼓（C 底鼓 / N 军鼓 / M 闭镲）：音频域触发、进主混音增益之前 ----
    reg [8:0] drum_held_d;
    wire [8:0] drum_ev = (usb_drum_held & ~drum_held_d) | ble_drum_pulse;
    reg [8:0] drum_trig;
    wire drum_ack;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin drum_held_d <= 9'd0; drum_trig <= 9'd0; end
        else begin
            drum_held_d <= usb_drum_held;
            if (drum_ack) drum_trig <= drum_ev;
            else drum_trig <= drum_trig | drum_ev;
        end
    end
    reg [3:0] ble_drum_vel_r;
    reg ble_drum_vel_hold;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ble_drum_vel_r <= 4'd15;
            ble_drum_vel_hold <= 1'b0;
        end else if (|ble_drum_pulse) begin
            ble_drum_vel_r <= ble_drum_vel;
            ble_drum_vel_hold <= 1'b1;
        end else if (drum_ack) begin
            ble_drum_vel_hold <= 1'b0;
        end
    end
    wire [3:0] drum_vel = ble_drum_vel_hold ? ble_drum_vel_r : usb_vel_eff;
    wire signed [15:0] drum_pcm;
    wire signed [15:0] kick_pcm, closed_hat_pcm;
    wire drum_active;
    drum_synth3 #(.CFG(2)) u_drum(
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick),
        .trig(drum_trig), .vel(drum_vel), .cancel(usb_esc_held | ble_all_off),
        .data(drum_pcm), .kick_pcm(kick_pcm), .hat_pcm(closed_hat_pcm),
        .active(drum_active), .ack(drum_ack));
    wire signed [15:0] snare_pcm;
    wire snare_active;
    snare_tv_engine u_snare(
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick),
        .trig(drum_trig), .vel(drum_vel), .cancel(usb_esc_held | ble_all_off),
        .data(snare_pcm), .active(snare_active), .ack());
    // 六鼓共享 ROM 子系统：4=开镲, 5=中Tom, 6=Crash, 7=高Tom, 8=低Tom, 9=Ride
    wire [5:0] six_trig = {drum_trig[7], drum_trig[6], drum_trig[4],
                           drum_trig[8], drum_trig[3], drum_trig[5]};
    wire signed [19:0] six_pcm20;
    wire signed [16:0] six_hat17;
    wire signed [21:0] six_pcm22, six_hat22;
    wire six_active;
    six_drum_synth u_six(
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick),
        .trig(six_trig), .vel(drum_vel),
        .cancel(usb_esc_held | ble_all_off),
        .pcm20(six_pcm20), .hat_pcm17(six_hat17),
        .pcm22(six_pcm22), .hat22(six_hat22), .active(six_active));
    // M 闭镲压住开镲；重新触发开镲时释放 choke。
    reg choke_hold;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) choke_hold <= 1'b0;
        else if (drum_trig[2]) choke_hold <= 1'b1;
        else if (drum_trig[3]) choke_hold <= 1'b0;
    end
    wire signed [21:0] six_out22 = (six_pcm22 - six_hat22) +
        (choke_hold ? 22'sd0 : six_hat22);
    // 21 位有符号最大 1048575，不溢出），再乘固定混音增益（Q8），最后才限幅到 16 位。
    // 硬限幅只作最终保护；单音音量与前面的混音方案保持不变。
    // 不按活动音数切换增益，无音量跳变；每个音仍用各自独立包络，互不清零。
    // ★混音增益调整位置：MIX_GAIN_Q8，256=1.0；160=0.625（当前）。
    // ------------------------------------------------------------------
    localparam signed [8:0] MIX_GAIN_Q8 = 9'sd160;
        wire signed [21:0] pcm_re22  = {{6{pcm_re_v[15]}},  pcm_re_v};
    wire signed [21:0] pcm_mi22  = {{6{pcm_mi_v[15]}},  pcm_mi_v};
    wire signed [21:0] pcm_fa22  = {{6{pcm_fa_v[15]}},  pcm_fa_v};
    wire signed [21:0] pcm_sol22 = {{6{pcm_sol_v[15]}}, pcm_sol_v};
    wire signed [21:0] pcm_la22  = {{6{pcm_la_v[15]}},  pcm_la_v};
    wire signed [21:0] pcm_si22  = {{6{pcm_si_v[15]}},  pcm_si_v};
    wire signed [21:0] pcm_mod22 = {{6{pcm_modal_v[15]}},pcm_modal_v};
    wire signed [21:0] pcm_c522  = {{6{pcm_c5_v[15]}},  pcm_c5_v};
    wire signed [21:0] pcm_d522  = {{6{pcm_d5_v[15]}},  pcm_d5_v};
    wire signed [21:0] pcm_cs422 = {{6{pcm_cs4_v[15]}}, pcm_cs4_v};
    wire signed [21:0] pcm_ds422 = {{6{pcm_ds4_v[15]}}, pcm_ds4_v};
    wire signed [21:0] pcm_fs422 = {{6{pcm_fs4_v[15]}}, pcm_fs4_v};
    wire signed [21:0] pcm_gs422 = {{6{pcm_gs4_v[15]}}, pcm_gs4_v};
    wire signed [21:0] pcm_as422 = {{6{pcm_as4_v[15]}}, pcm_as4_v};
    wire signed [21:0] pcm_cs522 = {{6{pcm_cs5_v[15]}}, pcm_cs5_v};
    wire signed [21:0] pcm_ds522 = {{6{pcm_ds5_v[15]}}, pcm_ds5_v};
    wire signed [21:0] gtr_rev22 = {{6{gtr_rev_out[15]}}, gtr_rev_out};
    wire signed [21:0] kick_ext   = {{6{kick_pcm[15]}},       kick_pcm};
    wire signed [21:0] closed_ext = {{6{closed_hat_pcm[15]}}, closed_hat_pcm};
    wire signed [21:0] snare_ext  = {{6{snare_pcm[15]}},      snare_pcm};
    wire signed [21:0] kick_gain   = kick_ext + (kick_ext >>> 1);
    wire signed [21:0] closed_gain = closed_ext + (closed_ext >>> 1) + (closed_ext >>> 2);
    wire signed [21:0] snare_gain  = snare_ext + (snare_ext >>> 1);
    wire signed [21:0] six22       = six_out22;
    reg signed [21:0] mix_pipe [0:20];
    integer mi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (mi = 0; mi < 21; mi = mi + 1) mix_pipe[mi] <= 22'sd0;
        end else begin
            mix_pipe[0]  <= pcm_re22;
            mix_pipe[1]  <= pcm_mi22;
            mix_pipe[2]  <= pcm_fa22;
            mix_pipe[3]  <= pcm_sol22;
            mix_pipe[4]  <= pcm_la22;
            mix_pipe[5]  <= pcm_si22;
            mix_pipe[6]  <= pcm_mod22;
            mix_pipe[7]  <= pcm_c522;
            mix_pipe[8]  <= pcm_d522;
            mix_pipe[9]  <= pcm_cs422;
            mix_pipe[10] <= pcm_ds422;
            mix_pipe[11] <= pcm_fs422;
            mix_pipe[12] <= pcm_gs422;
            mix_pipe[13] <= pcm_as422;
            mix_pipe[14] <= pcm_cs522;
            mix_pipe[15] <= pcm_ds522;
            mix_pipe[16] <= gtr_rev22;
            mix_pipe[17] <= kick_gain;
            mix_pipe[18] <= closed_gain;
            mix_pipe[19] <= snare_gain;
            mix_pipe[20] <= six22;
        end
    end
    wire signed [21:0] pcm_sum = mix_pipe[0] + mix_pipe[1] + mix_pipe[2] + mix_pipe[3] + mix_pipe[4] + mix_pipe[5] + mix_pipe[6] + mix_pipe[7] + mix_pipe[8] + mix_pipe[9] + mix_pipe[10] + mix_pipe[11] + mix_pipe[12] + mix_pipe[13] + mix_pipe[14] + mix_pipe[15] + mix_pipe[16] + mix_pipe[17] + mix_pipe[18] + mix_pipe[19] + mix_pipe[20];
    // 求和打一拍再乘增益：缩短多路求和→乘增益→限幅的组合路径（纯延迟，音色不变）
    reg signed [21:0] pcm_sum_r;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) pcm_sum_r <= 22'sd0;
        else pcm_sum_r <= pcm_sum;
    wire signed [30:0] pcm_gain = pcm_sum_r * MIX_GAIN_Q8; // 22位x9位=31位，宽位乘法不提前截断
    wire signed [22:0] pcm_mix  = pcm_gain >>> 8;        // Q8 定标还原
    // ★主音量（F8/F9，统一操作第四批）：插入位置=效果处理之后、最终16位饱和之前。
    //   独立流水一拍：宽位混音先寄存，再与增益(17位正数Q1.15)有符号相乘并>>>15，然后才做16位饱和；
    //   100%时与pcm_mix逐值相等（仅固定延迟1拍，已记录）；增益在sample_tick更新，DAC/VOFA共用最终PCM。
    reg signed [22:0] pcm_mix_r;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) pcm_mix_r <= 23'sd0;
        else pcm_mix_r <= pcm_mix;
    reg [1:0] song_active_sync;
    always @(posedge clk or negedge audio_reset_n)
        if (!audio_reset_n) song_active_sync <= 2'b00;
        else song_active_sync <= {song_active_sync[0], song_active};
    wire [16:0] vol_eff = song_active_sync[1] ? 17'd9919 : {1'b0, vol_gain};
    wire signed [39:0] vol_mul = pcm_mix_r * $signed({1'b0, vol_eff}); // 23位 x 17位 = 40位
    wire signed [24:0] vol_shift = vol_mul >>> 15;
    wire signed [15:0] pcm_mix16 = (vol_shift > 25'sd32767) ? 16'sd32767 :
                                   (vol_shift < -25'sd32768) ? -16'sd32768 : vol_shift[15:0];
    // 混音组合逻辑打一拍再送 DAC/VOFA：把"求和→乘增益→限幅"与 VOFA 的浮点转换
    // 拆成两级，修复关键路径；两者仍共用同一份 PCM，串口协议与帧内容不变。
    always @(posedge clk or negedge rst_n)
        if (!rst_n) pcm_sample <= 16'sd0;
        else pcm_sample <= pcm_mix16;

    // ---- 统一停止控制（Esc全局制音/钢琴Space）与最终PCM静音缩放 ----
    // panic_gain 为 0..32768 无符号Q1.15（1.0=32768不当作有符号负数）；乘积按有符号运算后算术右移15位，
    // 1.0时与 pcm_sample 逐值相同，0时精确输出0，-32768满幅不溢出。组合缩放直接接DAC/VOFA寄存器，
    // 不插入额外流水延迟（DAC与VOFA仍共用同一份处理后PCM）。
    wire voices_active = act_re | act_mi | act_fa | act_sol | act_la | act_si | act_modal | act_c5 | act_d5 | act_cs4 | act_ds4 | act_fs4 | act_gs4 | act_as4 | act_cs5 | act_ds5 | gtr_active | drum_active | snare_active | six_active;
    audio_stop_control u_stop_ctl(
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick),
        .esc(usb_esc_held), .space(usb_space_held),
        .voices_active(voices_active), .rev_clear_done(gtr_rev_clear_done),
        .vofa_frame_done(vofa_frame_done),
        .cancel_now(stop_cancel_now), .stop_block(stop_block),
        .piano_rel_req(piano_rel_req), .kill_commit(kill_commit), .fx_clear(fx_clear),
        .rev_clear_req(rev_clear_req), .panic_gain(panic_gain), .vofa_hold(vofa_hold));
    // USB总音量（F8减/F9加）：17档、按下沿一步、1024采样整数斜坡；Esc/停止同拍丢弃，Space期间允许。
    // 插入点见混音后的主音量级（效果处理之后、最终16位饱和之前）；DAC/VOFA共用最终PCM。
    usb_volume_control u_usb_volume(.clk(clk),.rst_n(audio_reset_n),.sample_tick(sample_tick),
        .connected(usb_keyboard_present),.vol_up(usb_f9),.vol_down(usb_f8),
        .req_block(stop_cancel_now | stop_block),
        .level(vol_level),.gain(vol_gain),.target(vol_target));
    // USB钢琴八度（Home降/End升）：只作用于USB手动钢琴音；TTP固定原八度。
    usb_octave_control u_usb_octave(.clk(clk),.rst_n(audio_reset_n),
        .connected(usb_keyboard_present),
        .oct_up(usb_end),.oct_down(usb_home),
        .accept(~(stop_cancel_now | stop_block)),
        .octave(oct_sel),.octave_next(oct_sel_next));
    // ---- ADC slider filter branch: inserted after mix/master volume, before final panic ----
    key_toggle #(.DEBOUNCE_CLKS(1050000)) u_filter_key(
        .clk(clk), .rst_n(audio_reset_n), .key_n(key_filter_n), .on(filter_on));
    wire [8:0] adc_a0, adc_a1, adc_a3;
    wire [3:0] adc_param_valid;
    (* keep *) wire [8:0] adc_reserved_a2;
    (* keep *) wire [8:0] adc_reserved_a3;
    (* keep *) wire adc_reserved_valid;
    adc_param_bridge u_adc_params(
        .sys_clk(sys_clk), .sys_rst_n(rst_n), .adc_scl(adc_scl), .adc_sda(adc_sda),
        .audio_clk(clk), .audio_rst_n(audio_reset_n),
        .a0_idx(adc_a0), .a1_idx(adc_a1), .a2_idx(adc_a2), .a3_idx(adc_a3),
        .param_valid(adc_param_valid), .params_ok(adc_params_ok),
        .reserved_a2(adc_reserved_a2), .reserved_a3(adc_reserved_a3),
        .reserved_valid(adc_reserved_valid));
    wire signed [15:0] pcm_filtered;
    adc_filter_audio u_adc_filter(
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick),
        .pcm_in(pcm_sample), .panic_gain(panic_gain),
        .filter_on(filter_on), .a0_idx(adc_a0), .a1_idx(adc_a1),
        .param_valid(adc_param_valid), .params_ok(adc_params_ok),
        .pcm_out(pcm_filtered));
    wire echo_clear = stop_cancel_now | kill_commit | fx_clear;
    wire signed [15:0] pcm_echoed;
    wire echo_tail_active;
    audio_echo u_echo(
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick),
        .pcm_in(pcm_filtered), .filter_on(filter_on), .params_ok(adc_params_ok),
        .a3_idx(adc_a3), .clear(echo_clear), .pcm_out(pcm_echoed),
        .tail_active(echo_tail_active));
    wire signed [32:0] pcm_panic_mul = $signed(pcm_echoed) * $signed({1'b0, panic_gain}); // 16x17位
    wire signed [15:0] pcm_out = pcm_panic_mul[30:15];                                    // 算术右移15位
    // 任一通道在发声或停止控制保持期间都打开 VOFA 数据流（含淡出/清理/终止零帧）。
    wire vofa_enable = voices_active | vofa_hold | echo_tail_active;

    audio_drive #(.BCK_HALF_DIV(17)) u_audio (
        .clk(clk), .rst_n(audio_reset_n), .idata(pcm_out),
        .req(sample_tick), .HP_BCK(HP_BCK), .HP_WS(HP_WS), .HP_DIN(HP_DIN)
    );
    // 底板功放低电平开启，高电平关闭。
    // 复位时关闭功放，DAC 运行约 100ms 后开启。
    audio_amp_control u_amp (
        .clk(clk), .rst_n(audio_reset_n), .pa_en(PA_EN)
    );
    vofa_uart u_vofa (
        .clk(clk), .rst_n(audio_reset_n), .sample_tick(sample_tick),
        .enable(vofa_enable), .pcm(pcm_out), .uart_tx_pin(vofa_tx_unused), .dropped_frames(),
        .frame_done(vofa_frame_done)
    );

    usb_visualizer u_visualizer (
        .clk(clk), .rst_n(audio_reset_n),
        .pcm(pcm_out), .sample_valid(sample_tick),
        .uart_tx(UART_TX), .frame_done(), .frame_seq(), .dropped_frames()
    );
endmodule





