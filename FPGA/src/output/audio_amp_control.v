// 板载 NS4263 功放控制：高电平关闭，低电平开启。
// 复位释放后等待约 100ms，让连续输出的 DAC 时钟先稳定。
// 这是上电时序控制，不代替板上的 DAC、模拟滤波和功放电路。
module audio_amp_control #(
    parameter integer STARTUP_CLKS = 5250000
)(
    input clk,
    input rst_n,
    output reg pa_en
);
    localparam integer COUNT_WIDTH = (STARTUP_CLKS > 1) ? $clog2(STARTUP_CLKS) : 1;
    reg [COUNT_WIDTH-1:0] count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            pa_en <= 1'b1;
        end else if (pa_en) begin
            if (count == STARTUP_CLKS-1) begin
                pa_en <= 1'b0;
            end else count <= count + 1'b1;
        end
    end
endmodule
