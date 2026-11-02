// 板载 KEY1 短按/长按识别（低有效按键）：
//   按下去抖 10ms；按住到 1s 触发一次长按脉冲（只一次）；
//   松开去抖 10ms 后，若从未触发长按则给出短按脉冲。
module mode_button #(
    parameter integer DEBOUNCE_CLKS = 525000,   // ★10ms 去抖（52.5MHz）
    parameter integer LONG_CLKS     = 52500000  // ★约 1s 长按阈值
)(
    input clk, input rst_n, input key_n,
    output reg short_pulse,
    output reg long_pulse
);
    localparam S_IDLE = 2'd0, S_DOWN = 2'd1, S_UP = 2'd2;
    reg [1:0] sync;
    reg [1:0] state;
    reg [25:0] cnt;
    reg long_fired;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync <= 2'b11; state <= S_IDLE; cnt <= 0; long_fired <= 0;
            short_pulse <= 0; long_pulse <= 0;
        end else begin
            sync <= {sync[0], key_n};
            short_pulse <= 1'b0; long_pulse <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (!sync[1]) begin
                        if (cnt == DEBOUNCE_CLKS-1) begin state <= S_DOWN; cnt <= 0; long_fired <= 0; end
                        else cnt <= cnt + 1'b1;
                    end else cnt <= 0;
                end
                S_DOWN: begin
                    if (sync[1]) begin state <= S_UP; cnt <= 0; end   // 疑似松开，去抖确认
                    else if (!long_fired && cnt >= LONG_CLKS) begin
                        long_pulse <= 1'b1; long_fired <= 1'b1;       // 长按只触发一次
                    end else cnt <= cnt + 1'b1;
                end
                S_UP: begin
                    if (!sync[1]) begin state <= S_DOWN; cnt <= 0; end // 抖动，回到按下
                    else if (cnt == DEBOUNCE_CLKS-1) begin
                        state <= S_IDLE; cnt <= 0;
                        if (!long_fired) short_pulse <= 1'b1;          // 未达长按才发短按
                    end else cnt <= cnt + 1'b1;
                end
            endcase
        end
    end
endmodule
