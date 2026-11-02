// PT8211 串行输出：每帧左右声道各 16 位，高位先发。
// 同一份采样发送到两个声道；保持原驱动的时钟与数据时序。
// 主时钟 52.5MHz，半周期分频 17，采样率约 48.254kHz。



module pt8211_tx #(parameter BCK_HALF_DIV = 17)(
    // idata 是音色模块生成的 16 位 PCM 数字采样，不是模拟电压。
    input clk, input rst_n, input [15:0] idata,
    // HP_DIN 是实际音频数据出口，经 audio_drive、top 同名端口到 FPGA AA16，
    // 再经底板走线接到 PT8211 的 DIN（3脚），DAC 将收到的采样转换成模拟音频。
    // HP_BCK 经 Y17 接 DAC BCK（1脚）；HP_WS 经 AB17 接 DAC WS（2脚）。
    // req 是内部采样请求，不连接 DAC；三个 HP 信号共同完成串行传输。
    output req, output reg HP_BCK, output reg HP_WS, output reg HP_DIN
);
    reg [15:0] divider;
    reg [4:0] bit_index;
    // 锁存整帧采样，避免发送途中音色模块更新造成数据撕裂。
    reg [15:0] frame_sample;
    wire [4:0] next_index = bit_index + 5'd1;
    wire falling_tick = (divider == BCK_HALF_DIV-1) && HP_BCK;
    // 新帧开始时请求采样，供音色模块与 VOFA 共用。
    assign req = rst_n && falling_tick && (bit_index == 31);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            divider <= 0;
            HP_BCK <= 0;
            HP_WS <= 1;
            HP_DIN <= 0;
            bit_index <= 31;
            frame_sample <= 0;
        end else if (divider == BCK_HALF_DIV-1) begin
            divider <= 0;
            HP_BCK <= ~HP_BCK;
            // 在位时钟下降沿更新数据，DAC 在上升沿采集。
            if (HP_BCK) begin
                bit_index <= next_index;
                HP_WS <= next_index[4];
                if (bit_index == 31) begin
                    // 新帧锁存当前采样，左右声道共用，保证一帧内数据不变。
                    frame_sample <= idata;
                    // 音频输出位置①：先把当前采样最高位送到 DAC 数据线。
                    HP_DIN <= idata[15];
                end else begin
                    // 音频输出位置②：按位序输出锁存采样，最高位到最低位。
                    // 下一声道重新从第15位开始，重复同一采样。
                    HP_DIN <= frame_sample[15-next_index[3:0]];
                end
            end
        end else divider <= divider + 1'b1;
    end
endmodule


