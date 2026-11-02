// 低有效按键转单周期触发：按下连续稳定 2ms，释放稳定 10ms 后重新允许。
// 按下快速响应，长按不重复；释放消抖避免机械抖动造成二次发声。
// ★消抖调整位置（只调这两个参数，不影响多键）：
//   PRESS_CLKS = 按下需要连续稳定的时钟数；RELEASE_CLKS = 松开需要连续稳定的时钟数。
//   52.5MHz 下：105000=2ms、157500=3ms、525000=10ms。
//   每个键各自实例化本模块，消抖状态互不共享，支持多键同时按下。
module key_press_pulse #(
    parameter integer PRESS_CLKS=105000,
    parameter integer RELEASE_CLKS=525000
)(input clk, input rst_n, input key_n, output reg pulse);
    reg [1:0] sync;
    reg armed;
    reg [19:0] count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin sync<=2'b11; armed<=1; count<=0; pulse<=0; end
        else begin
            sync<={sync[0],key_n}; pulse<=0;
            if (armed) begin
                if (sync[1]) count<=0;
                else if (count==PRESS_CLKS-1) begin pulse<=1; armed<=0; count<=0; end
                else count<=count+1'b1;
            end else begin
                if (!sync[1]) count<=0;
                else if (count==RELEASE_CLKS-1) begin armed<=1; count<=0; end
                else count<=count+1'b1;
            end
        end
    end
endmodule
