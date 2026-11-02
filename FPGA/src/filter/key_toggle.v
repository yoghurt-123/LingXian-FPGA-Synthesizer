// Debounced active-low board key -> toggled effect-bypass state.
// KEY0 is used; its input is in the 1.5 V bank and has an internal pull-up.
module key_toggle #(
    parameter integer DEBOUNCE_CLKS = 1050000 // 20 ms at 52.5 MHz
)(
    input clk,
    input rst_n,
    input key_n,
    output reg on
);
    reg [1:0] sync;
    reg stable;
    reg [20:0] cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync <= 2'b11;
            stable <= 1'b1;
            cnt <= 21'd0;
            on <= 1'b0;
        end else begin
            sync <= {sync[0], key_n};
            if (sync[1] == stable) begin
                cnt <= 21'd0;
            end else if (cnt >= DEBOUNCE_CLKS - 1) begin
                cnt <= 21'd0;
                stable <= sync[1];
                if (!sync[1]) on <= ~on;
            end else begin
                cnt <= cnt + 21'd1;
            end
        end
    end
endmodule
