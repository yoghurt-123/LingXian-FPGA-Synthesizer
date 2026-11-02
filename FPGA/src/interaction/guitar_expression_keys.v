// 吉他表情输入：F11连奏滑音开关、PageUp/PageDown滑音时间、最小目标品位选择。
// 规则（OVERNIGHT_ADVANCEMENT_HANDOFF Stage3）：
//  - F11(0x44)按下沿切换、保持不重复；状态跨普通模式切换保留，复位关闭；断连后需先松开再按。
//  - PageUp(0x4B)/PageDown(0x4E)每次一档，20..300ms共15档（默认80ms=4档）；两键同持不调；松开不补发。
//  - 品位：顶部1..9(0x1E..0x26)、0(0x27)、减号(0x2D)=10、等号(0x2E)=11、Backspace(0x2A)=12。
//    S2模式解耦后始终在连接、非Esc同拍时接受；单个新按选中，多键同报新按全部忽略；
//    保持不重复；先持旧键再新按另一键允许新边沿选品；断连后须全松，保留档位不补发。
//  - fret_eff 为"本拍有效选择"（含同报告新按），供同一报告的拨弦请求锁存。
module guitar_expression_keys(
 input clk, input rst_n,
 input connected, input block,                  // block=Esc同拍
 input [12:0] fret_held,                        // bit i = 品位 i（0..12）
 input glide_key, input pgup, input pgdn,
 output reg [3:0] fret_sel,
 output [3:0] fret_eff,
 output reg b_on,
 output reg [4:0] time_sel,                     // 1..15档
 output reg [13:0] slide_samples                // 已按档位换算的采样数（分段启动时锁存用）
);
 // 时间档：20ms步进，N=round(ms*Fs/1000)，Fs=52500000/1088
 function [13:0] n_of; input [4:0] t; begin
  case(t)
   5'd1: n_of=14'd965;   5'd2: n_of=14'd1930;  5'd3: n_of=14'd2895;
   5'd4: n_of=14'd3860;  5'd5: n_of=14'd4825;  5'd6: n_of=14'd5790;
   5'd7: n_of=14'd6756;  5'd8: n_of=14'd7721;  5'd9: n_of=14'd8686;
   5'd10: n_of=14'd9651; 5'd11: n_of=14'd10616;5'd12: n_of=14'd11581;
   5'd13: n_of=14'd12546;5'd14: n_of=14'd13511;default: n_of=14'd14476;
  endcase
 end endfunction
 // 单个新按的索引（低位优先；多新按时不采用）
 function [3:0] first_set; input [12:0] v; integer i; begin
  first_set=4'd0;
  for(i=0;i<13;i=i+1) if(v[i]) first_set=i[3:0];
 end endfunction
 // 品位选择
 reg [12:0] fret_prev; reg fret_resync;
 wire [12:0] fret_rise = fret_held & ~fret_prev;
 wire [12:0] fret_rise_m1 = fret_rise & (fret_rise - 13'd1);
 wire new_one = (fret_rise != 13'd0) && (fret_rise_m1 == 13'd0);
 wire [3:0] new_idx = first_set(fret_rise);
 wire fret_accept = connected & ~fret_resync & ~block;
 assign fret_eff = (fret_accept && new_one) ? new_idx : fret_sel;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin fret_sel<=4'd0; fret_prev<=13'd0; fret_resync<=1'b1; end
  else begin
   fret_prev<=fret_held;
   if(!connected) begin fret_prev<=13'd0; fret_resync<=1'b1; end
   else if(fret_held==13'd0) fret_resync<=1'b0;
   if(fret_accept && new_one) fret_sel<=new_idx;
  end
 end
 // F11滑音开关
 reg glide_prev; reg glide_resync;
 wire glide_rise = glide_key & ~glide_prev;
 wire glide_accept = connected & ~glide_resync & ~block;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin b_on<=1'b0; glide_prev<=1'b0; glide_resync<=1'b1; end
  else begin
   glide_prev<=glide_key;
   if(!connected) begin glide_prev<=1'b0; glide_resync<=1'b1; end
   else if(!glide_key) glide_resync<=1'b0;
   if(glide_accept && glide_rise) b_on<=~b_on;
  end
 end
 // 时间档
 reg pu_prev,pd_prev; reg pg_resync;
 wire pu_rise = pgup & ~pu_prev;
 wire pd_rise = pgdn & ~pd_prev;
 wire pg_accept = connected & ~pg_resync & ~block;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin time_sel<=5'd4; pu_prev<=1'b0; pd_prev<=1'b0; pg_resync<=1'b1; end
  else begin
   pu_prev<=pgup; pd_prev<=pgdn;
   if(!connected) begin pu_prev<=1'b0; pd_prev<=1'b0; pg_resync<=1'b1; end
   else if(!pgup && !pgdn) pg_resync<=1'b0;
   if(pg_accept) begin
    if(pu_rise && !pgdn && time_sel!=5'd15) time_sel<=time_sel+5'd1;
    if(pd_rise && !pgup && time_sel!=5'd1) time_sel<=time_sel-5'd1;
   end
  end
 end
 always @(posedge clk) slide_samples <= n_of(time_sel);
endmodule
