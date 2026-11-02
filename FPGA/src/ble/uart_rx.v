module uart_rx #(
    parameter integer CLKS_PER_BIT = 434
)(
    input clk,
    input rst_n,
    input rx,
    output reg [7:0] data,
    output reg valid,
    output reg frame_err
);
    localparam integer HALF = CLKS_PER_BIT / 2;
    localparam [1:0] S_IDLE = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;

    reg rx_meta;
    reg rx_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

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
            data <= 0;
            valid <= 0;
            frame_err <= 0;
        end else begin
            valid <= 1'b0;
            frame_err <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (!rx_sync) begin
                        state <= S_START;
                        count <= 0;
                    end
                end
                S_START: begin
                    if (count == HALF - 1) begin
                        if (!rx_sync) begin
                            state <= S_DATA;
                            count <= 0;
                            bit_index <= 0;
                        end else begin
                            state <= S_IDLE;
                            count <= 0;
                        end
                    end else begin
                        count <= count + 1'b1;
                    end
                end
                S_DATA: begin
                    if (count == CLKS_PER_BIT - 1) begin
                        count <= 0;
                        shift[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        count <= count + 1'b1;
                    end
                end
                S_STOP: begin
                    if (count == CLKS_PER_BIT - 1) begin
                        count <= 0;
                        if (rx_sync) begin
                            data <= shift;
                            valid <= 1'b1;
                        end else begin
                            frame_err <= 1'b1;
                        end
                        state <= S_IDLE;
                    end else begin
                        count <= count + 1'b1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
