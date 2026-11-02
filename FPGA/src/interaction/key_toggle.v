module key_toggle #(parameter DEBOUNCE_CLKS = 524288)(
    input clk, input rst_n, input key_n, output reg enable
);
    reg [1:0] sync;
    reg [19:0] count;
    reg stable;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync <= 2'b11; count <= 20'd0; stable <= 1'b1; enable <= 1'b0;
        end else begin
            sync <= {sync[0], key_n};
            if (sync[1] == stable) count <= 20'd0;
            else if (count == DEBOUNCE_CLKS-1) begin
                count <= 20'd0;
                stable <= sync[1];
                if (!sync[1]) enable <= ~enable;
            end else count <= count + 20'd1;
        end
    end
endmodule
