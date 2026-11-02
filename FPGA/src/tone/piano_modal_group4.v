// R4 试验：四个钢琴声部共享一组64x32幅度RAM。
// 每个声部保留独立相位/年龄/力度/来源/包络状态；扫描按64拍时隙错开，
// 同一时刻只有一个声部访问共享RAM，读地址/写地址/写数据全部走该声部。
// fresh仍由各声部首扫描把旧幅度视为0，RAM无需物理清零；kill抑制在途写。
module piano_modal_group4 #(
 parameter N0=0, parameter N1=1, parameter N2=2, parameter N3=3
)(
 input clk, input rst_n, input sample_tick,
 input [3:0] trig, input [3:0] src_usb,
 input [15:0] vel, input [7:0] octave,
 input rel_req, input [3:0] rel_usb, input kill,
 output [63:0] data, output [3:0] active, output [15:0] vel_out
);
 (* syn_ramstyle = "block_ram" *) reg [31:0] mem[0:63];
 reg [31:0] mem_rdata;
 reg [1:0] active_v;
 reg [7:0] win_cnt;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin win_cnt<=8'd0; active_v<=2'd0; end
  else if(sample_tick) begin win_cnt<=8'd0; active_v<=2'd0; end
  else if(win_cnt==8'd63) begin win_cnt<=8'd0; active_v<=active_v+2'd1; end
  else win_cnt<=win_cnt+8'd1;
 end
 wire scan_go0 = (active_v==2'd0 && win_cnt==8'd1);
 wire scan_go1 = (active_v==2'd1 && win_cnt==8'd1);
 wire scan_go2 = (active_v==2'd2 && win_cnt==8'd1);
 wire scan_go3 = (active_v==2'd3 && win_cnt==8'd1);
 wire [3:0] raddr0,raddr1,raddr2,raddr3;
 wire [3:0] waddr0,waddr1,waddr2,waddr3;
 wire we0,we1,we2,we3;
 wire [31:0] wdata0,wdata1,wdata2,wdata3;
 piano_modal_voice_core #(.NOTE_SEL(N0)) u0(
  .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.scan_go(scan_go0),
  .trigger(trig[0]),.src_usb(src_usb[0]),.vel(vel[3:0]),.octave(octave[1:0]),
  .rel_req(rel_req),.rel_usb(rel_usb[0]),.kill(kill),
  .active(active[0]),.data(data[15:0]),.vel_out(vel_out[3:0]),
  .mem_raddr(raddr0),.mem_waddr(waddr0),.mem_we(we0),.mem_wdata(wdata0),.mem_rdata(mem_rdata));
 piano_modal_voice_core #(.NOTE_SEL(N1)) u1(
  .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.scan_go(scan_go1),
  .trigger(trig[1]),.src_usb(src_usb[1]),.vel(vel[7:4]),.octave(octave[3:2]),
  .rel_req(rel_req),.rel_usb(rel_usb[1]),.kill(kill),
  .active(active[1]),.data(data[31:16]),.vel_out(vel_out[7:4]),
  .mem_raddr(raddr1),.mem_waddr(waddr1),.mem_we(we1),.mem_wdata(wdata1),.mem_rdata(mem_rdata));
 piano_modal_voice_core #(.NOTE_SEL(N2)) u2(
  .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.scan_go(scan_go2),
  .trigger(trig[2]),.src_usb(src_usb[2]),.vel(vel[11:8]),.octave(octave[5:4]),
  .rel_req(rel_req),.rel_usb(rel_usb[2]),.kill(kill),
  .active(active[2]),.data(data[47:32]),.vel_out(vel_out[11:8]),
  .mem_raddr(raddr2),.mem_waddr(waddr2),.mem_we(we2),.mem_wdata(wdata2),.mem_rdata(mem_rdata));
 piano_modal_voice_core #(.NOTE_SEL(N3)) u3(
  .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.scan_go(scan_go3),
  .trigger(trig[3]),.src_usb(src_usb[3]),.vel(vel[15:12]),.octave(octave[7:6]),
  .rel_req(rel_req),.rel_usb(rel_usb[3]),.kill(kill),
  .active(active[3]),.data(data[63:48]),.vel_out(vel_out[15:12]),
  .mem_raddr(raddr3),.mem_waddr(waddr3),.mem_we(we3),.mem_wdata(wdata3),.mem_rdata(mem_rdata));
 wire [3:0] rd_addr = (active_v==2'd0)?raddr0:(active_v==2'd1)?raddr1:(active_v==2'd2)?raddr2:raddr3;
 always @(posedge clk) mem_rdata <= mem[{active_v,rd_addr}];
 wire wr_en = we0|we1|we2|we3;
 wire [1:0] wr_voice = we0?2'd0:we1?2'd1:we2?2'd2:2'd3;
 wire [3:0] wr_addr = we0?waddr0:we1?waddr1:we2?waddr2:waddr3;
 wire [31:0] wr_data = we0?wdata0:we1?wdata1:we2?wdata2:wdata3;
 always @(posedge clk) if(wr_en) mem[{wr_voice,wr_addr}] <= wr_data;
endmodule
