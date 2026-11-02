// USB吉他演奏键：六根空弦各自单拍拨弦脉冲 + 空格制音/断连清理脉冲；S2起与模式解耦，始终有效。
// 物理HID键位（新快照独立 guitar_held）：bit0=Q bit1=W bit2=E bit3=R bit4=T bit5=Y；空格单独一位。
// 吉他音高映射（在本模块内按吉他表再映射，与钢琴/和弦分区无关）：
//   Q=E2（原请求锁存的独立位，直达槽0）；W=A2 E=D3 R=G3 T=B3 Y=E4（经原池分配器）。
// 规则：
//  - 按下沿拨弦一次；长按、重复报告、键槽重排不重复触发（逐位边沿检测）；
//  - 空格制音不区分模式：按下沿发一次 guitar mute 脉冲，使Space同时制钢琴和吉他；
//    按住期间不产生任何吉他拨弦；松开不补发（空格期间按下的键需先松开再按）；
//  - 断连：发清理脉冲（取消待执行请求并平滑收尾）；重连后须先"全部松开"
//    （含空格）才接受新拨弦，重连前的按住状态不重放；
// 本模块只产生事件，不判断声部池/音源；多键同报告时每位独立输出，由 guitar_ctrl 请求锁存并行接收。
module usb_guitar_keys(
 input clk, input rst_n,
 input connected, input blocked,
 input [5:0] held, input space,
 output reg [5:0] pluck, output reg space_mute, output reg disc_mute
);
 reg [5:0] previous;
 reg space_prev, conn_prev, resync;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   previous<=6'd0; space_prev<=1'b0; conn_prev<=1'b0; resync<=1'b1;
   pluck<=6'd0; space_mute<=1'b0; disc_mute<=1'b0;
  end else begin
   pluck<=6'd0; space_mute<=1'b0; disc_mute<=1'b0;
   conn_prev<=connected;
   if(!connected) begin
    previous<=6'd0; space_prev<=1'b0; resync<=1'b1;
    // 吉他模式下断连：取消待执行的拨弦/替换请求并平滑收尾（演示进行中由顶层过滤本脉冲）
    if(conn_prev) disc_mute<=1'b1;
   end else begin
    if(held==6'd0 && !space) resync<=1'b0;
    // Space 制音作用两种模式（钢琴平滑释放由 audio_stop_control 同时产生）。
    if(space && !space_prev) space_mute<=1'b1;
    if(!space && !space_prev && !resync && !blocked)
     pluck<=held & ~previous;
    previous<=held; space_prev<=space;
   end
  end
 end
endmodule
