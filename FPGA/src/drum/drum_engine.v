// 单底鼓引擎（修复版）：每采样严格一次更新；显式 IDLE/M/N1/N2/SUM/DONE 调度；
// 24×24→48位包络乘积、32×24→56位音高乘积；噪声全程 signed、足宽乘积与算术右移；
// 力度(vel+1) 5位；重触发先 48 采样快速释放再起音；Esc 平滑快速释放并清待触发。
// 参数唯一来源：drum_params.vh（由 experiments/drum_model 拟合换算）。test_cfg: bit0=带1, bit1=带2（0=仅模态，3=全部）。
module drum_engine (
    input clk, input rst_n, input sample_tick,
    input trig, input [3:0] vel, input cancel,
    input [1:0] test_cfg,
    output reg signed [15:0] data,
    output reg active,
    output reg [15:0] clip_count
);
    `include "tone/drum_params.vh"
    localparam [1:0] S_IDLE=2'd0, S_MODE=2'd1, S_N1=2'd2, S_N2=2'd3;
    localparam [2:0] S_SUM=3'd4, S_DONE=3'd5;
    reg [2:0] st;
    reg trig_pend;
    reg [3:0] vel_lat;
    reg [31:0] ph, dlt, ph2, ph3;
    reg [23:0] am, an1, an2, am2, am3;
    reg [31:0] ls;
    reg signed [31:0] hx1, hy1, ly1, hx2, hy2, ly2;
    reg signed [31:0] mix;          // 本帧累加
    reg signed [31:0] sv;           // 正弦读数
    reg signed [47:0] pm;           // 包络乘积
    reg [55:0] pp;                  // 音高乘积
    reg signed [47:0] pn1, pn2;     // 噪声乘积
    reg signed [31:0] wn;
    reg [6:0] rel;                  // 快速释放剩余（重触发/取消）
    reg retrig_pend;
    reg fast;                       // 快速衰减标志
    wire [7:0] saddr = ph[31:24];
    wire [7:0] saddr2 = ph2[31:24];
    wire [7:0] saddr3 = ph3[31:24];
    wire [32:0] stp = K_STEPT + dlt;
    reg start_pend; reg [3:0] start_vel;
    wire [31:0] ls_n = {ls[30:0], ls[31]^ls[21]^ls[1]^ls[0]};
    wire signed [31:0] wn_n = $signed(ls_n[15:0]);
    wire signed [36:0] vel_s = (mix * $signed({1'b0, vel_lat + 5'd1})) >>> 4;
    wire signed [15:0] sval;
    wire signed [15:0] sval2 = sval;   // 临时：共享单正弦表（正式移植时改为分时读三次）
    wire signed [15:0] sval3 = sval;
    sine_lut u_sine(.clk(clk), .addr(saddr), .data(sval));
    // 有符号扩位
    wire signed [31:0] ahp1s = {16'b0, K_N1_AHP};
    wire signed [31:0] blp1s = {16'b0, K_N1_BLP};
    wire signed [31:0] ahp2s = {16'b0, K_CLICK_AHP};
    wire signed [31:0] blp2s = {16'b0, K_CLICK_BLP};
    wire signed [47:0] p_hp1 = ahp1s * (hy1 + wn_n - hx1);
    wire signed [47:0] p_lp1 = blp1s * (hy1 - ly1);
    wire signed [47:0] p_hp2 = ahp2s * (hy2 + wn_n - hx2);
    wire signed [47:0] p_lp2 = blp2s * (hy2 - ly2);
    wire signed [31:0] hp1 = p_hp1 >>> 16;
    wire signed [31:0] hp2 = p_hp2 >>> 16;
    wire signed [31:0] lp1n = ly1 + (p_lp1 >>> 16);
    wire signed [31:0] lp2n = ly2 + (p_lp2 >>> 16);
    wire [23:0] code_m  = fast ? 24'd262144 : K_MODECODE;   // 快速衰减码
    wire [23:0] code_n1 = fast ? 24'd262144 : K_N1CODE;
    wire [23:0] code_n2 = fast ? 24'd262144 : K_CLICKCODE;
    wire signed [47:0] pm_full = (am * code_m);
    wire signed [47:0] pn1_full = (an1 * code_n1);
    wire signed [47:0] pn2_full = (an2 * code_n2);
    wire [55:0] pp_full = ({24'd0, dlt} * K_RP);
    // 单帧数据
    wire signed [31:0] mode_v = (sv * $signed({1'b0, am[23:8]})) >>> 16;
    wire signed [31:0] n1_v = (lp1n * $signed({1'b0, an1[23:8]})) >>> 16;
    wire signed [31:0] n2_v = (lp2n * $signed({1'b0, an2[23:8]})) >>> 15;
    wire signed [31:0] mode2_v = (sval2 * $signed({1'b0, am2[23:8]})) >>> 16;
    wire signed [31:0] mode3_v = (sval3 * $signed({1'b0, am3[23:8]})) >>> 16;
    wire signed [31:0] sum_frame = mix;
    wire [4:0] vel_g = {1'b0, vel_lat} + 5'd1;
    wire signed [36:0] vel_p = sum_frame * $signed({1'b0, vel_g});
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st<=S_IDLE; trig_pend<=0; vel_lat<=0; ph<=0; ph2<=0; ph3<=0; dlt<=0; am<=0; am2<=0; am3<=0; an1<=0; an2<=0; ls<=32'h1234567; start_pend<=0; start_vel<=0;
            hx1<=0; hy1<=0; ly1<=0; hx2<=0; hy2<=0; ly2<=0; mix<=0; sv<=0; pm<=0; pp<=0; pn1<=0; pn2<=0; wn<=0;
            rel<=0; retrig_pend<=0; fast<=0; data<=0; active<=0; clip_count<=0;
        end else begin
            if (trig) trig_pend <= 1'b1;
            if (cancel) begin
                trig_pend <= 0; retrig_pend <= 0; start_pend <= 0;
                if (active) begin fast <= 1'b1; rel <= 7'd512; end
            end
            case (st)
                S_IDLE: begin
                    if (sample_tick) begin
                        mix <= 0; sv <= 0;
                        if (!active) begin
                            if (trig_pend) begin
                                trig_pend <= 0;
                                ph<=0; ph2<=0; ph3<=0; dlt<=K_STEP0-K_STEPT; am<=K_MODAMP; am2<=K_MOD2AMP; am3<=K_MOD3AMP; an1<=K_N1AMP; an2<=K_CLICKAMP;
                                ls<=32'h2468ACE; hx1<=0; hy1<=0; ly1<=0; hx2<=0; hy2<=0; ly2<=0;
                                vel_lat<=vel; active<=1; fast<=0; rel<=0;
                            end
                        end else if (trig_pend && !start_pend) begin
                            // 重触发：记录新力度并快速释放48采样后起音
                            trig_pend<=0; start_pend<=1; start_vel<=vel; rel<=7'd48; fast<=1;
                        end
                        if (active || trig_pend || retrig_pend) st<=S_MODE;
                    end
                end
                S_MODE: begin
                    sv <= sval;
                    ph <= ph + stp;
                    ph2 <= ph2 + {stp[31:0],1'b0};
                    ph3 <= ph3 + stp + {stp[31:0],1'b0};
                    dlt <= pp_full[55:24];
                    am <= (am > (pm_full>>>24)) ? (am - (pm_full>>>24)) : 24'd0;
                    am2 <= (am2 > ((am2*K_MOD2CODE)>>>24)) ? (am2 - ((am2*K_MOD2CODE)>>>24)) : 24'd0;
                    am3 <= (am3 > ((am3*K_MOD3CODE)>>>24)) ? (am3 - ((am3*K_MOD3CODE)>>>24)) : 24'd0;
                    st <= S_N1;
                end
                S_N1: begin
                    ls <= ls_n;
                    wn <= wn_n;
                    hx1 <= wn_n; hy1 <= hp1; ly1 <= lp1n;
                    hx2 <= wn_n; hy2 <= hp2; ly2 <= lp2n;
                    an1 <= (an1 > (pn1_full>>>24)) ? (an1 - (pn1_full>>>24)) : 24'd0;
                    an2 <= (an2 > (pn2_full>>>24)) ? (an2 - (pn2_full>>>24)) : 24'd0;
                    st <= S_N2;
                end
                S_N2: begin
                    mix <= mode_v + mode2_v + mode3_v + (test_cfg[0] ? n1_v : 0) + (test_cfg[1] ? n2_v : 0);
                    st <= S_SUM;
                end
                S_SUM: begin
                    if (vel_s > 37'sd32767) begin data <= 16'sd32767; clip_count <= clip_count+16'd1; end
                    else if (vel_s < -37'sd32768) begin data <= -16'sd32768; clip_count <= clip_count+16'd1; end
                    else data <= vel_s[15:0];
                    if ((am < 24'd256) && (an1 < 24'd256) && (an2 < 24'd256)) active <= 0;
                    if (rel != 0) begin rel <= rel - 1'b1; if (rel == 7'd1) begin fast <= 0;
                        if (start_pend) begin
                            start_pend<=0; ph<=0; ph2<=0; ph3<=0; dlt<=K_STEP0-K_STEPT; am<=K_MODAMP; am2<=K_MOD2AMP; am3<=K_MOD3AMP; an1<=K_N1AMP; an2<=K_CLICKAMP;
                            vel_lat<=start_vel; ls<=32'h2468ACE; hx1<=0; hy1<=0; ly1<=0; hx2<=0; hy2<=0; ly2<=0; active<=1;
                        end
                    end end
                    st <= S_DONE;
                end
                S_DONE: begin
                    if (sample_tick) begin
                        // 上一帧未完成则继续（正常不会发生，1088clk远大于6clk）
                        if (active || trig_pend || retrig_pend) st <= S_MODE; else st <= S_IDLE;
                    end else st <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
