// [已停用] 旧混合字段快照：旧 held 同时承载钢琴/吉他，顶层已改用 usb_zones_snapshot 的独立分区字段。
// 本文件保留仅作历史/备份参考，不在 audio_tone.gprj 中，禁止新代码实例化。
// 完整HID报告解码：钢琴16键保持位 + 空格位 + 功能键F1~F6位；请求/确认握手传稳定快照，禁止逐位独立同步。
// 六个普通键槽全部扫描；"映射16键"不代表键盘能同时上报16键（Boot键盘通常最多6键）。
// 位序与主工程 NOTE_SEL 一一对应，便于直接接到各钢琴实例：
//   bit0=C4(A) bit1=D4(S) bit2=E4(D) bit3=F4(F) bit4=G4(G) bit5=A4(H) bit6=B4(J)
//   bit7=C5(K) bit8=D5(L) bit9=C#4(W) bit10=D#4(E) bit11=F#4(T) bit12=G#4(Y)
//   bit13=A#4(U) bit14=C#5(O) bit15=D#5(P)
// 空格(0x2C)单独一位 space_held：仅吉他模式用作全局制音，钢琴模式不响应。
// 功能键 F1~F6(0x3A~0x3F) 单独六位 f_held：由 usb_func_keys 映射到指定模式/效果/混响/演示启停。
// Esc(0x29)单独一位 esc_held：全局紧急制音（两种模式都响应，不由本模块做模式门控）。
// 力度修饰：小键盘1/2/3(0x59/0x5A/0x5B)三位 kp_held[2:0] + 左Shift（modifier字节bit1）一位 lshift；
//   与音符同一份已提交握手快照一起传递，音域内组合计算有效力度，不做独立同步。
// 总音量键 F8(0x41)/F9(0x42) 两位 vol_down_held/vol_up_held：同一快照传递，音频域检测按下沿。
// 钢琴八度键 Z(0x1D)降/X(0x1B)升 两位 oct_down_held/oct_up_held：同一快照传递，仅钢琴USB手动音使用。
// 吉他弯音键：左箭头(0x50)/右箭头(0x4F) 两位 bend_left_held/bend_right_held，同一快照传递，仅吉他主奏使用。
// 吉他颤音键 V(0x19) 一位 vib_held：同一快照传递，仅吉他主奏使用（按住开启，松开撤去）。
// Stage3：B(0x05)滑音开关、PageUp(0x4B)/PageDown(0x4E)时间、顶部品位1..9/0/-/=/Backspace 共13位，同一快照传递。
// 左Ctrl(modifier byte0 bit0)：吉他掌根闷音修饰，随整份报告原子跨域。
// 吉他六键（A/S/D/F/G/H）复用 bit0..5 的物理保持位，由 usb_guitar_keys 按吉他音高表再映射。
module usb_key_snapshot(
 input usb_clk, input audio_clk, input rst_n, input ready,
 input [1:0] typ, input report, input [63:0] raw,
 output reg [15:0] held, output reg space_held, output reg [5:0] f_held, output reg esc_held,
 output reg [2:0] kp_held, output reg lshift, output reg vol_down_held, output reg vol_up_held,
 output reg oct_down_held, output reg oct_up_held, output reg bend_left_held, output reg bend_right_held, output reg vib_held,
 output reg [12:0] fret_held, output reg b_held, output reg pgup_held, output reg pgdn_held, output reg lctrl_held, output reg q_held, output reg r_held, output reg f7_held, output reg [8:0] drum_held, output reg connected
);
 reg [63:0] decoded; reg invalid; integer i;
 always @* begin
  decoded=0; invalid=0;
  if(raw[1])decoded[27]=1; // 左Shift（modifier字节 bit1，不占普通键槽）
  if(raw[0])decoded[51]=1; // 左Ctrl（modifier字节 bit0，吉他掌根闷音）
  for(i=2;i<8;i=i+1) begin
   case(raw[i*8+:8])
    8'h04:decoded[0]=1;   // C4  A
    8'h16:decoded[1]=1;   // D4  S
    8'h07:decoded[2]=1;   // E4  D
    8'h09:decoded[3]=1;   // F4  F
    8'h0a:decoded[4]=1;   // G4  G
    8'h0b:decoded[5]=1;   // A4  H
    8'h0d:decoded[6]=1;   // B4  J
    8'h0e:decoded[7]=1;   // C5  K
    8'h0f:decoded[8]=1;   // D5  L
    8'h1a:decoded[9]=1;   // C#4 W
    8'h08:decoded[10]=1;  // D#4 E
    8'h17:decoded[11]=1;  // F#4 T
    8'h1c:decoded[12]=1;  // G#4 Y
    8'h18:decoded[13]=1;  // A#4 U
    8'h12:decoded[14]=1;  // C#5 O
    8'h13:decoded[15]=1;  // D#5 P
    8'h2c:decoded[16]=1;  // 空格（吉他模式制音）
    8'h3a:decoded[17]=1;  // F1 指定钢琴
    8'h3b:decoded[18]=1;  // F2 指定吉他
    8'h3c:decoded[19]=1;  // F3 清音/过载
    8'h3d:decoded[20]=1;  // F4 混响
    8'h3e:decoded[21]=1;  // F5 演示1启停
    8'h3f:decoded[22]=1;  // F6 演示2启停
    8'h29:decoded[23]=1;  // Esc 全局制音
    8'h59:decoded[24]=1;  // 小键盘1 弱档
    8'h5a:decoded[25]=1;  // 小键盘2 中档
    8'h5b:decoded[26]=1;  // 小键盘3 强档
    8'h41:decoded[28]=1;  // F8 总音量减
    8'h42:decoded[29]=1;  // F9 总音量加
    8'h1d:decoded[30]=1;  // Z 钢琴降八度
    8'h1b:decoded[31]=1;  // X 钢琴升八度
    8'h19:decoded[34]=1;  // V 吉他颤音保持
    8'h05:decoded[35]=1;  // B 连奏滑音开关
  8'h14:decoded[52]=1;  // Q 和弦预设（吉他模式；钢琴模式无功能）
  8'h15:decoded[53]=1;  // R 和弦预设（吉他模式）
  8'h40:decoded[54]=1;  // F7 钢琴踏板模式切换（上电关闭）
     8'h06:decoded[55]=1;  // C kick
     8'h11:decoded[56]=1;  // N snare
     8'h10:decoded[57]=1;  // M hat closed
     8'h2f:decoded[58]=1;  // [ crash
     8'h36:decoded[59]=1;  // , hat open
     8'h37:decoded[60]=1;  // . tom mid
     8'h0c:decoded[61]=1;  // I tom high
     8'h38:decoded[62]=1;  // / tom low
     8'h30:decoded[63]=1;  // ] ride
    8'h4b:decoded[36]=1;  // PageUp 滑音时间+
    8'h4e:decoded[37]=1;  // PageDown 滑音时间-
    8'h27:decoded[38]=1;  // 0 品
    8'h1e:decoded[39]=1;  // 1 品
    8'h1f:decoded[40]=1;  // 2 品
    8'h20:decoded[41]=1;  // 3 品
    8'h21:decoded[42]=1;  // 4 品
    8'h22:decoded[43]=1;  // 5 品
    8'h23:decoded[44]=1;  // 6 品
    8'h24:decoded[45]=1;  // 7 品
    8'h25:decoded[46]=1;  // 8 品
    8'h26:decoded[47]=1;  // 9 品
    8'h2d:decoded[48]=1;  // 减号 10品
    8'h2e:decoded[49]=1;  // 等号 11品
    8'h2a:decoded[50]=1;  // Backspace 12品
    8'h4f:decoded[32]=1;  // 右箭头 吉他弯音+2半音
    8'h50:decoded[33]=1;  // 左箭头 吉他弯音-2半音
    8'h01,8'h02,8'h03:invalid=1;
   endcase
  end
 end
 reg [64:0] latest,payload;
 reg request,ack;
 reg [1:0] ack_sync,request_sync;
 // 无效溢出报告保留上一保持状态（不产生新事件）；断连始终清空；空报告表示全部松开。
 // 连接状态只随"真实有效报告"建立：重连后在收到第一份报告前不冒充"全部松开"，
 // 这样按住键重连时下游 resync 会等真实松开报告，不会把旧按住状态当新按下重放。
 always @(posedge usb_clk or negedge rst_n) begin
  if(!rst_n) begin latest<=0;payload<=0;request<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};
   if(!ready || typ!=1) latest<=0;
   else if(report && !invalid) latest<={1'b1,decoded};
   // payload从请求发出至确认返回保持不变，接收域看到同步请求后才采样。
   if(request==ack_sync[1] && payload!=latest) begin payload<=latest;request<=~request;end
  end
 end
 always @(posedge audio_clk or negedge rst_n) begin
  if(!rst_n) begin request_sync<=0;ack<=0;held<=0;space_held<=0;f_held<=0;esc_held<=0;kp_held<=0;lshift<=0;vol_down_held<=0;vol_up_held<=0;oct_down_held<=0;oct_up_held<=0;bend_left_held<=0;bend_right_held<=0;vib_held<=0;fret_held<=0;b_held<=0;pgup_held<=0;pgdn_held<=0;lctrl_held<=0;q_held<=0;r_held<=0;f7_held<=0;drum_held<=0;connected<=0;end
  else begin
   request_sync<={request_sync[0],request};
   if(request_sync[1]!=ack) begin
    {connected,drum_held,f7_held,r_held,q_held,lctrl_held,fret_held,pgdn_held,pgup_held,b_held,vib_held,bend_left_held,bend_right_held,oct_up_held,oct_down_held,vol_up_held,vol_down_held,lshift,kp_held,esc_held,f_held,space_held,held}<=payload;ack<=request_sync[1];
   end
  end
 end
endmodule
