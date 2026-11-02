// USB总音量控制（F8减/F9加，Keyboard页0x41/0x42）：17档（0..16，每档6.25%），上电100%。
// 规则：
//  - 按下沿调整一档，长按/重复报告不连调；边界饱和不回绕；松手保留（不沿用力度键的松手恢复）。
//  - 两键同时保持不调整；先持一键再按另一键也忽略本次；松开不补发，需重新按下。
//  - 断开连接保持目标档位（不归零不跳满）；重连后须先松开两键（resync）再接受，避免意外变档。
//  - Esc/cancel/stop_block优先、有效模式切换同拍：丢弃本次变档请求（保持位继续跟踪）；Space期间允许调整。
//  - 目标增益 Q1.15 = level*2048（0..32768；0x8000为正数）；每次变档从当前实际增益用1024采样
//    （约21.22ms）整数斜坡（商余数法）平滑到新目标，中途改目标从当前gain重新规划；无变化不重启斜坡。
module usb_volume_control(
 input clk, input rst_n, input sample_tick,
 input connected, input vol_up, input vol_down,
 input req_block,            // 组合：Esc/cancel/stop_block/有效模式切换同拍 → 丢弃本次请求
 output reg [4:0] level,     // 目标档位 0..16
 output reg [15:0] gain,     // 实际增益 Q1.15（采样边界推进）
 output reg [15:0] target    // 本次斜坡目标 = level*2048
);
 reg up_prev, down_prev, resync;
 wire up_rise   = vol_up   & ~up_prev;
 wire down_rise = vol_down & ~down_prev;
 wire up_req    = up_rise   & connected & ~resync & ~req_block & ~vol_down;  // 另一键按住时忽略本次
 wire down_req  = down_rise & connected & ~resync & ~req_block & ~vol_up;
 // 斜坡状态：dir=1上升；step/rem来自|delta|>>10 / &1023；err为余数累加
 reg dir, ramping;
 reg [10:0] step, rem, err;
 wire [4:0] lvl_n = (up_req && level!=5'd16) ? (level + 5'd1) :
                    (down_req && level!=5'd0) ? (level - 5'd1) : level;
 wire [15:0] tgt_n = {11'b0, lvl_n} * 16'd2048;
 wire lvl_chg = (lvl_n != level);
 // 斜坡推进量：step + 本拍进位（err+rem≥1024）
 wire [10:0] err_sum = err + rem;
 wire [10:0] inc = step + {10'b0, err_sum[10]};
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   level<=5'd16; gain<=16'd32768; target<=16'd32768; up_prev<=1'b0; down_prev<=1'b0; resync<=1'b1;
   dir<=1'b0; ramping<=1'b0; step<=11'd0; rem<=11'd0; err<=11'd0;
  end else begin
   up_prev<=vol_up; down_prev<=vol_down;
   if(!connected) begin
    up_prev<=1'b0; down_prev<=1'b0; resync<=1'b1;
   end else begin
    if(!vol_up && !vol_down) resync<=1'b0;
    if(lvl_chg) begin
     // 变档请求（含与sample_tick同拍）：当拍从当前gain重新规划，本拍不推进
     level   <= lvl_n;
     target  <= tgt_n;
     dir     <= (tgt_n >= gain);
     step    <= (tgt_n >= gain) ? ((tgt_n - gain) >> 10) : ((gain - tgt_n) >> 10);
     rem     <= (tgt_n >= gain) ? ((tgt_n - gain) & 16'h03FF) : ((gain - tgt_n) & 16'h03FF);  // delta&1023
     err     <= 11'd0;
     ramping <= (tgt_n != gain);
    end else if(sample_tick && ramping) begin
     if(dir) begin
      if((gain + inc) >= target) begin gain<=target; ramping<=1'b0; err<=11'd0; end
      else begin gain<=gain+inc; err<=err_sum[9:0]; end
     end else begin
      if(gain <= (target + inc)) begin gain<=target; ramping<=1'b0; err<=11'd0; end
      else begin gain<=gain-inc; err<=err_sum[9:0]; end
     end
    end
   end
  end
 end
endmodule
