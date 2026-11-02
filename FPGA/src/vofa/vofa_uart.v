// Mirror the DAC's actual PCM at every eighth audio frame, without stalling audio.
// Nominal 921052.6 baud (VOFA setting 921600), 6031.71 samples/second.
module vofa_uart #(parameter CLKS_PER_BIT=57, parameter DECIMATION=8)(
    input clk, input rst_n, input enable, input sample_tick, input signed [15:0] pcm,
    output uart_tx_pin, output reg [31:0] dropped_frames,
    output reg frame_done        // ★整帧（8字节）发送完成脉冲：供Esc清理确认终止零帧
);
    `include "vofa_protocol.vh"
    reg [15:0] decimate;
    reg [1:0] state;
    reg [63:0] frame;
    reg [2:0] byte_index;
    reg tx_start;
    reg [7:0] tx_data;
    wire tx_busy;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx(
        .clk(clk),.rst_n(rst_n),.start(tx_start),.data(tx_data),
        .tx(uart_tx_pin),.busy(tx_busy)
    );
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decimate<=0; state<=0; frame<=0; byte_index<=0;
            tx_start<=0; tx_data<=0; dropped_frames<=0; frame_done<=0;
        end else begin
            tx_start<=0;
            frame_done<=0;
            if (sample_tick) begin
                if (decimate == DECIMATION-1) decimate<=0;
                else decimate<=decimate+1'b1;
                if (decimate==0 && enable) begin
                    if (state==0) begin
                        frame<=vofa_make_frame(pcm); byte_index<=0; state<=1;
                    end else dropped_frames<=dropped_frames+1'b1;
                end
            end
            case (state)
                1: begin tx_data<=frame[7:0]; tx_start<=1; state<=2; end
                2: if (tx_busy) state<=3;
                3: if (!tx_busy) begin
                    if (byte_index==7) begin frame_done<=1; state<=0; end
                    else begin frame<=frame>>8; byte_index<=byte_index+1'b1; state<=1; end
                end
                default: begin end
            endcase
        end
    end
endmodule

