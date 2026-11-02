// USB钢琴八度控制（Home=降八度 0x4A / End=升八度 0x4D）：S2模式解耦后始终作用于USB手动钢琴音。
// 三档：0=低八度 1=原八度 2=高八度；上电/复位原八度；按下沿一步、边界饱和不回绕；
// 长按/重复报告不连调；Home+End同时保持不调整、先持一键再按另一键忽略本次、松开不补发；
// 断连保持选择且重连须先松开两键（resync）；Esc/stop_block同拍取消选择（同拍音符也取消，
// 由音符模块的既有blocked门控保证）。
// 输出 octave_next 为本拍"有效选择"（组合）：同报告Home/End+新音符时，音符事件携带新音区，不是晚一拍。
module usb_octave_control(
 input clk, input rst_n,
 input connected, input oct_up, input oct_down,
 input accept,                 // 1=本拍允许处理选择（Esc同拍为0）
 output reg [1:0] octave,      // 选择状态寄存器
 output wire [1:0] octave_next // 本拍有效选择（组合）
);
 reg up_prev, down_prev, resync;
 wire up_rise   = oct_up   & ~up_prev;
 wire down_rise = oct_down & ~down_prev;
 wire up_ok   = up_rise   & connected & ~resync & accept & ~oct_down;
 wire down_ok = down_rise & connected & ~resync & accept & ~oct_up;
 assign octave_next = (up_ok   && octave != 2'd2) ? (octave + 2'd1) :
                      (down_ok && octave != 2'd0) ? (octave - 2'd1) : octave;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin octave<=2'd1; up_prev<=1'b0; down_prev<=1'b0; resync<=1'b1; end
  else begin
   up_prev<=oct_up; down_prev<=oct_down;
   if(!connected) begin
    up_prev<=1'b0; down_prev<=1'b0; resync<=1'b1;
   end else begin
    if(!oct_up && !oct_down) resync<=1'b0;
    octave<=octave_next;
   end
  end
 end
endmodule
