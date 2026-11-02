// 从完整八字节报告识别A键；保持、松开、错误报告和断连沿用已验证逻辑。
module usb_a_key(input clk, input rst_n, input [1:0] typ,
 input report, input [63:0] raw, output reg held);
 integer i; reg found, rollover;
 always @* begin
  found=0; rollover=0;
  for(i=2;i<8;i=i+1) begin
   if(raw[i*8+:8]==8'h04) found=1;
   if(raw[i*8+:8]>=1 && raw[i*8+:8]<=3) rollover=1;
  end
 end
 always @(posedge clk) begin
  if(!rst_n || typ!=1) held<=0;
  else if(report && !rollover) held<=found;
 end
endmodule
