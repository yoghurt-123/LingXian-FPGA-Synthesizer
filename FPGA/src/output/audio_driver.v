// 保留原音频驱动接口，底层串行发送交给 PT8211 模块。
// 顶层、按键、音色生成和 VOFA 的连接不变。
module audio_drive #(parameter BCK_HALF_DIV = 17)(
    input clk, input rst_n, input [15:0] idata,
    output req, output HP_BCK, output HP_WS, output HP_DIN
);
    pt8211_tx #(.BCK_HALF_DIV(BCK_HALF_DIV)) u_tx (
        .clk(clk), .rst_n(rst_n), .idata(idata), .req(req),
        .HP_BCK(HP_BCK), .HP_WS(HP_WS), .HP_DIN(HP_DIN)
    );
endmodule
