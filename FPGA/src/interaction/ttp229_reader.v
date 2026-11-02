// TTP229 十六键低有效两线串行驱动，不是 I2C。
// 一轮扫描：拉低时钟后逐位读 16 位，十六位读完后 keys 才整体更新，
// 所以上层每个扫描周期看到的都是同一轮的完整按键状态，多个键可同时为 1。
// 多键识别的前提是触摸芯片工作在 Multi-Key 模式：
//   模块上 TP3、TP4 各需 1MΩ 接地（部分模块已焊好），改接后必须给模块重新上电；
//   若模块是单键模式，芯片每轮只会报告一个键，软件无法补救。
// 消抖时间在 key_press_pulse.v（PRESS_CLKS/RELEASE_CLKS），
// 扫描间隔与位宽在下面 parameter 处调整（top.v 实例可覆盖）。
module ttp229_reader #(
    parameter POWER_ON_CLKS = 31500000, // 上电等待：31500000/52.5MHz = 600ms
    parameter POLL_CLKS = 525000,       // 两轮扫描间隔：默认10ms；top.v实例用131250(2.5ms)
    parameter HALF_BIT_CLKS = 263       // 位半周期：约5us
)(
    input clk,
    input rst_n,
    input sdo,
    output reg scl,
    output reg [15:0] keys,             
    output reg keys_valid              
);
    localparam STARTUP=2'd0, IDLE=2'd1, LOW_PHASE=2'd2, HIGH_PHASE=2'd3;
    reg [1:0] state;
    reg [31:0] timer;
    reg [3:0] bit_index;
    reg [15:0] shift_keys;
    
    reg [1:0] sdo_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sdo_sync <= 2'b11;
        else sdo_sync <= {sdo_sync[0], sdo};
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=STARTUP; timer<=0; bit_index<=0;
            scl<=1; shift_keys<=0; keys<=0; keys_valid<=0;
        end else begin
            keys_valid<=0;
            case (state)
                STARTUP: begin
                    scl<=1;
                    if (timer==POWER_ON_CLKS-1) begin timer<=0; state<=IDLE; end
                    else timer<=timer+1'b1;
                end
                IDLE: begin
                    scl<=1;
                    if (timer==POLL_CLKS-1) begin
                        timer<=0; bit_index<=0; shift_keys<=0;
                        scl<=0; state<=LOW_PHASE;
                    end else timer<=timer+1'b1;
                end
                LOW_PHASE: begin
                    if (timer==HALF_BIT_CLKS-1) begin
                        shift_keys[bit_index]<=!sdo_sync[1];
                        timer<=0; scl<=1; state<=HIGH_PHASE;
                    end else timer<=timer+1'b1;
                end
                HIGH_PHASE: begin
                    if (timer==HALF_BIT_CLKS-1) begin
                        timer<=0;
                        if (bit_index==15) begin
                            keys<=shift_keys; keys_valid<=1; state<=IDLE;
                        end else begin
                            bit_index<=bit_index+1'b1; scl<=0; state<=LOW_PHASE;
                        end
                    end else timer<=timer+1'b1;
                end
                default: begin state<=STARTUP; timer<=0; scl<=1; keys<=0; end
            endcase
        end
    end
endmodule

