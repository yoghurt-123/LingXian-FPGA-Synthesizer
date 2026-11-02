module uart_tx #(parameter CLKS_PER_BIT=57)(
    input clk, input rst_n, input start, input [7:0] data,
    output reg tx, output reg busy
);
    reg [15:0] counter;
    reg [3:0] bit_index;
    reg [9:0] shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx<=1; busy<=0; counter<=0; bit_index<=0; shift<=10'h3ff;
        end else if (!busy) begin
            tx<=1;
            if (start) begin
                shift<={1'b1,data,1'b0};
                tx<=0; busy<=1; counter<=0; bit_index<=0;
            end
        end else if (counter == CLKS_PER_BIT-1) begin
            counter<=0;
            if (bit_index==9) begin tx<=1; busy<=0; end
            else begin
                tx<=shift[1]; shift<={1'b1,shift[9:1]}; bit_index<=bit_index+1'b1;
            end
        end else counter<=counter+1'b1;
    end
endmodule
