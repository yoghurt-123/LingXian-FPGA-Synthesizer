// 电吉他音源（定点，无浮点、无录音ROM）：一条扫描运算通路轮流计算 6 个声部槽 × 24 个分音，
// 不复制运算资源。每弦独立保存相位/幅度/音龄状态；音高由 note_sel 按弦选择参数表。
// 分音槽编号与序号一一对应（含被剔除的空槽），起音整形/衰减参数由 guitar_note_params.vh 给出。
// 支持：拨弦触发、平滑制音（输出级短释放）、约 4 秒自然衰减。
// 拨弦瞬态：LFSR 白噪声 → 一阶高通(≈1.5kHz) → 一阶低通(≈6kHz) → 短包络（升约 0.7ms、τ≈2.7ms），
// 与已确认的离线版本同结构同幅度（NOISE_AMP 为唯一强度参数），随任意拨弦触发一次。
// 声部数量评估：6 槽扫描共 583 拍，采样周期 1088 拍（52.5MHz/1088≈48.25kHz），余量 505 拍，无需提高时钟。
module guitar_voice #(
    parameter integer GTR_SAMPLES  = 193015, // ★最长发声时间，约 4.0s（按 52500000/1088）
    parameter integer TAIL_START   = 168889, // ★约 3.5s 后附加加速衰减，避免长尾硬切
    parameter integer TAIL_SHIFT   = 6,      // ★加速强度：越小衰减越快
    parameter integer TAIL_LOW_START = 48254,// ★A2/D3/G3 低阶分音尾音加强起始（1.0s≈48254 采样，调小=更早生效）
    parameter integer TAIL_LOW_SHIFT = 6,    // ★A2/D3/G3 低阶分音尾音加强强度（越小衰减越快；6=已认可基准，7/8 更缓）
    parameter integer MUTE_RELEASE = 1024,   // ★制音释放长度（采样）：1024≈21ms，输出增益线性归零
    parameter integer SPLIT1       = 14476,  // 0.30s：快段→中段（与提取时一致）
    parameter integer SPLIT2       = 48254,  // 1.00s：中段→慢段
    parameter integer RELEASE_LEN  = 1024,   // 正常结束的末尾平滑归零长度（约 21ms）
    parameter integer FADE_RELEASE = 64,     // ★按槽替换淡出长度（采样）：64≈1.33ms；替换旧音先用它快速淡出
    parameter integer MUTE_PLUCK_CODE = 9932,// ★闷音拨弦附加衰减码（30ms 后生效，τ≈35ms≈-18dB@150ms，与离线一致）
    parameter integer NOISE_AMP    = 1300    // ★拨弦噪声电平（2026-10-14 标定：新模型下瞬态约 -22dB，随力度缩放）
)(
    input clk, input rst_n, input sample_tick,
    input [5:0] trig,        // 每声部拨弦触发（bit0=E2 bit1=B2 bit2=E3 bit3..5=单音弦池 A2/D3/G3/B3/E4 共用）
    input mute,              // 平滑制音（全局）：所有在发声的弦进入 21ms 释放，待触发取消
    input kill,              // ★Esc全局清理：输出已静音后的强制终止（电平，清全部声部状态）
    input [5:0] fade_req,    // ★按槽替换淡出请求：该槽以 FADE_RELEASE 采样快速淡出后自然结束（与全局制音独立）
    input [23:0] vel_sel,    // ★每槽 4 位力度码：输出增益=(code+1)/16（手动演奏固定 4'hF=1.0）
    input [5:0] pluck_mute,  // ★本次拨弦闷音标志：约 30ms 后进入快速衰减（palm-mute 近似）
    input [23:0] note_sel,   // 每声部音高选择（4 位/槽）：0=E2 1=B2 2=E3 3=A2 4=D3 5=G3 6=B3 7=E4 8=G2 9=A3
    input [143:0] slot_ratio,// ★每槽弯音倍率（6×24 Q4.20，1.0=2^20；未激活槽也必须为2^20）
    output active,
    output [2:0] low_note,   // 当前低音弦（供清音增益选择）：0=其他音，1=A2，2=D3，3=G3，4=B3；不影响过载路径
    output [5:0] slot_busy,  // ★各槽占用（pending|playing）：供分配控制判断空闲/等待淡出完成
    output reg signed [15:0] data
);
    `include "guitar_note_params.vh"
    // 扫描布局：0..575 = 6 槽 × 24 分音 × 4 拍；576..581 = 六槽增益槽；582 = 输出槽
    (* syn_ramstyle = "block_ram" *) reg [31:0] phase_mem [0:143];
    reg [31:0] phase_q;
    reg [31:0] phase_new_r;
    reg [31:0] amp   [0:143];        // 幅度 Q12
    reg [18:0] age   [0:5];
    reg [5:0]  playing, pending, muted;
    reg [5:0]  fresh;                // 该槽"触发后首扫"标志：首扫 24 个分音全部从 0 起音，不读 amp 旧值
    reg [10:0] relcnt [0:5];         // 制音释放计数（1024→0）
    reg [10:0] relg   [0:5];         // 该槽输出增益 0..1024
    reg [9:0]  scan;
    reg busy;
    reg signed [20:0] sum0, sum1, sum2, sum3, sum4, sum5;
    reg signed [31:0] total;
    // 扫描索引：由"每拍从 scan_n 推导"改为增量计数器推导（去掉 ×96 与 10 位减法长链），
    // 行为与原推导在 0..575 有效区逐拍一致（尾段 576..582 的索引值本就不被使用）
    // ★kaddr 改为直接递增（组尾 +1，末组饱和）：扫描期严格 0,1,..,143，与原 sidx/pidx 推导
    //   在所有被使用的节拍上逐位一致；砍掉 qidx→pidx_c→sidx_c→×24 长链对"相位读回"的拖累。
    reg [3:0] sidx, sel;
    reg [1:0] qidx;
    reg [4:0] pidx;
    reg [7:0] kaddr;
    wire pwrap = (qidx == 2'd3);                                 // 本分音组最后一拍
    wire swrap = pwrap && (pidx == 5'd23);                       // 本槽最后一个分音
    wire [1:0] qidx_c = pwrap ? 2'd0 : (qidx + 2'd1);
    wire [4:0] pidx_c = pwrap ? (swrap ? 5'd0 : (pidx + 5'd1)) : pidx;
    wire [2:0] sidx_c = swrap ? ((sidx == 3'd5) ? 3'd5 : (sidx + 3'd1)) : sidx;
    wire [7:0] kaddr_c = pwrap ? ((kaddr == 8'd143) ? 8'd143 : (kaddr + 8'd1)) : kaddr;
    reg [3:0] note_lat [0:5];        // ★按槽锁存的音色（4 位，支持 0..9）：触发时锁存，发声中不受 note_sel 变化影响
    reg [3:0] vel_lat  [0:5];        // ★按槽锁存的力度码（触发时锁存）
    reg       mplk_lat [0:5];        // ★按槽锁存的闷音标志（触发时锁存）
    wire [3:0] sel_c = note_lat[sidx_c];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sidx <= 3'd0; qidx <= 2'd0; pidx <= 5'd0; kaddr <= 8'd0; sel <= 4'd0;
        end else if (sample_tick) begin
            sidx <= 3'd0; qidx <= 2'd0; pidx <= 5'd0; kaddr <= 8'd0; sel <= note_lat[0];
        end else if (busy) begin
            sidx <= sidx_c; qidx <= qidx_c; pidx <= pidx_c; kaddr <= kaddr_c; sel <= sel_c;
        end
    end
    // ---- amp 同步双口 RAM（1R+1W，读输出寄存=1 拍延迟；不依赖上电初值）----
    // 写口：qidx1 写回（数据/使能见下方 amp_wd/amp_we）；读口预取"下一分音"（kaddr_c），
    // 读延迟 1 拍后恰在分音组起点(qidx0)对齐当前分音；读=下一分音、写=当前分音，同拍必不同地址
    wire [7:0]  amp_ra = sample_tick ? 8'd0 : kaddr_c;
    reg  [31:0] amp_rd;
    reg  [31:0] amp_cur_r;    // qidx0 捕获的当前分音旧值（供 qidx1 写回算式）
    reg  [31:0] amp_new_r;    // qidx1 写入的新值（供 qidx2 输出乘积）
    wire [31:0] amp_wd;
    wire amp_we;
    always @(posedge clk) begin
        if (amp_we) amp[kaddr] <= amp_wd;
        amp_rd <= amp[amp_ra];
    end
    always @(posedge clk) begin
        amp_cur_r <= amp_rd;
        if (amp_we) amp_new_r <= amp_wd;
    end
    // 分段衰减 + 尾段加速（制音不再加速衰减，快慢由输出级释放决定）
    // ★尾音加强统一由下方 tail_low_on_n 按音符/分音选择（含 2026-10-12 E2/A2 优化）：约 1 秒起平滑加速，
    //   消除长尾"低沉轰鸣"（基波/低阶分音衰减过慢）。微调位置：
    //   TAIL_LOW_START = 起始采样数（48254≈1.0s）；TAIL_LOW_SHIFT = 强度（越小越快）
    //   其余音与其余分音仍按原 TAIL_START(3.5s)/TAIL_SHIFT 加速，互不影响
    // ★衰减码流水：索引本就提前一拍预计算，这里用"下一拍索引"提前一拍算出衰减码并寄存，
    //   切断 sidx→age→衰减码表→加法→乘法器的长组合路径（算法与数值不变，仅滞后一拍对齐）
    wire [3:0] sel_n  = sample_tick ? note_lat[0] : sel_c;
    wire [2:0] sidx_n = sample_tick ? 3'd0 : sidx_c;
    wire [4:0] pidx_n = sample_tick ? 5'd0 : pidx_c;
    wire [18:0] age_n = age[sidx_n];
    // ★尾音加强（按音符选择，与所在槽位无关；本轮扩展：E2 新增、A2 由低两阶扩到低三阶）：
    //   E2(0)/D3/G3/B3/E4(4~7) 低两阶分音；A2(3) 低三阶分音；均自 TAIL_LOW_START(≈1.0s) 起平滑加速，
    //   强度 TAIL_LOW_SHIFT=6（与 2026-10-12 E2/A2 试听认可版本一致）；B2/E3 不参与，走原 3.5s 通用策略
    wire tail_low_on_n = ((sel_n == 4'd0) && (pidx_n <= 5'd1)) ||   // E2 低两阶
                         ((sel_n == 4'd8) && (pidx_n <= 5'd1)) ||   // G2（E弦3品移调）低两阶
                         ((sel_n == 4'd3) && (pidx_n <= 5'd2)) ||   // A2 低三阶
                         ((sel_n == 4'd9) && (pidx_n <= 5'd2)) ||   // A3（A弦八度移调）低三阶
                         (((sel_n == 4'd4) || (sel_n == 4'd5) || (sel_n == 4'd6) || (sel_n == 4'd7) || (sel_n == 4'd10)) && (pidx_n <= 5'd1));
    wire [18:0] tail_start_n = tail_low_on_n ? TAIL_LOW_START : TAIL_START;
    wire [18:0] tail_age_n = (age_n > tail_start_n) ? (age_n - tail_start_n) : 19'd0;
    wire [15:0] tail_extra_n = tail_low_on_n ? (tail_age_n >> TAIL_LOW_SHIFT) : (tail_age_n >> TAIL_SHIFT);
    wire [15:0] code_base_n = (age_n < SPLIT1) ? gtr_fast(sel_n, pidx_n) :
                              (age_n < SPLIT2) ? gtr_mid(sel_n, pidx_n) : gtr_slow(sel_n, pidx_n);
    // ★闷音拨弦：约 30ms(1447 采样)后附加强衰减（τ≈35ms），与离线 palm-mute 一致
    wire [15:0] mute_boost_n = (mplk_lat[sidx_n] && (age_n > 19'd1447)) ? MUTE_PLUCK_CODE[15:0] : 16'd0;
    wire [16:0] code_sum_n = {1'b0, code_base_n} + {1'b0, tail_extra_n} + {1'b0, mute_boost_n};
    reg [15:0] decay_code_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) decay_code_r <= 16'd0;
        else decay_code_r <= code_sum_n[16] ? 16'd32767 : code_sum_n[15:0];
    end
    wire pre_first = sample_tick || !busy || (scan >= 10'd576);
    // ★相位步长流水（弯音扩展）：查表一级寄存，再用槽倍率做32×24乘法+取整+饱和后寄存。
    //   两级都落在槽内4拍窗口（STA按单周期检查，探针实测乘法级约79MHz）；
    //   倍率=2^20时 (step*2^20+2^19)>>20 == step，与基线逐位等价。
    // 弯音步长预取需要真正的"下一分音"索引：pidx_c 仅在 qidx==3 才前进，而两级流水要在 q2 就拿到下一分音，
    // 因此这里用与 qidx 无关的 pidx_nx（尾分音回0、槽满饱和），并在空闲/尾段强制首槽。
    wire swrap_nx = (pidx == 5'd23);
    wire [4:0] pidx_nx = pre_first ? 5'd0 : (swrap_nx ? 5'd0 : (pidx + 5'd1));
    wire [2:0] sidx_nx = pre_first ? 3'd0 : (swrap_nx ? ((sidx == 3'd5) ? 3'd5 : (sidx + 3'd1)) : sidx);
    wire [3:0] sel_nx = pre_first ? note_lat[0] : note_lat[sidx_nx];
    // 步长表改为独立BSRAM-ROM（同步读1拍，与原"组合查表+寄存"同拍同值）：
    // 切断 pidx/sel→大组合查表→step_tab_r 的长路径（Stage3构建曾出现该路径-6.4ns）。
    wire [31:0] step_tab_d;
    guitar_step_rom u_step_rom(.clk(clk), .addr({sel_nx, pidx_nx}), .data(step_tab_d));
    reg [23:0] ratio_n, ratio_r;
    always @* begin
        case (sidx_nx)
            3'd0: ratio_n = slot_ratio[23:0];
            3'd1: ratio_n = slot_ratio[47:24];
            3'd2: ratio_n = slot_ratio[71:48];
            3'd3: ratio_n = slot_ratio[95:72];
            3'd4: ratio_n = slot_ratio[119:96];
            default: ratio_n = slot_ratio[143:120];
        endcase
    end
    always @(posedge clk) begin
        ratio_r <= ratio_n;
    end
    wire [55:0] step_prod = step_tab_d * ratio_r;
    wire [36:0] step_round = {1'b0, step_prod[55:20]} + {36'b0, step_prod[19]};
    wire [31:0] step_eff = (step_round[36:31] != 6'd0) ? 32'd0 : step_round[31:0];
    reg [31:0] step_r;
    always @(posedge clk) step_r <= step_eff;
    // 正常结束的末尾平滑归零（制音走输出级释放，不走这里）
    wire [18:0] remain = (GTR_SAMPLES - 1) - age[sidx];
    wire [15:0] rel_gain = (remain < RELEASE_LEN) ? {6'd0, remain[9:0]} : 16'd1024;
    // ★力度缩放：增益槽输出 = 槽释放增益 relg × 力度码(vl_m+1)/16（手动 vel=4'hF 时等价于原 relg）
    // ★rg_v 流水：把"下一拍槽选 + 11×5 乘 + 右移"提前一拍算出并寄存；relg/vel_lat 仅在 sample_tick 更新，
    //   整轮扫描内恒定，故寄存值与原同拍组合计算逐位一致（gain 槽的 operand_b 用寄存值）。
    wire [10:0] rg_m_p = (scan == 10'd575) ? relg[0] : (scan == 10'd576) ? relg[1] : (scan == 10'd577) ? relg[2] :
                         (scan == 10'd578) ? relg[3] : (scan == 10'd579) ? relg[4] : (scan == 10'd580) ? relg[5] : 11'd0;
    wire [3:0] vl_m_p = (scan == 10'd575) ? vel_lat[0] : (scan == 10'd576) ? vel_lat[1] : (scan == 10'd577) ? vel_lat[2] :
                        (scan == 10'd578) ? vel_lat[3] : (scan == 10'd579) ? vel_lat[4] : (scan == 10'd580) ? vel_lat[5] : 4'd15;
    wire [15:0] rg_prod_p = rg_m_p * (vl_m_p + 5'd1);   // 先 16 位自determined 相乘，避免赋值上下文截断
    reg [10:0] rg_v_r;                                  // = (relg*(vel+1))/16，提前一拍
    always @(posedge clk) rg_v_r <= rg_prod_p[14:4];
    reg signed [31:0] operand_a;
    reg signed [15:0] operand_b;
    reg signed [47:0] product;
    // amp 写口（组合 数据/使能）：分支与原 qidx1 实现一致；fresh 首扫用"从 0 起音"公式，不读旧值
    wire amp_fresh = fresh[sidx];
    wire amp_isrel = (remain < RELEASE_LEN);
    wire amp_isatk = (age[sidx] < gtr_attack(sel, pidx));
    wire [31:0] amp_lim   = ({16'd0, gtr_level(sel, pidx)} << 12);
    wire [31:0] amp_atk_n = (amp_cur_r + gtr_rise(sel, pidx) > amp_lim) ? amp_lim : (amp_cur_r + gtr_rise(sel, pidx));
    wire [31:0] amp_atk_f = ({16'd0, gtr_rise(sel, pidx)} > amp_lim) ? amp_lim : {16'd0, gtr_rise(sel, pidx)};
    wire [47:0] amp_dec48 = {16'b0, amp_cur_r} - (product >>> 24);
    assign amp_wd = amp_isrel ? product[41:10] :
                    amp_isatk ? (amp_fresh ? amp_atk_f : amp_atk_n) : amp_dec48[31:0];
    assign amp_we = busy && !sample_tick && (scan < 10'd576) && (qidx == 2'd1) && playing[sidx];
    wire signed [15:0] sine_value;
    // ★正弦表同步读（BSRAM：地址当拍采样、数据下一拍输出）：q=2 时输出的是"q=1 相位"对应的数据，
    //   相位经 qidx0 更新后组内不变，与原"组合表读出再寄存"逐位一致，同时切断 kaddr→相位mux→LUT 长路径。
    sine_lut u_sine(.clk(clk), .addr(phase_new_r[31:24]), .data(sine_value));
    // ★相位写回寄存读：提前一拍寄存"下一拍索引(kaddr_n)对应的相位"，qidx0 的 phase[kaddr]<=读值+step_r
    //   改用寄存值，切断 kaddr→144选1相位读→32位加法→写译码 的长链。kaddr 组内恒定、组间无中间写，
    //   寄存值与旧直读逐位一致；唯一例外：sample_tick 当拍槽0被触发时相位阵列刚预置（同沿写入，
    //   寄存读会取到旧值），此时显式装入与预置公式相同的值，保持与旧直读一致。
    wire [7:0] kaddr_n = sample_tick ? 8'd0 : kaddr_c;
    wire phase_scan_we = busy && !sample_tick && (scan < 10'd576) &&
                         (qidx == 2'd0) && playing[sidx];
    wire phase_we = phase_scan_we;
    wire [7:0] phase_wa = kaddr;
    wire [31:0] phase_wd = fresh[sidx] ?
        (gtr_phase(note_lat[sidx], pidx) - gtr_step(note_lat[sidx], pidx) + step_r) :
        (phase_q + step_r);
    always @(posedge clk) begin
        if (phase_we) phase_mem[phase_wa] <= phase_wd;
        if (phase_we) phase_new_r <= phase_wd;
        phase_q <= phase_mem[kaddr_n];
    end
    always @* begin
        operand_a = 32'sd0; operand_b = 16'sd0;
        if (scan < 10'd576) begin
            if (qidx == 2'd0) begin
                if (remain < RELEASE_LEN) begin
                    operand_a = $signed(amp_rd);
                    operand_b = $signed({1'b0, rel_gain[9:0]});
                end else begin
                    operand_a = $signed(amp_rd);
                    operand_b = $signed(decay_code_r);
                end
            end else if (qidx == 2'd2) begin
                operand_a = {{16{sine_value[15]}}, sine_value};
                operand_b = $signed(amp_new_r[27:12]);
            end
        end else if (scan == 10'd576) begin
            operand_a = $signed(sum0); operand_b = $signed({5'b0, rg_v_r});
        end else if (scan == 10'd577) begin
            operand_a = $signed(sum1); operand_b = $signed({5'b0, rg_v_r});
        end else if (scan == 10'd578) begin
            operand_a = $signed(sum2); operand_b = $signed({5'b0, rg_v_r});
        end else if (scan == 10'd579) begin
            operand_a = $signed(sum3); operand_b = $signed({5'b0, rg_v_r});
        end else if (scan == 10'd580) begin
            operand_a = $signed(sum4); operand_b = $signed({5'b0, rg_v_r});
        end else if (scan == 10'd581) begin
            operand_a = $signed(sum5); operand_b = $signed({5'b0, rg_v_r});
        end
    end
    reg signed [31:0] nz_term;             // 拨弦噪声项（在噪声发生器中更新）
    wire signed [48:0] out_sum = total + (product >>> 10);
    wire signed [48:0] out_final = out_sum + nz_term;
    always @(posedge clk) product <= operand_a * operand_b;
    assign active = |pending | |playing;
    // 清音增益选择：从发声的池槽（3..5）按锁存音色判定；优先级 A2>D3>G3>B3>E4（多音同响时取优先级最高的增益）
    wire p3on = pending[3] | playing[3];
    wire p4on = pending[4] | playing[4];
    wire p5on = pending[5] | playing[5];
    wire a2on = (p3on && note_lat[3] == 3'd3) | (p4on && note_lat[4] == 3'd3) | (p5on && note_lat[5] == 3'd3);
    wire d3on = (p3on && note_lat[3] == 3'd4) | (p4on && note_lat[4] == 3'd4) | (p5on && note_lat[5] == 3'd4);
    wire g3on = (p3on && note_lat[3] == 3'd5) | (p4on && note_lat[4] == 3'd5) | (p5on && note_lat[5] == 3'd5);
    wire b3on = (p3on && note_lat[3] == 3'd6) | (p4on && note_lat[4] == 3'd6) | (p5on && note_lat[5] == 3'd6);
    wire e4on = (p3on && note_lat[3] == 3'd7) | (p4on && note_lat[4] == 3'd7) | (p5on && note_lat[5] == 3'd7);
    wire g2on = (p3on && note_lat[3] == 4'd8) | (p4on && note_lat[4] == 4'd8) | (p5on && note_lat[5] == 4'd8);
    wire a3on = (p3on && note_lat[3] == 4'd9) | (p4on && note_lat[4] == 4'd9) | (p5on && note_lat[5] == 4'd9);
    assign low_note = a2on ? 3'd1 : d3on ? 3'd2 : g3on ? 3'd3 : b3on ? 3'd4 : e4on ? 3'd5 : g2on ? 3'd6 : a3on ? 3'd7 : 3'd0;
    // 各槽占用反馈（供分配控制：空闲优先 / 等待替换淡出完成）
    assign slot_busy = pending | playing;
    // ---- 拨弦瞬态噪声（单发生器）----
    // ★2026-10-14 调整：①LFSR 不再每次复位（自由滚动，避免每次拨弦波形相同 -> "秒针滴答"）；
    //   ②电平降到 1300（按Q2标定，瞬态约 -22dB）；③上升 24 采样≈0.5ms、衰减 >>6≈1.3ms（更像拨片）；
    //   ④随本次触发槽的力度缩放（(vel+1)/16），与离线按力度缩放一致。
    reg [15:0] nz_lfsr;
    reg signed [17:0] nz_hp;
    reg signed [15:0] nz_hp_prev;
    reg signed [17:0] nz_lp;
    reg [15:0] nz_env;
    reg [7:0]  nz_cnt;
    reg nz_act;
    reg [3:0]  nz_v;              // 本次拨弦的力度码（触发时锁存）
    wire signed [15:0] nz_wn = $signed(nz_lfsr);
    wire signed [17:0] nz_hp_t = nz_hp + {{2{nz_wn[15]}}, nz_wn} - {{2{nz_hp_prev[15]}}, nz_hp_prev};
    wire signed [17:0] nz_lp_d = nz_hp - nz_lp;
    // 触发时取所有待触发槽中的最大力度码（直接取输入 vel_sel：事件先写力度再触发，vel_lat 同拍才更新）
    wire [3:0] pv0 = pending[0] ? vel_sel[3:0]   : 4'd0;
    wire [3:0] pv1 = pending[1] ? vel_sel[7:4]   : 4'd0;
    wire [3:0] pv2 = pending[2] ? vel_sel[11:8]  : 4'd0;
    wire [3:0] pv3 = pending[3] ? vel_sel[15:12] : 4'd0;
    wire [3:0] pv4 = pending[4] ? vel_sel[19:16] : 4'd0;
    wire [3:0] pv5 = pending[5] ? vel_sel[23:20] : 4'd0;
    wire [3:0] pv01 = (pv0 > pv1) ? pv0 : pv1;
    wire [3:0] pv23 = (pv2 > pv3) ? pv2 : pv3;
    wire [3:0] pv45 = (pv4 > pv5) ? pv4 : pv5;
    wire [3:0] pv0123 = (pv01 > pv23) ? pv01 : pv23;
    wire [3:0] pvmax = (pv0123 > pv45) ? pv0123 : pv45;
    wire signed [35:0] nz_prod = $signed(nz_lp) * $signed({2'b0, nz_env});
    wire signed [25:0] nz_scaled = ($signed(nz_prod >>> 15)) * $signed({1'b0, nz_v} + 6'sd1);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nz_lfsr <= 16'hACE1; nz_hp <= 18'sd0; nz_hp_prev <= 16'sd0; nz_lp <= 18'sd0;
            nz_env <= 16'd0; nz_cnt <= 8'd0; nz_act <= 1'b0; nz_term <= 32'sd0; nz_v <= 4'd15;
        end else if (sample_tick) begin
            if (|pending) begin nz_cnt <= 8'd0; nz_env <= 16'd0; nz_act <= 1'b1; nz_v <= pvmax; end
            if (nz_act) begin
                nz_lfsr <= {nz_lfsr[14:0], nz_lfsr[15]^nz_lfsr[13]^nz_lfsr[12]^nz_lfsr[10]};
                nz_hp_prev <= nz_wn;
                nz_hp <= (27395 * (nz_hp_t >>> 1)) >>> 14;          // 一阶高通 ≈1.5kHz
                nz_lp <= nz_lp + ((17845 * (nz_lp_d >>> 1)) >>> 14); // 一阶低通 ≈6kHz
                if (nz_cnt < 8'd24) begin nz_env <= nz_env + (NOISE_AMP >>> 3); nz_cnt <= nz_cnt + 1'b1; end
                else nz_env <= nz_env - (nz_env >>> 6);
                nz_term <= nz_scaled >>> 4;    // = (lp*env>>15) * (vel+1)/16
                if (nz_env < 16'd2 && nz_cnt >= 8'd24) begin nz_act <= 1'b0; nz_env <= 16'd0; end
            end else nz_term <= 32'sd0;
        end
    end
    integer s, p;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            age[0] <= 19'd0; age[1] <= 19'd0; age[2] <= 19'd0; age[3] <= 19'd0; age[4] <= 19'd0; age[5] <= 19'd0;
            playing <= 6'b000000; pending <= 6'b000000; muted <= 6'b000000;
            note_lat[0] <= 3'd0; note_lat[1] <= 3'd0; note_lat[2] <= 3'd0;
            note_lat[3] <= 3'd0; note_lat[4] <= 3'd0; note_lat[5] <= 3'd0;
            vel_lat[0] <= 4'hF; vel_lat[1] <= 4'hF; vel_lat[2] <= 4'hF;
            vel_lat[3] <= 4'hF; vel_lat[4] <= 4'hF; vel_lat[5] <= 4'hF;
            mplk_lat[0] <= 1'b0; mplk_lat[1] <= 1'b0; mplk_lat[2] <= 1'b0;
            mplk_lat[3] <= 1'b0; mplk_lat[4] <= 1'b0; mplk_lat[5] <= 1'b0;
            relcnt[0] <= 11'd0; relcnt[1] <= 11'd0; relcnt[2] <= 11'd0; relcnt[3] <= 11'd0; relcnt[4] <= 11'd0; relcnt[5] <= 11'd0;
            relg[0] <= 11'd1024; relg[1] <= 11'd1024; relg[2] <= 11'd1024; relg[3] <= 11'd1024; relg[4] <= 11'd1024; relg[5] <= 11'd1024;
            scan <= 10'd0; busy <= 1'b0; sum0 <= 21'sd0; sum1 <= 21'sd0; sum2 <= 21'sd0; sum3 <= 21'sd0; sum4 <= 21'sd0; sum5 <= 21'sd0;
            total <= 32'sd0; data <= 16'sd0;
            fresh <= 6'b000000;
        end else if (kill) begin
            // ★Esc全局清理：输出已静音后的强制终止（清全部声部状态与扫描）
            playing <= 6'b000000; pending <= 6'b000000; muted <= 6'b000000; fresh <= 6'b000000;
            busy <= 1'b0; data <= 16'sd0; total <= 32'sd0;
            sum0 <= 21'sd0; sum1 <= 21'sd0; sum2 <= 21'sd0; sum3 <= 21'sd0; sum4 <= 21'sd0; sum5 <= 21'sd0;
            relcnt[0] <= 11'd0; relcnt[1] <= 11'd0; relcnt[2] <= 11'd0;
            relcnt[3] <= 11'd0; relcnt[4] <= 11'd0; relcnt[5] <= 11'd0;
            relg[0] <= 11'd1024; relg[1] <= 11'd1024; relg[2] <= 11'd1024;
            relg[3] <= 11'd1024; relg[4] <= 11'd1024; relg[5] <= 11'd1024;
        end else begin
            // 拨弦触发锁存：任何时钟沿捕获脉冲，避免错过与 sample_tick 不同步的触发
            if (trig[0]) pending[0] <= 1'b1;
            if (trig[1]) pending[1] <= 1'b1;
            if (trig[2]) pending[2] <= 1'b1;
            if (trig[3]) pending[3] <= 1'b1;
            if (trig[4]) pending[4] <= 1'b1;
            if (trig[5]) pending[5] <= 1'b1;
            if (mute) begin
                // 平滑制音：在发声的弦启动短释放；尚未发声的待触发取消
                for (s = 0; s < 6; s = s + 1) begin
                    pending[s] <= 1'b0;
                    if (playing[s] && relcnt[s] == 11'd0) begin
                        relcnt[s] <= MUTE_RELEASE;
                        muted[s] <= 1'b1;
                    end
                end
            end
            // ★按槽替换淡出：仅对该槽做 FADE_RELEASE 采样短释放（独立于全局制音的 1024；两请求同拍时以淡出为准）
            for (s = 0; s < 6; s = s + 1) begin
                if (fade_req[s] && playing[s] && relcnt[s] == 11'd0) begin
                    relcnt[s] <= FADE_RELEASE;
                    muted[s] <= 1'b1;
                end
            end
            if (sample_tick) begin
                fresh <= 6'b000000;      // 首扫只覆盖一个采样：本采样内被触发槽再置位
                for (s = 0; s < 6; s = s + 1) begin
                    if (pending[s]) begin
                        pending[s] <= 1'b0; playing[s] <= 1'b1; muted[s] <= 1'b0;
                        relcnt[s] <= 11'd0; relg[s] <= 11'd1024;   // 新拨弦清除旧制音/淡出状态
                        age[s] <= 19'd0; fresh[s] <= 1'b1;         // 本采样为首扫：24 分音全部从 0 起音
                        note_lat[s] <= note_sel[4*s +: 4];         // ★按槽锁存音色（此后发声中不再变化）
                        vel_lat[s]  <= vel_sel[4*s +: 4];
                        mplk_lat[s] <= pluck_mute[s];         // ★按槽锁存音色（此后发声中不再变化）
                    end else if (playing[s]) begin
                        if (relcnt[s] != 11'd0) begin
                            // 制音释放推进：计数到 0 即清除 playing 并清零残余幅度
                            relcnt[s] <= relcnt[s] - 1'b1;
                            relg[s] <= (relcnt[s] == 11'd1) ? 11'd1024 : (relcnt[s] - 1'b1);
                            if (relcnt[s] == 11'd1) begin
                                playing[s] <= 1'b0; muted[s] <= 1'b0;   // 残留 amp 不再清零：复用槽由 fresh 首扫全部重写
                            end
                        end else if (age[s] == GTR_SAMPLES - 1) playing[s] <= 1'b0;
                        else age[s] <= age[s] + 1'b1;
                    end
                end
                if (|pending | |playing) begin
                    busy <= 1'b1; scan <= 10'd0;
                    sum0 <= 21'sd0; sum1 <= 21'sd0; sum2 <= 21'sd0; sum3 <= 21'sd0; sum4 <= 21'sd0; sum5 <= 21'sd0; total <= 32'sd0;
                end else data <= 16'sd0;
            end else if (busy) begin
                // 第582拍接收上一拍的第6声部乘积，避免下一拍乘积清零后漏掉G3。
                if (scan < 10'd582) begin
                    scan <= scan + 1'b1;
                    if (scan < 10'd576) case (qidx)
                        2'd0: ;
                        2'd1: ;   // amp 写回已移至 RAM 写口（组合 amp_wd + 同步写，fresh 首扫从 0 起音）
                        2'd3: if (playing[sidx]) case (sidx)
                            3'd0: sum0 <= sum0 + (product >>> 15);
                            3'd1: sum1 <= sum1 + (product >>> 15);
                            3'd2: sum2 <= sum2 + (product >>> 15);
                            3'd3: sum3 <= sum3 + (product >>> 15);
                            3'd4: sum4 <= sum4 + (product >>> 15);
                            default: sum5 <= sum5 + (product >>> 15);
                        endcase
                        default: ;
                    endcase
                    else if (scan == 10'd577) total <= (product >>> 10);
                    else if (scan == 10'd578) total <= total + (product >>> 10);
                    else if (scan == 10'd579) total <= total + (product >>> 10);
                    else if (scan == 10'd580) total <= total + (product >>> 10);
                    else if (scan == 10'd581) total <= total + (product >>> 10);
                end else begin
                    busy <= 1'b0;
                    data <= (out_final > 49'sd32767) ? 16'sd32767 :
                            (out_final < -49'sd32768) ? -16'sd32768 :
                            out_final[15:0];
                end
            end
        end
    end
endmodule
