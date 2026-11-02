// 板上演示播放器 2（板载 KEY0 控制）：与 demo_player 同一逻辑，仅两处不同：
//   ①时间单位=4 个采样（四分频计数），19 位时间字段可覆盖约 43.5s；
//   ②事件索引 8 位、NEV=157（demo_song2.vh：4 小节单音 riff + 8 小节和弦 E5/G5/D5/A5）。
// 启动：吉他模式下短按板载 KEY0（top 生成 start 脉冲）；再按一次停止。
// 事件编码 {wr,mute,vel[3:0],note[3:0],slot[2:0],time[18:0]}，time 单位=4 个采样。
module demo_player2 (
    input clk, input rst_n, input sample_tick,
    input start,                 // 启动脉冲（一次）
    input stop,                  // 停止请求（KEY0 再按/制音键/切回钢琴）
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
    `include "demo_song2.vh"
    localparam NEV = 157;
    localparam S_IDLE = 2'd0, S_CLEAR = 2'd1, S_PLAY = 2'd2, S_DONE = 2'd3;
    reg [1:0] st;
    reg [18:0] cnt;              // 时间计数（单位=4 个采样）
    reg [7:0] epv;               // 事件索引（8 位，157 事件）
    reg [1:0] sub;
    reg [3:0] dsub;
    reg [1:0] tdiv;              // ★4 分频：每 4 个 sample_tick 产生一个计数节拍
    wire tick4 = sample_tick && (tdiv == 2'd3);
    // ★复位本地同步：全设计异步复位网(!audio_reset_n)扇出很大，走它进 CE/数据会拖长路径；
    //   本模块内部改用两级同步的同步复位（复位值/功能不变，仅释放晚 2 拍，演示不受影响）。
    reg [1:0] rst_sync = 2'b00;
    always @(posedge clk) rst_sync <= {rst_sync[0], rst_n};
    wire rst_n_s = rst_sync[1];
    // ★事件表改BSRAM-ROM（原case函数为LUT-ROM）：同步读+预取下一拍索引；
    //   任意拍读出值=该拍epv对应事件（epv仅在S_PLAY的sub=1推进），逐拍与原组合查表一致。
    reg [31:0] ev_mem [0:255];
    initial begin
        ev_mem[0] = 32'hB8180000;
        ev_mem[1] = 32'h7018169E;
        ev_mem[2] = 32'hB21821EE;
        ev_mem[3] = 32'hF0182D3D;
        ev_mem[4] = 32'hB0D843DB;
        ev_mem[5] = 32'hB8185A7A;
        ev_mem[6] = 32'h70187118;
        ev_mem[7] = 32'hB2187C67;
        ev_mem[8] = 32'hB05887B7;
        ev_mem[9] = 32'hF0D89E55;
        ev_mem[10] = 32'hB818B4F4;
        ev_mem[11] = 32'h7018CB92;
        ev_mem[12] = 32'hB218D6E1;
        ev_mem[13] = 32'hF018E230;
        ev_mem[14] = 32'hB0D8F8CF;
        ev_mem[15] = 32'hB8590F6D;
        ev_mem[16] = 32'hF0D9260C;
        ev_mem[17] = 32'hB219315B;
        ev_mem[18] = 32'hF0193CAA;
        ev_mem[19] = 32'h180169E7;
        ev_mem[20] = 32'h18496A48;
        ev_mem[21] = 32'h14916AA9;
        ev_mem[22] = 32'h54018086;
        ev_mem[23] = 32'h544980E7;
        ev_mem[24] = 32'h50918148;
        ev_mem[25] = 32'h0C918BD5;
        ev_mem[26] = 32'h10498C20;
        ev_mem[27] = 32'h10018C6C;
        ev_mem[28] = 32'h4C91A273;
        ev_mem[29] = 32'h5049A2BF;
        ev_mem[30] = 32'h5001A30A;
        ev_mem[31] = 32'h1401ADC2;
        ev_mem[32] = 32'h1449AE23;
        ev_mem[33] = 32'h1091AE84;
        ev_mem[34] = 32'h0C91B912;
        ev_mem[35] = 32'h1049B95D;
        ev_mem[36] = 32'h1001B9A8;
        ev_mem[37] = 32'h9A19C461;
        ev_mem[38] = 32'h9921C4C2;
        ev_mem[39] = 32'h9569C523;
        ev_mem[40] = 32'h5619DAFF;
        ev_mem[41] = 32'h5521DB60;
        ev_mem[42] = 32'h5169DBC1;
        ev_mem[43] = 32'h0D69E64E;
        ev_mem[44] = 32'h1121E69A;
        ev_mem[45] = 32'h1219E6E5;
        ev_mem[46] = 32'h4D69FCED;
        ev_mem[47] = 32'h5121FD38;
        ev_mem[48] = 32'h5219FD84;
        ev_mem[49] = 32'h161A083C;
        ev_mem[50] = 32'h1522089D;
        ev_mem[51] = 32'h116A08FE;
        ev_mem[52] = 32'h0D6A138B;
        ev_mem[53] = 32'h112213D7;
        ev_mem[54] = 32'h121A1422;
        ev_mem[55] = 32'h991A1EDB;
        ev_mem[56] = 32'h9A621F3C;
        ev_mem[57] = 32'h96AA1F9D;
        ev_mem[58] = 32'h551A3579;
        ev_mem[59] = 32'h566235DA;
        ev_mem[60] = 32'h52AA363B;
        ev_mem[61] = 32'h0EAA40C8;
        ev_mem[62] = 32'h12624114;
        ev_mem[63] = 32'h111A415F;
        ev_mem[64] = 32'h4EAA5767;
        ev_mem[65] = 32'h526257B2;
        ev_mem[66] = 32'h511A57FD;
        ev_mem[67] = 32'h151A62B6;
        ev_mem[68] = 32'h16626317;
        ev_mem[69] = 32'h12AA6378;
        ev_mem[70] = 32'h0EAA6E05;
        ev_mem[71] = 32'h12626E51;
        ev_mem[72] = 32'h111A6E9C;
        ev_mem[73] = 32'h98DA7954;
        ev_mem[74] = 32'h98A279B5;
        ev_mem[75] = 32'h966A7A16;
        ev_mem[76] = 32'h54DA8FF3;
        ev_mem[77] = 32'h54A29054;
        ev_mem[78] = 32'h526A90B5;
        ev_mem[79] = 32'h0E6A9B42;
        ev_mem[80] = 32'h10A29B8D;
        ev_mem[81] = 32'h10DA9BD9;
        ev_mem[82] = 32'h4E6AB1E0;
        ev_mem[83] = 32'h50A2B22C;
        ev_mem[84] = 32'h50DAB277;
        ev_mem[85] = 32'h14DABD30;
        ev_mem[86] = 32'h14A2BD91;
        ev_mem[87] = 32'h126ABDF2;
        ev_mem[88] = 32'h0E6AC87F;
        ev_mem[89] = 32'h10A2C8CA;
        ev_mem[90] = 32'h10DAC916;
        ev_mem[91] = 32'h1802D3CE;
        ev_mem[92] = 32'h184AD42F;
        ev_mem[93] = 32'h1492D490;
        ev_mem[94] = 32'h5402EA6D;
        ev_mem[95] = 32'h544AEACE;
        ev_mem[96] = 32'h5092EB2F;
        ev_mem[97] = 32'h0C92F5BC;
        ev_mem[98] = 32'h104AF607;
        ev_mem[99] = 32'h1002F653;
        ev_mem[100] = 32'h4C930C5A;
        ev_mem[101] = 32'h504B0CA6;
        ev_mem[102] = 32'h50030CF1;
        ev_mem[103] = 32'h140317A9;
        ev_mem[104] = 32'h144B180A;
        ev_mem[105] = 32'h1093186B;
        ev_mem[106] = 32'h0C9322F9;
        ev_mem[107] = 32'h104B2344;
        ev_mem[108] = 32'h1003238F;
        ev_mem[109] = 32'h9A1B2E48;
        ev_mem[110] = 32'h99232EA9;
        ev_mem[111] = 32'h956B2F0A;
        ev_mem[112] = 32'h561B44E6;
        ev_mem[113] = 32'h55234547;
        ev_mem[114] = 32'h516B45A8;
        ev_mem[115] = 32'h0D6B5036;
        ev_mem[116] = 32'h11235081;
        ev_mem[117] = 32'h121B50CC;
        ev_mem[118] = 32'h4D6B66D4;
        ev_mem[119] = 32'h5123671F;
        ev_mem[120] = 32'h521B676B;
        ev_mem[121] = 32'h161B7223;
        ev_mem[122] = 32'h15237284;
        ev_mem[123] = 32'h116B72E5;
        ev_mem[124] = 32'h0D6B7D72;
        ev_mem[125] = 32'h11237DBE;
        ev_mem[126] = 32'h121B7E09;
        ev_mem[127] = 32'h991B88C2;
        ev_mem[128] = 32'h9A638923;
        ev_mem[129] = 32'h96AB8984;
        ev_mem[130] = 32'h551B9F60;
        ev_mem[131] = 32'h56639FC1;
        ev_mem[132] = 32'h52ABA022;
        ev_mem[133] = 32'h0EABAAAF;
        ev_mem[134] = 32'h1263AAFB;
        ev_mem[135] = 32'h111BAB46;
        ev_mem[136] = 32'h4EABC14E;
        ev_mem[137] = 32'h5263C199;
        ev_mem[138] = 32'h511BC1E5;
        ev_mem[139] = 32'h151BCC9D;
        ev_mem[140] = 32'h1663CCFE;
        ev_mem[141] = 32'h12ABCD5F;
        ev_mem[142] = 32'h0EABD7EC;
        ev_mem[143] = 32'h1263D838;
        ev_mem[144] = 32'h111BD883;
        ev_mem[145] = 32'h1803E33B;
        ev_mem[146] = 32'h184BE39C;
        ev_mem[147] = 32'h1493E3FD;
        ev_mem[148] = 32'h5403F9DA;
        ev_mem[149] = 32'h544BFA3B;
        ev_mem[150] = 32'h5093FA9C;
        ev_mem[151] = 32'h0C940529;
        ev_mem[152] = 32'h104C0574;
        ev_mem[153] = 32'h100405C0;
        ev_mem[154] = 32'h18043266;
        ev_mem[155] = 32'h184C32C7;
        ev_mem[156] = 32'h14943328;
    end
    wire [7:0] epv_use = ((st==S_PLAY) && (sub==2'd1)) ? (epv + 1'b1) : epv;
    reg [31:0] ev_r;
    always @(posedge clk) ev_r <= ev_mem[epv_use];
    wire [31:0] ev = ev_r;
    wire [18:0] ev_t    = ev[18:0];
    wire [2:0]  ev_slot = ev[21:19];
    wire [3:0]  ev_note = ev[25:22];
    wire [3:0]  ev_vel  = ev[29:26];
    wire        ev_mute = ev[30];
    wire        ev_wr   = ev[31];
    always @(posedge clk) begin
        if (!rst_n_s) tdiv <= 2'd0;
        else if (sample_tick) tdiv <= tdiv + 2'd1;
    end
    always @(posedge clk) begin
        if (!rst_n_s) begin
            st<=S_IDLE; cnt<=19'd0; epv<=8'd0; sub<=2'd0; dsub<=4'd0; active<=1'b0;
            trig<=6'b0; wr_en<=1'b0; wr_slot<=3'd0; wr_note<=4'd0; fade_req<=6'b0;
            vel_sel<=24'hFFFFFF; pluck_mute<=6'b0; mute_req<=1'b0; pool_rst<=1'b0;
        end else begin
            trig <= 6'b0; wr_en <= 1'b0; mute_req <= 1'b0; pool_rst <= 1'b0;
            if (stop && (st != S_IDLE)) begin
                st <= S_IDLE; active <= 1'b0; fade_req <= 6'b0;
                cnt <= 19'd0; epv <= 8'd0; sub <= 2'd0; dsub <= 4'd0;
            end else case (st)
                S_IDLE: begin
                    active <= 1'b0; fade_req <= 6'b0;
                    if (start) begin
                        st <= S_CLEAR; cnt <= 19'd0; epv <= 8'd0; sub <= 2'd0;
                        active <= 1'b1; mute_req <= 1'b1;   // 清场：平滑制音现有声音
                    end
                end
                S_CLEAR: begin
                    if (tick4) begin
                        cnt <= cnt + 1'b1;
                        if (cnt == 19'd449) begin cnt <= 19'd0; st <= S_PLAY; end   // 450 单位≈37ms
                    end
                end
                S_PLAY: begin
                    if (tick4) begin
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
