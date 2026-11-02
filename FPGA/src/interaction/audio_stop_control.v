// 统一停止控制：Esc 全局紧急制音（panic）与钢琴 Space 平滑制音的公共控制层。
// 约定：
//  - cancel_now：组合信号，仅在 Esc 有效按下沿当拍为1；供各接收模块在同拍抑制/取消（统一接收沿）。
//  - stop_block：电平信号，从 Esc 按下沿起保持到"清理完成且 Esc 松开"；期间所有输入来源禁止起音。
//  - piano_rel_req：Space 按下沿的单拍钢琴释放请求（1024采样平滑释放由各钢琴声部执行）。
//    Space 不再按模式二选一：吉他制音由 usb_guitar_keys 同拍产生，鼓自然尾音不取消。
//  - kill_commit/fx_clear/rev_clear_req：全局输出淡出到零后，对音源/效果/混响的一次性清理请求（电平）。
//  - panic_gain：0..32768 无符号 Q1.15，仅在采样边界推进，241个采样（约4.994ms）线性精确到0。
//  - vofa_hold：淡出/清理/终止零帧期间保持VOFA发送；音频为0后确认至少2整帧（覆盖在途旧帧）再允许停流。
//  - 恢复条件：清理完成且 Esc 已松开（电平判断，断连把Esc视为松开，不会卡住）；恢复时增益直接回1.0，
//    此时无待发音（新输入已被持续门控、旧按键需松开重按），不会产生爆音。
module audio_stop_control(
 input clk, input rst_n, input sample_tick,
 input esc,                 // USB Esc保持位（已在线掩码）
 input space,               // USB 空格保持位（两种乐器同时制音）
 input voices_active,       // 全部钢琴+吉他声部 active 汇总（清理完成确认）
 input rev_clear_done,      // 混响顺序清零完成
 input vofa_frame_done,     // VOFA 整帧发送完成脉冲
 output wire cancel_now,    // 组合：Esc按下沿当拍
 output wire stop_block,    // 电平：全阻断期
 output reg  piano_rel_req, // 单拍：钢琴外部释放请求
 output reg  kill_commit,   // 电平：声部/效果清理请求
 output reg  fx_clear,      // 电平：guitar_fx 历史清零
 output reg  rev_clear_req, // 电平：混响顺序清零请求
 output reg [15:0] panic_gain, // Q1.15 0..32768
 output reg  vofa_hold      // 电平：保持VOFA发送（含终止零帧）
);
 localparam S_IDLE=2'd0, S_FADE=2'd1, S_CLEAN=2'd2, S_DONE=2'd3;
 localparam [15:0] G_FULL=16'd32768;
 // 241个采样从32768精确线性到0：135/136交替（241*135+233=32768），商余数法
 localparam [9:0] FADE_DIV=10'd241;
 localparam [9:0] FADE_REM=10'd233;
 reg [1:0] st;
 reg esc_prev, space_prev;
 reg [15:0] acc;            // 余数累加 0..240
 reg [1:0] zframes;         // 清理期间收到的整帧完成数（0..3，饱和）
 wire esc_rise = esc & ~esc_prev;
 wire space_rise = space & ~space_prev;
 assign cancel_now = esc_rise;
 assign stop_block = (st != S_IDLE);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin esc_prev<=1'b0; space_prev<=1'b0; end
  else begin esc_prev<=esc; space_prev<=space; end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   st<=S_IDLE; acc<=16'd0; zframes<=2'd0;
   piano_rel_req<=1'b0; kill_commit<=1'b0; fx_clear<=1'b0; rev_clear_req<=1'b0;
   panic_gain<=G_FULL; vofa_hold<=1'b0;
  end else begin
   piano_rel_req<=1'b0;
   // 钢琴 Space：两种模式都产生一次释放请求（重复请求不抬增益由声部侧保证）；
   // 吉他制音由 usb_guitar_keys 的 space_mute 同拍触发，鼓不进入本清理。
   if(space_rise && st==S_IDLE) piano_rel_req<=1'b1;
   if(vofa_frame_done && st==S_CLEAN && zframes!=2'd3) zframes<=zframes+2'd1;
   case(st)
    S_IDLE: begin
     if(esc_rise) begin
      st<=S_FADE; acc<=16'd0; panic_gain<=G_FULL; vofa_hold<=1'b1; zframes<=2'd0;
     end
    end
    S_FADE: begin
     if(sample_tick) begin
      // 商余数步进：acc+=233；溢出则本拍减136否则减135；结束拍精确归零
      if((acc + FADE_REM) >= FADE_DIV) begin
       acc <= acc + FADE_REM - FADE_DIV;
       if(panic_gain <= 16'd136) begin
        panic_gain <= 16'd0; st<=S_CLEAN;
        kill_commit<=1'b1; fx_clear<=1'b1; rev_clear_req<=1'b1;
       end else panic_gain <= panic_gain - 16'd136;
      end else begin
       acc <= acc + FADE_REM;
       if(panic_gain <= 16'd135) begin
        panic_gain <= 16'd0; st<=S_CLEAN;
        kill_commit<=1'b1; fx_clear<=1'b1; rev_clear_req<=1'b1;
       end else panic_gain <= panic_gain - 16'd135;
      end
     end
    end
    S_CLEAN: begin
     // 声部清理完成 + 混响清零完成 + 至少2整帧（其一必为零PCM帧）确认
     if(voices_active==1'b0 && rev_clear_done==1'b1 && zframes>=2'd2) begin
      if(!esc) begin
       st<=S_IDLE; panic_gain<=G_FULL;
       kill_commit<=1'b0; fx_clear<=1'b0; rev_clear_req<=1'b0; vofa_hold<=1'b0;
      end else st<=S_DONE;
     end
    end
    S_DONE: begin
     if(!esc) begin
      st<=S_IDLE; panic_gain<=G_FULL;
      kill_commit<=1'b0; fx_clear<=1'b0; rev_clear_req<=1'b0; vofa_hold<=1'b0;
     end
    end
   endcase
  end
 end
endmodule
