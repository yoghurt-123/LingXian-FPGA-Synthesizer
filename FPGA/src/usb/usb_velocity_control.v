// USB手动演奏力度选择（新特殊键映射）：F1降档 / F2升档 + 左Shift临时重音。
// 规则：
//  - 三档沿用原力度码表：弱=8、中=11、强=15；上电/复位默认中档11（保持原听感）；
//  - F1/F2按下沿一步，边界饱和不回绕；长按/重复报告不连调；两键同报或另一键保持时忽略本次；
//  - 左Shift对当前档位码加2并饱和到15（重音）；保持位与音符来自同一份已提交快照；
//  - velocity 为本拍有效值（含同报告F1/F2沿）：同一报告的USB音符使用更新后的力度，不慢一拍；
//  - 断连保留档位；重连后须先松开F1/F2（resync）才接受，避免旧按住状态造成意外变档。
module usb_velocity_control(
 input clk, input rst_n, input connected,
 input f_down, input f_up, input lshift,
 output [3:0] velocity
);
 reg [1:0] level;
 reg down_prev, up_prev, resync;
 wire down_rise = f_down & ~down_prev;
 wire up_rise   = f_up   & ~up_prev;
 wire down_ok   = down_rise & connected & ~resync & ~f_up;
 wire up_ok     = up_rise   & connected & ~resync & ~f_down;
 wire [1:0] level_next = (up_ok   && level != 2'd2) ? (level + 2'd1) :
                         (down_ok && level != 2'd0) ? (level - 2'd1) : level;
 wire [3:0] base_code = (level_next == 2'd0) ? 4'd8 :
                        (level_next == 2'd1) ? 4'd11 : 4'd15;
 wire [4:0] boosted = {1'b0, base_code} + (lshift ? 5'd2 : 5'd0);
 assign velocity = (boosted > 5'd15) ? 4'd15 : boosted[3:0];
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   level<=2'd1; down_prev<=1'b0; up_prev<=1'b0; resync<=1'b1;
  end else begin
   down_prev<=f_down; up_prev<=f_up;
   if(!connected) begin
    down_prev<=1'b0; up_prev<=1'b0; resync<=1'b1;
   end else begin
    if(!f_down && !f_up) resync<=1'b0;
    level<=level_next;
   end
  end
 end
endmodule
