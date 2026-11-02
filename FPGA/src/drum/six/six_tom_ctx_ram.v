module six_tom_ctx_ram(
    input clk,
    input we,
    input [7:0] addr,
    input [31:0] wdata,
    output reg [31:0] rdata
);
    (* syn_ramstyle = "block_ram" *) reg [31:0] mem [0:255];
    // Registered write port keeps the inferred RAM placeable after the
    // single-port read-before-write mode was rejected by the fitter.
    reg we_d;
    reg [7:0] addr_d;
    reg [31:0] wdata_d;
    always @(posedge clk) begin
        rdata <= mem[addr];
        we_d <= we;
        addr_d <= addr;
        wdata_d <= wdata;
        if(we_d) mem[addr_d] <= wdata_d;
    end
endmodule
