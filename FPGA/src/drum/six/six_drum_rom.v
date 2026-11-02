module six_drum_rom(
    input clk,
    input [12:0] addr,
    output reg [31:0] data
);
    reg [31:0] mem [0:4095];
    initial $readmemh("src/drum/six/six_drum_params.hex", mem);
    always @(posedge clk) data <= mem[addr];
endmodule
