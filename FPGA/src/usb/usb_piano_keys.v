// USB钢琴键事件：把16位保持状态转成音频时钟域单拍触发；S2起与模式解耦，始终有效。
// 规则：
//  - 按下沿触发一次；长按、重复报告、键槽顺序变化都不重复触发（逐位边沿检测）；
//  - 松开只停止"新触发"，钢琴声部按自身包络自然衰减；
//  - 断连立即清除保持状态并进入等待：重新连上后必须看到"全部松开"才接受新触发，
//    避免重连时把键盘上报的旧按住状态当作新按下（禁止遗留/补发）；
//  - blocked（Esc全局制音/Space钢琴制音期间）：拒绝新触发，但previous继续跟踪保持状态（不补发）。
//  - octave：本报告有效八度选择（0=低 1=原 2=高），与触发脉冲同拍锁存到trig_oct，随音符事件传递。
module usb_piano_keys(
 input clk, input rst_n, input connected, input blocked,
 input [15:0] held, input [1:0] octave,
 output reg [15:0] trig, output reg [1:0] trig_oct
);
 reg [15:0] previous;
 reg resync;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin previous<=16'd0;resync<=1'b1;trig<=16'd0;trig_oct<=2'd1;end
  else begin
   trig<=16'd0;
   if(!connected) begin
    previous<=16'd0;resync<=1'b1;
   end else begin
    if(held==16'd0) resync<=1'b0;
    if(!resync && !blocked) begin
     trig<=held & ~previous;
     trig_oct<=octave;   // 同拍变档后的有效选择（与触发的边沿同一快照）
    end
    previous<=held;
   end
  end
 end
endmodule
