module ble_uart_tx #(
    parameter integer CLKS_PER_BIT = 434
)(
    input clk,
    input rst_n,
    input start,
    input [7:0] data,
    output reg tx,
    output reg busy
);
    localparam [1:0] S_IDLE = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;

    reg [1:0] state;
    reg [8:0] count;
    reg [2:0] bit_index;
    reg [7:0] shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            count <= 0;
            bit_index <= 0;
            shift <= 0;
            tx <= 1'b1;
            busy <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    busy <= 1'b0;
                    if (start) begin
                        shift <= data;
                        busy <= 1'b1;
                        tx <= 1'b0;
                        count <= 0;
                        state <= S_START;
                    end
                end
                S_START: begin
                    if (count == CLKS_PER_BIT - 1) begin
                        count <= 0;
                        bit_index <= 0;
                        tx <= shift[0];
                        shift <= {1'b0, shift[7:1]};
                        state <= S_DATA;
                    end else begin
                        count <= count + 1'b1;
                    end
                end
                S_DATA: begin
                    if (count == CLKS_PER_BIT - 1) begin
                        count <= 0;
                        if (bit_index == 3'd7) begin
                            tx <= 1'b1;
                            state <= S_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            tx <= shift[0];
                            shift <= {1'b0, shift[7:1]};
                        end
                    end else begin
                        count <= count + 1'b1;
                    end
                end
                S_STOP: begin
                    if (count == CLKS_PER_BIT - 1) begin
                        count <= 0;
                        tx <= 1'b1;
                        busy <= 1'b0;
                        state <= S_IDLE;
                    end else begin
                        count <= count + 1'b1;
                    end
                end
                default: begin
                    state <= S_IDLE;
                    tx <= 1'b1;
                    busy <= 1'b0;
                end
            endcase
        end
    end
endmodule

