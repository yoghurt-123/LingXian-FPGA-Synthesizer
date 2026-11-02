// 板载 WS2812 状态指示：绿=钢琴，蓝=吉他清音，紫=吉他过载。
// 标称时钟 52.5MHz；每位 66 周期，约 1.257us。
// 0 码高电平约 0.305us，1 码高电平约 0.800us。
module status_led (
    input clk,
    input rst_n,
    input [1:0] color_sel,   // 0=绿 1=蓝 2=紫
    output led_data
);
    // WS2812 按绿色、红色、蓝色顺序发送，每字节高位先发；数值为低亮度。
    localparam [23:0] COLOR_GREEN  = 24'h080000;   // 绿（钢琴）
    localparam [23:0] COLOR_BLUE   = 24'h00000C;   // 蓝（吉他清音）
    localparam [23:0] COLOR_PURPLE = 24'h00080C;   // 紫（吉他过载，红+蓝）
    wire [23:0] COLOR_GRB = (color_sel == 2'd1) ? COLOR_BLUE :
                            (color_sel == 2'd2) ? COLOR_PURPLE : COLOR_GREEN;
    reg [19:0] pause_count;
    reg [6:0] bit_count;
    reg [4:0] bit_index;
    reg sending;
    wire pixel_bit = COLOR_GRB[bit_index];
    assign led_data = rst_n && sending &&
                      (bit_count < (pixel_bit ? 7'd42 : 7'd16));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pause_count <= 0;
            bit_count <= 0;
            bit_index <= 23;
            sending <= 0;
        end else if (!sending) begin
            // 上电及每帧后保持低电平约 10ms，完成复位锁存并定期刷新。
            if (pause_count == 20'd524999) begin
                pause_count <= 0;
                bit_count <= 0;
                bit_index <= 23;
                sending <= 1;
            end else pause_count <= pause_count + 1'b1;
        end else if (bit_count == 7'd65) begin
            bit_count <= 0;
            if (bit_index == 0) sending <= 0;
            else bit_index <= bit_index - 1'b1;
        end else bit_count <= bit_count + 1'b1;
    end
endmodule
