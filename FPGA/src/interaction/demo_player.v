// 板上演示播放器：按采样节拍从 demo_song.vh 事件表读取逐弦事件，驱动现有实时合成引擎。
// 启动：吉他模式下短按板载 KEY1（由 top 生成 start 脉冲）；长按为模式切换，不触发播放。
// 停止：触摸制音键（KEY8）或切回钢琴模式 → 立即停止发送新事件（由上层同步平滑制音）。
// 结束：最后一个事件后对池槽（3..5）短淡出→字段写回默认→通知 ctrl 复位池状态；
//       固定槽 0..2 的尾音自然衰减不干预。演奏期间手动拨弦由上层抑制，避免与事件驱动冲突。
// 事件编码 {wr,mute,vel[3:0],note[3:0],slot[2:0],time[18:0]}：wr=先写音色字段（和弦切换，忙则先淡出）
// 力度增益=(vel+1)/16（表中已折入离线固定总增益 0.45；手动演奏固定为 1.0）
module demo_player (
    input clk, input rst_n, input sample_tick,
    input start,                 // 启动脉冲（一次）
    input stop,                  // 停止请求（制音键/切回钢琴）
    input [5:0] slot_busy,       // 来自音源：槽占用
    output reg active,           // 演示进行中
    output reg [5:0] trig,
    output reg wr_en,            // 池槽字段写使能
    output reg [2:0] wr_slot,
    output reg [3:0] wr_note,
    output reg [5:0] fade_req,   // 和弦切换先短淡出
    output reg [23:0] vel_sel,   // 每槽 4 位力度（增益=(v+1)/16）
    output reg [5:0] pluck_mute, // 本次拨弦的闷音标志
    output reg mute_req,         // 启动清场的平滑制音请求（与 ctrl 合并）
    output reg pool_rst          // 结束后通知 ctrl 复位池分配状态
);
    `include "demo_song.vh"
    localparam NEV = 66;
    localparam S_IDLE = 2'd0, S_CLEAR = 2'd1, S_PLAY = 2'd2, S_DONE = 2'd3;
    reg [1:0] st;
    reg [18:0] cnt;
    reg [6:0] epv;
    reg [1:0] sub;
    reg [3:0] dsub;
    // ★事件表改BSRAM-ROM（原case函数为LUT-ROM）：同步读+预取下一拍索引；
    //   任意拍读出值=该拍epv对应事件（epv仅在S_PLAY的sub=1推进），逐拍与原组合查表一致。
    reg [31:0] ev_mem [0:127];
    initial begin
        ev_mem[0] = 32'h18000000;
        ev_mem[1] = 32'h18480184;
        ev_mem[2] = 32'h14900308;
        ev_mem[3] = 32'h54005A7A;
        ev_mem[4] = 32'h54485BFE;
        ev_mem[5] = 32'h50905D82;
        ev_mem[6] = 32'h0C9087B7;
        ev_mem[7] = 32'h104888E4;
        ev_mem[8] = 32'h10008A12;
        ev_mem[9] = 32'h4C90E230;
        ev_mem[10] = 32'h5048E35E;
        ev_mem[11] = 32'h5000E48C;
        ev_mem[12] = 32'h14010F6D;
        ev_mem[13] = 32'h144910F1;
        ev_mem[14] = 32'h10911275;
        ev_mem[15] = 32'h0C913CAA;
        ev_mem[16] = 32'h10493DD8;
        ev_mem[17] = 32'h10013F05;
        ev_mem[18] = 32'h9A1969E7;
        ev_mem[19] = 32'h99216B6B;
        ev_mem[20] = 32'h95696CEF;
        ev_mem[21] = 32'h5619C461;
        ev_mem[22] = 32'h5521C5E5;
        ev_mem[23] = 32'h5169C769;
        ev_mem[24] = 32'h0D69F19E;
        ev_mem[25] = 32'h1121F2CB;
        ev_mem[26] = 32'h1219F3F9;
        ev_mem[27] = 32'h4D6A4C17;
        ev_mem[28] = 32'h51224D45;
        ev_mem[29] = 32'h521A4E73;
        ev_mem[30] = 32'h161A7954;
        ev_mem[31] = 32'h15227AD8;
        ev_mem[32] = 32'h116A7C5C;
        ev_mem[33] = 32'h0D6AA691;
        ev_mem[34] = 32'h1122A7BF;
        ev_mem[35] = 32'h121AA8EC;
        ev_mem[36] = 32'h98DAD3CE;
        ev_mem[37] = 32'h98A2D552;
        ev_mem[38] = 32'h966AD6D6;
        ev_mem[39] = 32'h54DB2E48;
        ev_mem[40] = 32'h54A32FCC;
        ev_mem[41] = 32'h526B3150;
        ev_mem[42] = 32'h0E6B5B85;
        ev_mem[43] = 32'h10A35CB2;
        ev_mem[44] = 32'h10DB5DE0;
        ev_mem[45] = 32'h4E6BB5FF;
        ev_mem[46] = 32'h50A3B72C;
        ev_mem[47] = 32'h50DBB85A;
        ev_mem[48] = 32'h14DBE33B;
        ev_mem[49] = 32'h14A3E4BF;
        ev_mem[50] = 32'h126BE643;
        ev_mem[51] = 32'h0E6C1078;
        ev_mem[52] = 32'h10A411A6;
        ev_mem[53] = 32'h10DC12D3;
        ev_mem[54] = 32'h18043DB5;
        ev_mem[55] = 32'h184C3F39;
        ev_mem[56] = 32'h149440BD;
        ev_mem[57] = 32'h5404982F;
        ev_mem[58] = 32'h544C99B3;
        ev_mem[59] = 32'h50949B37;
        ev_mem[60] = 32'h0C94C56C;
        ev_mem[61] = 32'h104CC699;
        ev_mem[62] = 32'h1004C7C7;
        ev_mem[63] = 32'h18057A5F;
        ev_mem[64] = 32'h184D7BE3;
        ev_mem[65] = 32'h14957D67;
    end
    wire [6:0] epv_use = ((st==S_PLAY) && (sub==2'd1)) ? (epv + 1'b1) : epv;
    reg [31:0] ev_r;
    always @(posedge clk) ev_r <= ev_mem[epv_use];
    wire [31:0] ev = ev_r;
    wire [18:0] ev_t    = ev[18:0];
    wire [2:0]  ev_slot = ev[21:19];
    wire [3:0]  ev_note = ev[25:22];
    wire [3:0]  ev_vel  = ev[29:26];
    wire        ev_mute = ev[30];
    wire        ev_wr   = ev[31];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st<=S_IDLE; cnt<=19'd0; epv<=7'd0; sub<=2'd0; dsub<=4'd0; active<=1'b0;
            trig<=6'b0; wr_en<=1'b0; wr_slot<=3'd0; wr_note<=4'd0; fade_req<=6'b0;
            vel_sel<=24'hFFFFFF; pluck_mute<=6'b0; mute_req<=1'b0; pool_rst<=1'b0;
        end else begin
            trig <= 6'b0; wr_en <= 1'b0; mute_req <= 1'b0; pool_rst <= 1'b0;
            if (stop && (st != S_IDLE)) begin
                // 停止：撤销剩余事件（上层同步平滑制音；池槽淡出由音源尾音自然结束）
                st <= S_IDLE; active <= 1'b0; fade_req <= 6'b0;
                cnt <= 19'd0; epv <= 7'd0; sub <= 2'd0; dsub <= 4'd0;
            end else case (st)
                S_IDLE: begin
                    active <= 1'b0; fade_req <= 6'b0;
                    if (start) begin
                        st <= S_CLEAR; cnt <= 19'd0; epv <= 7'd0; sub <= 2'd0;
                        active <= 1'b1; mute_req <= 1'b1;   // 清场：平滑制音现有声音
                    end
                end
                S_CLEAR: begin
                    if (sample_tick) begin
                        cnt <= cnt + 1'b1;
                        if (cnt == 19'd1800) begin cnt <= 19'd0; st <= S_PLAY; end   // ≈37ms
                    end
                end
                S_PLAY: begin
                    if (sample_tick) begin
                        cnt <= cnt + 1'b1;
                        if (epv >= NEV) begin st <= S_DONE; dsub <= 4'd0; end
                        else case (sub)
                            2'd0: if (cnt >= ev_t) begin
                                      if (ev_wr && slot_busy[ev_slot]) begin
                                          fade_req[ev_slot] <= 1'b1;  // 和弦切换：旧音先淡出
                                          sub <= 2'd3;
                                      end else begin
                                          if (ev_wr) begin wr_en<=1'b1; wr_slot<=ev_slot; wr_note<=ev_note; end
                                          vel_sel[4*ev_slot +: 4] <= ev_vel;
                                          pluck_mute[ev_slot] <= ev_mute;
                                          sub <= 2'd1;
                                      end
                                  end
                            2'd1: begin trig[ev_slot] <= 1'b1; epv <= epv + 1'b1; sub <= 2'd0; end
                            2'd3: if (!slot_busy[ev_slot]) begin
                                      fade_req[ev_slot] <= 1'b0;
                                      wr_en<=1'b1; wr_slot<=ev_slot; wr_note<=ev_note;
                                      vel_sel[4*ev_slot +: 4] <= ev_vel;
                                      pluck_mute[ev_slot] <= ev_mute;
                                      sub <= 2'd1;
                                  end
                            default: sub <= 2'd0;
                        endcase
                    end
                end
                S_DONE: begin
                    case (dsub)
                        4'd0: begin fade_req <= 6'b111000; dsub <= 4'd1; end          // 池槽短淡出
                        4'd1: if (!slot_busy[5]) begin fade_req <= 6'b0; dsub <= 4'd2; end
                        4'd2: begin wr_en<=1'b1; wr_slot<=3'd3; wr_note<=4'd3; dsub<=4'd3; end
                        4'd3: begin wr_en<=1'b1; wr_slot<=3'd4; wr_note<=4'd4; dsub<=4'd4; end
                        4'd4: begin wr_en<=1'b1; wr_slot<=3'd5; wr_note<=4'd5; dsub<=4'd5; end
                        4'd5: begin pool_rst <= 1'b1; dsub <= 4'd6; end               // ctrl 池状态复位
                        default: begin active <= 1'b0; st <= S_IDLE; end
                    endcase
                end
            endcase
        end
    end
endmodule
