module six_noise_ctx_ram(
    input clk,
    input we,
    input [5:0] addr,
    input [31:0] wdata,
    output reg [31:0] rdata
);
    (* syn_ramstyle = "block_ram" *) reg [31:0] mem [0:63];
    reg we_d;
    reg [5:0] addr_d;
    reg [31:0] wdata_d;
    always @(posedge clk) begin
        rdata <= mem[addr];
        we_d <= we;
        addr_d <= addr;
        wdata_d <= wdata;
        if(we_d) mem[addr_d] <= wdata_d;
    end
endmodule
