// 吉他混响（Schroeder：4 梳状 + 2 全通），定点、无乘法器、默认旁路。
// 与离线 fx_preview 原型同结构：RT60≈1.5s、阻尼≈0.25、湿比 0.25、输入半幅。
// 梳状延迟(采样)：1215/1293/1390/1476；全通：245/605（48.25kHz，1 采样≈20.7us，确定时延）。
// 反馈系数用 2 的幂组合近似（无 DSP / 无乘法器）：g0=456/512 g1=453/512 g2=448/512 g3=445/512。
// 每采样 5 拍：IDLE→CALC（阻尼+反馈+写环）→AP1→AP2→OUT；干声在采样周期内输出，无额外采样延迟。
module guitar_reverb (
    input clk, input rst_n, input sample_tick,
    input signed [15:0] in,
    input rev_on,                 // 1=混响开 0=旁路（默认旁路）
    input clear_req,              // ★Esc全局清理：顺序清零请求（电平；期间暂停正常反馈写入）
    output reg clear_done,        // 顺序清零完成（clear_req为高期间保持）
    output reg signed [15:0] data
);
    localparam C0 = 1215, C1 = 1293, C2 = 1390, C3 = 1476;
    localparam A0 = 245,  A1 = 605;
    localparam S_IDLE = 3'd0, S_RD = 3'd1, S_LP = 3'd2, S_CALC = 3'd3, S_AP1 = 3'd4, S_AP2 = 3'd5, S_OUT = 3'd6;

    function signed [15:0] sat16f; input signed [19:0] v; begin
        sat16f = (v > 20'sd32767) ? 16'sd32767 : (v < -20'sd32768) ? -16'sd32768 : v[15:0];
    end endfunction

    reg signed [15:0] cb0 [0:2047];   // 深度声明为 2 的幂，取模定位，便于推断 BSRAM
    reg signed [15:0] cb1 [0:2047];
    reg signed [15:0] cb2 [0:2047];
    reg signed [15:0] cb3 [0:2047];
    reg signed [15:0] ab0 [0:1023];
    reg signed [15:0] ab1 [0:1023];

    // 上电清零（硬件 BSRAM 上电即为 0；仿真同样按 0 初值，避免未写地址读出 X）
    // Gowin 综合对 initial 循环计数上限为 2000，故拆成两段 1024。
    integer ii;
    initial begin
        for (ii = 0; ii < 1024; ii = ii + 1) begin
            cb0[ii] = 16'sd0; cb1[ii] = 16'sd0; cb2[ii] = 16'sd0; cb3[ii] = 16'sd0;
            ab0[ii] = 16'sd0; ab1[ii] = 16'sd0;
        end
        for (ii = 1024; ii < 2048; ii = ii + 1) begin
            cb0[ii] = 16'sd0; cb1[ii] = 16'sd0; cb2[ii] = 16'sd0; cb3[ii] = 16'sd0;
        end
    end

    reg [10:0] p0 = 11'd0, p1 = 11'd0, p2 = 11'd0, p3 = 11'd0;
    reg [9:0]  q0 = 10'd0, q1 = 10'd0;
    reg signed [15:0] d0, d1, d2, d3, ad0, ad1;
    reg signed [15:0] l0 = 16'sd0, l1 = 16'sd0, l2 = 16'sd0, l3 = 16'sd0;  // 阻尼状态
    reg signed [15:0] x_r;
    reg rev_r;
    reg [2:0] st;
    reg signed [17:0] sum_r;
    reg signed [17:0] wet1_r, wet2_r;
    // ★顺序清零（Esc全局清理）：逐地址写0（一个地址/时钟），与正常写口互斥；共2048拍（约39us）
    reg clr_active;
    reg [11:0] clr_cnt;

    // ---- 18/20 位符号扩展 ----
    wire signed [17:0] d0x = {{2{d0[15]}}, d0};
    wire signed [17:0] d1x = {{2{d1[15]}}, d1};
    wire signed [17:0] d2x = {{2{d2[15]}}, d2};
    wire signed [17:0] d3x = {{2{d3[15]}}, d3};
    wire signed [17:0] l0x = {{2{l0[15]}}, l0};
    wire signed [17:0] l1x = {{2{l1[15]}}, l1};
    wire signed [17:0] l2x = {{2{l2[15]}}, l2};
    wire signed [17:0] l3x = {{2{l3[15]}}, l3};
    wire signed [17:0] ad0x = {{2{ad0[15]}}, ad0};
    wire signed [17:0] ad1x = {{2{ad1[15]}}, ad1};
    wire signed [17:0] xx = {{2{x_r[15]}}, x_r};
    wire signed [19:0] x20 = {{4{x_r[15]}}, x_r};

    // 阻尼：lp_new = (3d + lp_old)/4
    wire signed [17:0] lpn0 = (d0x + d0x + d0x + l0x) >>> 2;
    wire signed [17:0] lpn1 = (d1x + d1x + d1x + l1x) >>> 2;
    wire signed [17:0] lpn2 = (d2x + d2x + d2x + l2x) >>> 2;
    wire signed [17:0] lpn3 = (d3x + d3x + d3x + l3x) >>> 2;

    // 反馈 g*lp_new（移位加法近似）；lp_new 已在 S_LP 拍寄存，这里用寄存值，缩短组合链
    wire signed [25:0] k0 = {{8{l0[15]}}, l0};
    wire signed [25:0] k1 = {{8{l1[15]}}, l1};
    wire signed [25:0] k2 = {{8{l2[15]}}, l2};
    wire signed [25:0] k3 = {{8{l3[15]}}, l3};
    wire signed [25:0] g0p = ((k0 << 8) + (k0 << 7) + (k0 << 6) + (k0 << 3)) >>> 9; // 456/512
    wire signed [25:0] g1p = ((k1 << 8) + (k1 << 7) + (k1 << 6) + (k1 << 2) + k1) >>> 9; // 453/512
    wire signed [25:0] g2p = ((k2 << 8) + (k2 << 7) + (k2 << 6)) >>> 9;              // 448/512
    wire signed [25:0] g3p = ((k3 << 8) + (k3 << 7) + (k3 << 5) + (k3 << 4) + (k3 << 3) + (k3 << 2) + k3) >>> 9; // 445/512
    wire signed [17:0] f0 = g0p[17:0];
    wire signed [17:0] f1 = g1p[17:0];
    wire signed [17:0] f2 = g2p[17:0];
    wire signed [17:0] f3 = g3p[17:0];

    // 梳状写入 v = in/2 + g*lp_new（20 位相加后饱和到 16 位存储）
    wire signed [17:0] hx = xx >>> 1;
    wire signed [19:0] hx20 = {{2{hx[17]}}, hx};
    wire signed [19:0] f020 = {{2{f0[17]}}, f0};
    wire signed [19:0] f120 = {{2{f1[17]}}, f1};
    wire signed [19:0] f220 = {{2{f2[17]}}, f2};
    wire signed [19:0] f320 = {{2{f3[17]}}, f3};
    wire signed [15:0] v0_w = sat16f(hx20 + f020);
    wire signed [15:0] v1_w = sat16f(hx20 + f120);
    wire signed [15:0] v2_w = sat16f(hx20 + f220);
    wire signed [15:0] v3_w = sat16f(hx20 + f320);

    // 全通：v = w + d/2；y = d - v/2
    wire signed [17:0] wetc = sum_r >>> 2;
    wire signed [17:0] apv0 = wetc + (ad0x >>> 1);
    wire signed [19:0] apv0_20 = {{2{apv0[17]}}, apv0};
    wire signed [15:0] apw0_w = sat16f(apv0_20);
    wire signed [17:0] apy0 = ad0x - (apv0 >>> 1);
    wire signed [17:0] apv1 = wet1_r + (ad1x >>> 1);
    wire signed [19:0] apv1_20 = {{2{apv1[17]}}, apv1};
    wire signed [15:0] apw1_w = sat16f(apv1_20);
    wire signed [17:0] apy1 = ad1x - (apv1 >>> 1);

    // 输出：wet = (3*in + reverb)/4
    wire signed [19:0] w20 = {{2{wet2_r[17]}}, wet2_r};
    wire signed [19:0] mix20 = (x20 + x20 + x20 + w20) >>> 2;
    wire signed [15:0] mix16 = sat16f(mix20);

    // ---- 读在 S_RD 拍、写在 S_CALC/S_AP1/S_AP2 拍，互不同拍，避免单口写模式冲突 ----
    //      clear_req 期间写口用于顺序清零（优先于正常写，读保持）
    always @(posedge clk) begin
        if (clr_active) cb0[clr_cnt[10:0]] <= 16'sd0;
        else if (st == S_CALC) cb0[p0] <= v0_w;
        else if (st == S_RD) d0 <= cb0[p0];
    end
    always @(posedge clk) begin
        if (clr_active) cb1[clr_cnt[10:0]] <= 16'sd0;
        else if (st == S_CALC) cb1[p1] <= v1_w;
        else if (st == S_RD) d1 <= cb1[p1];
    end
    always @(posedge clk) begin
        if (clr_active) cb2[clr_cnt[10:0]] <= 16'sd0;
        else if (st == S_CALC) cb2[p2] <= v2_w;
        else if (st == S_RD) d2 <= cb2[p2];
    end
    always @(posedge clk) begin
        if (clr_active) cb3[clr_cnt[10:0]] <= 16'sd0;
        else if (st == S_CALC) cb3[p3] <= v3_w;
        else if (st == S_RD) d3 <= cb3[p3];
    end
    always @(posedge clk) begin
        if (clr_active && !clr_cnt[10]) ab0[clr_cnt[9:0]] <= 16'sd0;
        else if (st == S_AP1) ab0[q0] <= apw0_w;
        else if (st == S_RD) ad0 <= ab0[q0];
    end
    always @(posedge clk) begin
        if (clr_active && !clr_cnt[10]) ab1[clr_cnt[9:0]] <= 16'sd0;
        else if (st == S_AP2) ab1[q1] <= apw1_w;
        else if (st == S_RD) ad1 <= ab1[q1];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; x_r <= 16'sd0; rev_r <= 1'b0;
            sum_r <= 18'sd0; wet1_r <= 18'sd0; wet2_r <= 18'sd0; data <= 16'sd0;
            l0 <= 16'sd0; l1 <= 16'sd0; l2 <= 16'sd0; l3 <= 16'sd0;
            clr_active <= 1'b0; clr_cnt <= 12'd0; clear_done <= 1'b0;
        end else if (clear_req) begin
            // Esc清理：暂停正常反馈，逐地址清零，并清滤波状态/管线/指针；保持BSRAM推断（同步写口）
            clr_active <= 1'b1;
            if (clr_cnt != 12'd2047) clr_cnt <= clr_cnt + 1'b1;
            else clear_done <= 1'b1;
            st <= S_IDLE; x_r <= 16'sd0; rev_r <= 1'b0; data <= 16'sd0;
            sum_r <= 18'sd0; wet1_r <= 18'sd0; wet2_r <= 18'sd0;
            l0 <= 16'sd0; l1 <= 16'sd0; l2 <= 16'sd0; l3 <= 16'sd0;
            p0 <= 11'd0; p1 <= 11'd0; p2 <= 11'd0; p3 <= 11'd0; q0 <= 10'd0; q1 <= 10'd0;
        end else begin
            clr_active <= 1'b0; clr_cnt <= 12'd0; clear_done <= 1'b0;
            case (st)
                S_IDLE: if (sample_tick) begin
                    x_r <= in; rev_r <= rev_on; st <= S_RD;
                end
                S_RD: st <= S_LP;
                S_LP: begin
                    l0 <= lpn0[15:0]; l1 <= lpn1[15:0]; l2 <= lpn2[15:0]; l3 <= lpn3[15:0];
                    st <= S_CALC;
                end
                S_CALC: begin
                    sum_r <= d0x + d1x + d2x + d3x;
                    st <= S_AP1;
                end
                S_AP1: begin wet1_r <= apy0; st <= S_AP2; end
                S_AP2: begin wet2_r <= apy1; st <= S_OUT; end
                S_OUT: begin
                    data <= rev_r ? mix16 : x_r;
                    p0 <= (p0 == C0-1) ? 11'd0 : p0 + 11'd1;
                    p1 <= (p1 == C1-1) ? 11'd0 : p1 + 11'd1;
                    p2 <= (p2 == C2-1) ? 11'd0 : p2 + 11'd1;
                    p3 <= (p3 == C3-1) ? 11'd0 : p3 + 11'd1;
                    q0 <= (q0 == A0-1) ? 10'd0 : q0 + 10'd1;
                    q1 <= (q1 == A1-1) ? 10'd0 : q1 + 10'd1;
                    st <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
