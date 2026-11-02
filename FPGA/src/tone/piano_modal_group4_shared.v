// Four piano voices sharing one modal datapath and one sine ROM.
// The 64-cycle slot scheduler is unchanged from piano_modal_group4.
module piano_modal_group4_shared #(
 parameter N0=0, parameter N1=1, parameter N2=2, parameter N3=3
)(
 input clk, input rst_n, input sample_tick,
 input [3:0] trig, input [3:0] src_usb, input [3:0] src_ble,
 input [15:0] vel, input [7:0] octave,
 input rel_req, input [3:0] rel_usb, input [3:0] rel_ble, input kill,
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
 wire scan_go = (win_cnt==8'd1);
 wire [3:0] mem_raddr, mem_waddr;
 wire mem_we;
 wire [31:0] mem_wdata;
 wire [1:0] mem_voice;
 wire [7:0] sine_addr;
 wire signed [15:0] sine_value;
 piano_modal_shared_core #(.N0(N0),.N1(N1),.N2(N2),.N3(N3)) u_core(
  .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
  .scan_go(scan_go),.scan_voice(active_v),
   .trig(trig),.src_usb(src_usb),.src_ble(src_ble),.vel(vel),.octave(octave),
   .rel_req(rel_req),.rel_usb(rel_usb),.rel_ble(rel_ble),.kill(kill),
  .data(data),.active(active),.vel_out(vel_out),
  .mem_raddr(mem_raddr),.mem_waddr(mem_waddr),.mem_we(mem_we),
  .mem_wdata(mem_wdata),.mem_rdata(mem_rdata),.mem_voice_o(mem_voice),
  .sine_addr_o(sine_addr),.sine_value_i(sine_value));
 sine_lut u_sine(.clk(clk),.addr(sine_addr),.data(sine_value));
 always @(posedge clk) mem_rdata <= mem[{active_v,mem_raddr}];
 always @(posedge clk) if(mem_we) mem[{mem_voice,mem_waddr}] <= mem_wdata;
endmodule

