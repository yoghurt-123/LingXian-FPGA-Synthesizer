module six_state_ram(
    input clk,
    input we,
    input [8:0] raddr,
    input [8:0] waddr,
    input [31:0] wdata,
    output reg [31:0] rdata
);
    (* syn_ramstyle = "block_ram" *) reg [31:0] mem [0:511];
    reg we_d;
    reg [8:0] waddr_d;
    reg [31:0] wdata_d;
    integer i;
    initial begin
        for (i=0;i<512;i=i+1) mem[i]=32'd0;
    end
    // Write data is registered once so the RAM has genuinely separate read
    // and write ports (Gowin SP read-before-write mode is not placeable).
    always @(posedge clk) rdata <= mem[raddr];
    always @(posedge clk) begin
        we_d <= we;
        waddr_d <= waddr;
        wdata_d <= wdata;
        if (we_d) mem[waddr_d] <= wdata_d;
    end
endmodule
