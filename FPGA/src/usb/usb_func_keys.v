// USB吉他功能键（新特殊键映射）：F3效果、F4混响、F6演示2启停。
// F5按最新范围保留为空（不分配新功能，也不参与重连resync/与F6冲突）。
// 规则：
//  - 全部为按下沿单拍请求；长按、重复报告、键槽重排不重复执行；
//  - F3/F4/F6在S2模式解耦后始终接受（仍受Esc/stop_block与空格启动约束）；F5保持无动作；
//  - Esc/stop_block优先（同拍取消请求，电平期间拒绝新请求，previous继续跟踪）；
//  - 断连清状态；重连后须先收到F3/F4/F6全部松开的真实报告才接受请求，不重放旧事件；
//  - 空格制音优先：制音期间不启动演示；
//  - F6运行的演示仍由原播放器独占吉他手动拨弦，不在这里改变音源。
module usb_func_keys(
 input clk, input rst_n,
 input connected,
 input [2:0] key,            // bit0=F3 bit1=F4 bit2=F6
 input space,
 input demo2_active,
 input cancel_now,           // Esc有效按下沿当拍
 input blocked,              // 电平：Esc制音期间
 output reg fx_req, rev_req, demo2_start, demo2_stop
);
 reg [2:0] previous;
 reg resync;
 wire [2:0] rising = key & ~previous;
 wire active = connected & ~resync;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   previous<=3'd0; resync<=1'b1;
   fx_req<=1'b0; rev_req<=1'b0; demo2_start<=1'b0; demo2_stop<=1'b0;
  end else begin
   fx_req<=1'b0; rev_req<=1'b0; demo2_start<=1'b0; demo2_stop<=1'b0;
   if(!connected) begin
    previous<=3'd0; resync<=1'b1;
   end else begin
    if(key==3'd0) resync<=1'b0;
    if(active && !blocked && !cancel_now) begin
     if(rising[0]) fx_req<=1'b1;
     if(rising[1]) rev_req<=1'b1;
     if(rising[2]) begin
      if(demo2_active) demo2_stop<=1'b1;
      else if(!space) demo2_start<=1'b1;
     end
    end
    previous<=key;
   end
  end
 end
endmodule
