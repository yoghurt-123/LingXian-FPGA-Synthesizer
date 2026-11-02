// 吉他主奏连续音高表情控制：左右弯音(±2半音) + V颤音(5Hz/±50音分候选，±25可恢复参数)。
// Stage2（2026-10-18）：V颤音与弯音在同一Q12半音域相加后一次查表换算倍率；LFO自由运行，
// Stage3（2026-10-18）：最小目标品位（0..12品）+ F11连奏滑音；总偏移=品位位置+弯音+颤音，一次换算；
//   起音直接使用品位倍率（第一个分音即目标音高）；主奏失效只撤弯音/颤音，品位位置保留。
//   开关只渐变深度（965采样），六槽各自保存撤去状态；扫描期间倍率保持不变。
// 规格（docs/planning/PITCH_BEND_DESIGN.md）：
//  - 左箭头(0x50)=-200音分，右箭头(0x4F)=+200音分；两键同按或全松=0；按住保持，松开平滑回中。
//  - 平滑约30ms：按真实sample_tick计数(52500000/1088)，默认RAMP_SAMPLES=1448；
//    商余数法逐采样推进，终点精确；途中反向从当前实际偏移重新规划。
//  - 只作用于"最近一次实际被声部接受的USB手动吉他触发"；槽号+代次绑定，
//    槽被其他来源重新分配后旧事务不再作用于新声音（代次校验）。
//  - 切换主奏：旧槽目标置0平滑回中，新槽从0平滑进入当前有效目标；
//    演示/断连使目标失效（平滑回中）；kill直接清事务并把倍率恢复1.0。
//  - 音高偏移域：有符号Q12半音（1半音=4096）；倍率=2^(偏移/12)，24位Q4.20（1.0=2^20）。
//  - 倍率表：1/16半音栅格覆盖±14.5半音（bend_ratio_rom），线性插值；零偏移精确等于2^20。
//  - 每采样在吉他扫描结束后（间隙）统一更新6个槽的偏移与倍率；扫描期间每槽只使用稳定一份倍率，
//    同一音符不同分音不会混用新旧倍率。基准不变量：所有槽未绑定时倍率=2^20。
module pitch_bend_ctrl #(
    parameter integer RAMP_SAMPLES = 1448,     // 30ms @ 48253.68Hz
    parameter integer VIB_RAMP = 965,           // 20ms深度渐变
    parameter integer VIB_PEAK = 2048           // 颤音深度峰值Q12半音：2048=±50音分（1024=±25音分可恢复参数）
)(
    input clk, input rst_n, input sample_tick,
    input bend_left, input bend_right,          // 保持电平（已做在线门控）
    input vib_hold,                             // V键保持电平（按住开启，松开撤去）
    input [23:0] trig_fret,                     // 6槽×4位：本次触发的品位（非USB源=0）
    input b_on,                                 // B连奏滑音开关
    input [3:0] fret_sel,                       // 当前品位选择
    input [13:0] slide_samples,                 // 当前滑音段采样数（20..300ms档，启动时锁存）
    input connected, input gtr_inhibit, input demo,
    input kill,
    input [5:0] trig,                           // 实际到吉他声部的触发（含演示；用于代次递增）
    input [5:0] trig_usb,                       // 其中USB手动来源的触发（用于绑定主奏）
    output [143:0] slot_ratio                   // 6×24位 Q4.20
);
    localparam integer GAP_START = 640;         // 扫描583拍后的间隙起点
    localparam integer SAFE_CNT  = 620;         // 此计数之后（扫描结束）可直接改倍率
    localparam [23:0] RATIO_ONE  = 24'h100000;
    localparam [11:0] NSAMP = RAMP_SAMPLES;      // 常数化，供位宽明确的比较/乘法
    localparam [31:0] LFO_STEP = 32'd445040;    // round(5*2^32/Fs)，实际4.999995Hz
    localparam integer DVIB = VIB_RAMP;         // 深度渐变采样数（默认20ms）
    localparam [12:0] VP13 = VIB_PEAK;           // 深度目标（13位有符号安全，≤4095）
    localparam [11:0] VP12 = VIB_PEAK;           // 12位深度寄存器比较用
    localparam [12:0] DV13 = DVIB;               // 渐变时长（13位）
    localparam [12:0] DV2  = DVIB * 2;           // 每采样最大2步（±50音分/20ms = 2.12步/采样）
    `include "vib_sine_params.vh"               // 128点正弦波形表（独立小ROM，不用音频正弦口）

    // ---------------- 目标与重连同步 ----------------
    reg arrow_resync;
    wire gtr_ok = connected & ~gtr_inhibit & ~demo;
    wire [1:0] target_cls = (!gtr_ok || arrow_resync) ? 2'd0 :
        (bend_left & ~bend_right) ? 2'd1 :
        (bend_right & ~bend_left) ? 2'd2 : 2'd0;
    wire signed [23:0] target_val = (target_cls == 2'd1) ? -24'sd8192 :
                                    (target_cls == 2'd2) ?  24'sd8192 : 24'sd0;

    // ---------------- 每槽状态 ----------------
    reg [3:0] gen [0:5];           // 槽代次（每次实际触发+1）
    reg lead_valid;                // 主奏绑定有效
    reg [2:0] lead_slot;
    reg signed [23:0] off [0:5];   // 当前音高偏移 Q12半音
    reg [1:0] pcls [0:5];          // 已规划目标类别（0=0,1=-8192,2=+8192）
    reg [10:0] rq [0:5];           // 每采样步进步数（支持缩短斜坡）
    reg [10:0] rr [0:5];           // 每采样步进余数
    reg [10:0] rrem [0:5];         // 余数累加
    reg rneg [0:5];                // 步进方向
    reg ron [0:5];                 // 斜坡进行中
    reg [23:0] ratio [0:5];        // 已提交倍率
    reg [5:0] unity_pend;          // 触发发生在扫描期：间隙内补提交起音倍率
    reg [3:0] pend_fret [0:5];     // 待补提交起音倍率对应的品位
    // ★Stage3：每槽绝对品位位置（Q12半音，0..49152）与滑音
    reg [16:0] pos [0:5];
    reg [3:0] applied_fret;        // 已应用到主奏的品位
    reg slide_on, sneg;
    reg [6:0] sq;
    reg [13:0] sr, srem;
    reg [13:0] sn_lat;            // 本段锁存时长
    reg [16:0] stgt;
    reg [3:0] stgt_fret;
    reg [16:0] sdiv_dab;
    reg [17:0] sdiv_rem, sdiv_q;
    reg [4:0] sdiv_cnt;
    reg sdiv_neg;
    // ★颤音：LFO自由运行 + 每槽深度渐变状态
    reg [31:0] lfo_phase;
    reg vib_resync;
    reg [11:0] dpth [0:5];         // 当前颤音深度（Q12半音，0..1024）
    reg [1:0] dq [0:5];            // 每采样深度步进（0/1；N=965时商只需0/1）
    reg [9:0] dr [0:5];            // 深度步进余数
    reg [9:0] drem [0:5];
    reg dneg [0:5];
    reg don [0:5];
    reg dcls [0:5];                // 已规划深度目标（0=0，1=1024）
    reg signed [12:0] vib_off;     // 当前槽的颤音瞬时偏移（ST_VIB计算）

    // ---------------- 倍率表与间隙状态机 ----------------
    localparam [3:0] ST_IDLE = 4'd0, ST_RAMP = 4'd1, ST_RD0 = 4'd2,
                     ST_RD1 = 4'd3, ST_MUL = 4'd4, ST_COMMIT = 4'd5, ST_TAIL = 4'd6,
                     ST_ISSUE = 4'd7, ST_DIV = 4'd8, ST_DRAMP = 4'd9, ST_VIB = 4'd10,
                     ST_SRAMP = 4'd11, ST_SDIV = 4'd12;
    reg [3:0] st;
    reg [2:0] fslot;
    reg [8:0] ridx; reg [7:0] rfrac; reg [3:0] rtag;
    reg [23:0] rr0, rr1;
    reg signed [32:0] iprod;
    reg [9:0] gap_cnt;


    // 品位起音倍率（与bend_ratio_rom在0.25/半音栅格点完全相同：round(2^(f/12)*2^20)）
    function [23:0] fret_ratio; input [3:0] f; begin
        case(f)
            4'd0: fret_ratio=24'h100000; 4'd1: fret_ratio=24'h10F390;
            4'd2: fret_ratio=24'h11F59B; 4'd3: fret_ratio=24'h1306FE;
            4'd4: fret_ratio=24'h1428A3; 4'd5: fret_ratio=24'h155B81;
            4'd6: fret_ratio=24'h16A09E; 4'd7: fret_ratio=24'h17F911;
            4'd8: fret_ratio=24'h1965FF; 4'd9: fret_ratio=24'h1AE8A0;
            4'd10: fret_ratio=24'h1C823E;4'd11: fret_ratio=24'h1E3438;
            default: fret_ratio=24'h200000;
        endcase
    end endfunction
    // ★滑音推进（目标品位位置stgt，从当前实际位置出发，段时长sn_lat）
    wire [16:0] spos = pos[fslot];
    wire [16:0] sstepv = {10'd0, sq};
    wire [16:0] snxt0 = sneg ? (spos - sstepv) : (spos + sstepv);
    wire [14:0] ssum = srem + sr;
    wire [13:0] ssum_adj = (ssum >= sn_lat) ? (ssum - sn_lat) : ssum[13:0];
    wire [16:0] sd_nxt = (ssum >= sn_lat) ? (sneg ? (snxt0 - 17'd1) : (snxt0 + 17'd1)) : snxt0;
    wire [16:0] stgt_now = {fret_sel, 12'd0};
    wire signed [17:0] sdelta = $signed({1'b0, stgt_now}) - $signed({1'b0, spos});
    wire slide_plan = lead_valid && (lead_slot == fslot) && b_on && ~gtr_inhibit && (fret_sel != applied_fret);   // 途中改目标也从实际位置重规划
    // LFO自由运行（按真实sample_tick推进，开关只渐变深度，相位不跳变）
    always @(posedge clk or negedge rst_n)
        if (!rst_n) lfo_phase <= 32'd0;
        else if (sample_tick) lfo_phase <= lfo_phase + LFO_STEP;
    wire signed [12:0] lfo_wave = vib_wave(lfo_phase[31:25]);
    wire vib_on = vib_hold & ~vib_resync & gtr_ok;   // 重连后须先松开V

    // 当前处理槽的组合量
    wire signed [23:0] cur_off = off[fslot];
    wire [1:0] want_cls = (lead_valid && (lead_slot == fslot)) ? target_cls : 2'd0;
    wire signed [23:0] want_val = (want_cls == 2'd1) ? -24'sd8192 :
                                  (want_cls == 2'd2) ?  24'sd8192 : 24'sd0;
    wire signed [23:0] cur_delta = want_val - cur_off;
    wire signed [23:0] cur_abs = cur_delta[23] ? -cur_delta : cur_delta;
    wire [17:0] dab = cur_abs[17:0];
    // 串行除法（18次移位减）：商/余数对任意RAMP_SAMPLES精确，仿真可缩短斜坡而不改变算法
    reg [17:0] div_rem, div_q, div_dab;
    reg [4:0] div_cnt;
    reg div_neg; reg [1:0] div_cls;
    // 斜坡推进
    wire signed [23:0] step_s = $signed({17'b0, rq[fslot]});
    wire signed [23:0] nxt0 = rneg[fslot] ? (cur_off - step_s) : (cur_off + step_s);
    wire [11:0] remsum = rrem[fslot] + rr[fslot];
    wire [11:0] remadj = (remsum >= NSAMP) ? (remsum - NSAMP) : remsum;
    wire signed [23:0] nxt = (remsum >= NSAMP) ?
        (rneg[fslot] ? (nxt0 - 24'sd1) : (nxt0 + 24'sd1)) : nxt0;
    // ★颤音深度计划/推进（目标只有0或1024；N=965，商只需0/1，无需再开除法器）
    wire dwant_hi = (lead_valid && (lead_slot == fslot) && vib_on);
    wire [11:0] dpth_cur = dpth[fslot];
    wire signed [12:0] ddelta = (dwant_hi ? VP13 : 13'sd0) - $signed({1'b0, dpth_cur});
    wire [12:0] dabs = ddelta[12] ? -ddelta : ddelta;
    // 每采样步数q=floor(dabs/DVIB)（0/1/2），余数r=dabs-q*DVIB<DVIB；2048深度需q=2路径
    wire [1:0] dq_c = (dabs >= DV2) ? 2'd2 : (dabs >= DV13) ? 2'd1 : 2'd0;
    wire [12:0] dr_full = dabs - ((dq_c == 2'd2) ? DV2 : (dq_c == 2'd1) ? DV13 : 13'd0);
    wire [9:0] dr_c = dr_full[9:0];
    wire [11:0] dstepv = {10'd0, dq[fslot]};
    wire [11:0] dnxt0 = dneg[fslot] ? (dpth_cur - dstepv) : (dpth_cur + dstepv);
    wire [10:0] dsum = drem[fslot] + dr[fslot];
    wire [10:0] dsum_adj = (dsum >= DVIB) ? (dsum - DVIB) : dsum;
    wire [11:0] dnxt = (dsum >= DVIB) ? (dneg[fslot] ? (dnxt0 - 12'd1) : (dnxt0 + 12'd1)) : dnxt0;
    // 颤音瞬时偏移：深度 × 波形（Q12），一次取整；与弯音偏移相加后再统一查表换算倍率
    wire signed [24:0] vib_prod = $signed({1'b0, dpth[fslot]}) * lfo_wave;
    wire signed [23:0] off_tot = $signed({7'd0, pos[fslot]}) + cur_off + {{11{vib_off[12]}}, vib_off};
    // 表索引/插值系数（ST_ISSUE时刻使用已更新的当前总偏移；负偏移算术右移取floor）
    wire signed [23:0] idx_raw = (off_tot >>> 8) + 24'sd232;
    // 表有效数据0..464（+14.5半音=idx 464，mem[465]为+14.5625但超出规格）；
    // 上端frac=0时直接取最后合法点，插值第二项钳制，绝不读入填充区。
    wire in_range = (idx_raw >= 0) && (idx_raw <= 24'sd464);
    wire [8:0] idx_v = in_range ? idx_raw[8:0] : ((idx_raw < 0) ? 9'd0 : 9'd464);
    wire [7:0] frac_v = in_range ? off_tot[7:0] : 8'd0;
    wire [8:0] idx1_v = (idx_v >= 9'd464) ? 9'd464 : (idx_v + 9'd1);
    wire [8:0] rom_addr = (st == ST_ISSUE) ? idx_v : (st == ST_RD0) ? idx1_v : ridx;
    wire [23:0] rom_data;
    bend_ratio_rom u_rom(.clk(clk), .addr(rom_addr), .data(rom_data));

    wire signed [24:0] interp_d = $signed({1'b0, rr1}) - $signed({1'b0, rr0});
    wire signed [32:0] interp_p = interp_d * $signed({1'b0, rfrac});
    wire signed [32:0] interp_adj = (interp_p + 33'sd128) >>> 8;
    wire signed [25:0] interp_sum = $signed({1'b0, rr0}) + interp_adj[24:0];
    wire [23:0] interp_val = (interp_sum < 0) ? 24'd0 :
                             (interp_sum > 26'sd16777215) ? 24'hFFFFFF : interp_sum[23:0];

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE; fslot <= 3'd0; ridx <= 9'd0; rfrac <= 8'd0; rtag <= 4'd0;
            rr0 <= 24'd0; rr1 <= 24'd0; iprod <= 33'sd0; gap_cnt <= 10'd0;
            div_rem <= 18'd0; div_q <= 18'd0; div_dab <= 18'd0; div_cnt <= 5'd0; div_neg <= 1'b0; div_cls <= 2'd0;
            lead_valid <= 1'b0; lead_slot <= 3'd0; arrow_resync <= 1'b1; vib_resync <= 1'b1;
            applied_fret <= 4'd0; slide_on <= 1'b0; sdiv_rem <= 18'd0; sdiv_q <= 18'd0; sdiv_cnt <= 5'd0; sdiv_neg <= 1'b0; sn_lat <= 14'd3860;
            unity_pend <= 6'd0; vib_off <= 13'sd0;
            for (k = 0; k < 6; k = k + 1) begin
                gen[k] <= 4'd0; off[k] <= 24'sd0; pcls[k] <= 2'd0;
                rq[k] <= 11'd0; rr[k] <= 11'd0; rrem[k] <= 11'd0;
                rneg[k] <= 1'b0; ron[k] <= 1'b0; ratio[k] <= RATIO_ONE;
                dpth[k] <= 12'd0; dq[k] <= 2'd0; dr[k] <= 10'd0; drem[k] <= 10'd0;
                pos[k] <= 17'd0; pend_fret[k] <= 4'd0;
                dneg[k] <= 1'b0; don[k] <= 1'b0; dcls[k] <= 1'b0;
            end
        end else begin
            if (sample_tick) gap_cnt <= 10'd0;
            else if (gap_cnt != 10'd1023) gap_cnt <= gap_cnt + 10'd1;

            // ---------- 间隙状态机：逐槽推进斜坡并换算倍率 ----------
            case (st)
                ST_IDLE: begin
                    if (gap_cnt == GAP_START) begin
                        fslot <= 3'd0;
                        st <= ST_RAMP;
                    end
                end
                ST_RAMP: begin
                    if (cur_delta == 24'sd0) begin
                        ron[fslot] <= 1'b0;
                        pcls[fslot] <= want_cls;
                        st <= ST_SRAMP;
                    end else if (!ron[fslot] || (pcls[fslot] != want_cls)) begin
                        // 重新规划：从当前实际偏移出发做一次串行除法，本采样不推进
                        div_dab <= dab; div_rem <= 18'd0; div_q <= 18'd0; div_cnt <= 5'd0;
                        div_neg <= cur_delta[23]; div_cls <= want_cls;
                        st <= ST_DIV;
                    end else begin
                        off[fslot] <= nxt;
                        rrem[fslot] <= remadj[10:0];
                        if (nxt == want_val) ron[fslot] <= 1'b0;
                        st <= ST_SRAMP;
                    end
                end
                ST_DIV: begin
                    if (div_cnt == 5'd18) begin
                        rneg[fslot] <= div_neg;
                        rq[fslot] <= div_q[10:0];
                        rr[fslot] <= div_rem[10:0];
                        rrem[fslot] <= 11'd0;
                        ron[fslot] <= 1'b1;
                        pcls[fslot] <= div_cls;
                        st <= ST_DRAMP;
                    end else begin
                        if ({div_rem[16:0], div_dab[17]} >= {6'd0, NSAMP}) begin
                            div_rem <= {div_rem[16:0], div_dab[17]} - {6'd0, NSAMP};
                            div_q <= {div_q[16:0], 1'b1};
                        end else begin
                            div_rem <= {div_rem[16:0], div_dab[17]};
                            div_q <= {div_q[16:0], 1'b0};
                        end
                        div_dab <= {div_dab[16:0], 1'b0};
                        div_cnt <= div_cnt + 5'd1;
                    end
                end
                ST_SRAMP: begin
                    if (slide_plan) begin
                        // 新目标品位：从当前实际位置规划一段滑音（时长按当前档位锁存）
                        sdiv_dab <= sdelta[17] ? -sdelta[16:0] : sdelta[16:0];
                        sdiv_rem <= 18'd0; sdiv_q <= 18'd0; sdiv_cnt <= 5'd0;
                        sdiv_neg <= sdelta[17];
                        sn_lat <= slide_samples;
                        stgt <= stgt_now; stgt_fret <= fret_sel;
                        applied_fret <= fret_sel; slide_on <= 1'b0;
                        st <= ST_SDIV;
                    end else if (lead_valid && (lead_slot == fslot) && slide_on) begin
                        pos[fslot] <= sd_nxt;
                        srem <= ssum_adj;
                        if (sd_nxt == stgt) begin slide_on <= 1'b0; applied_fret <= stgt_fret; end
                        st <= ST_DRAMP;
                    end else st <= ST_DRAMP;
                end
                ST_SDIV: begin
                    if (sdiv_cnt == 5'd17) begin
                        sq <= sdiv_q[6:0];
                        sr <= sdiv_rem[13:0];
                        sneg <= sdiv_neg;
                        srem <= 14'd0;
                        slide_on <= 1'b1;
                        st <= ST_DRAMP;
                    end else begin
                        if ({sdiv_rem[16:0], sdiv_dab[16]} >= {3'd0, sn_lat}) begin
                            sdiv_rem <= {sdiv_rem[16:0], sdiv_dab[16]} - {3'd0, sn_lat};
                            sdiv_q <= {sdiv_q[16:0], 1'b1};
                        end else begin
                            sdiv_rem <= {sdiv_rem[16:0], sdiv_dab[16]};
                            sdiv_q <= {sdiv_q[16:0], 1'b0};
                        end
                        sdiv_dab <= {sdiv_dab[15:0], 1'b0};
                        sdiv_cnt <= sdiv_cnt + 5'd1;
                    end
                end
                ST_DRAMP: begin
                    // 深度渐变：从当前实际深度重规划/推进（终点精确，N=965时商0/1）
                    if (ddelta == 13'sd0) begin
                        don[fslot] <= 1'b0;
                        dcls[fslot] <= dwant_hi;
                    end else if (!don[fslot] || (dcls[fslot] != dwant_hi)) begin
                        dneg[fslot] <= ddelta[12];
                        dq[fslot] <= dq_c;
                        dr[fslot] <= dr_c;
                        drem[fslot] <= 10'd0;
                        don[fslot] <= 1'b1;
                        dcls[fslot] <= dwant_hi;
                    end else begin
                        dpth[fslot] <= dnxt;
                        drem[fslot] <= dsum_adj;
                        if (dnxt == (dwant_hi ? VP12 : 12'd0)) don[fslot] <= 1'b0;
                    end
                    st <= ST_VIB;
                end
                ST_VIB: begin
                    vib_off <= (vib_prod + 25'sd2048) >>> 12;   // 深度×波形，Q12取整
                    st <= ST_ISSUE;
                end
                ST_ISSUE: begin
                    ridx <= idx_v;
                    rfrac <= frac_v;
                    rtag <= gen[fslot];
                    st <= ST_RD0;
                end
                ST_RD0: begin
                    rr0 <= rom_data;
                    st <= ST_RD1;
                end
                ST_RD1: begin
                    rr1 <= rom_data;
                    st <= ST_MUL;
                end
                ST_MUL: begin
                    iprod <= interp_p;
                    st <= ST_COMMIT;
                end
                ST_COMMIT: begin
                    // 代次校验：转换期间槽被重新触发则丢弃本次提交
                    if (gen[fslot] == rtag) ratio[fslot] <= interp_val;
                    if (fslot == 3'd5) st <= ST_TAIL;
                    else begin fslot <= fslot + 3'd1; st <= ST_RAMP; end
                end
                ST_TAIL: begin
                    // 扫描期到达的触发：间隙内补提交1.0（不覆盖扫描中的倍率）
                    for (k = 0; k < 6; k = k + 1) begin
                        if (unity_pend[k]) begin ratio[k] <= fret_ratio(pend_fret[k]); unity_pend[k] <= 1'b0; end
                    end
                    st <= ST_IDLE;
                end
                default: st <= ST_IDLE;
            endcase

            // ---------- 触发与代次（写在状态机之后：同拍优先） ----------
            if (trig[0]) begin
                gen[0] <= gen[0] + 4'd1; off[0] <= 24'sd0; ron[0] <= 1'b0; pcls[0] <= 2'd0;
                dpth[0] <= 12'd0; don[0] <= 1'b0; dcls[0] <= 1'b0;
                pos[0] <= {trig_fret[3:0], 12'd0};
                pend_fret[0] <= trig_fret[3:0];
                if (gap_cnt >= SAFE_CNT) ratio[0] <= fret_ratio(trig_fret[3:0]); else unity_pend[0] <= 1'b1;
                if (trig_usb[0]) begin lead_valid <= 1'b1; lead_slot <= 3'd0; applied_fret <= trig_fret[3:0]; slide_on <= 1'b0; end
                else if (lead_valid && (lead_slot == 3'd0)) lead_valid <= 1'b0;
            end
            if (trig[1]) begin
                gen[1] <= gen[1] + 4'd1; off[1] <= 24'sd0; ron[1] <= 1'b0; pcls[1] <= 2'd0;
                dpth[1] <= 12'd0; don[1] <= 1'b0; dcls[1] <= 1'b0;
                pos[1] <= {trig_fret[7:4], 12'd0};
                pend_fret[1] <= trig_fret[7:4];
                if (gap_cnt >= SAFE_CNT) ratio[1] <= fret_ratio(trig_fret[7:4]); else unity_pend[1] <= 1'b1;
                if (trig_usb[1]) begin lead_valid <= 1'b1; lead_slot <= 3'd1; applied_fret <= trig_fret[7:4]; slide_on <= 1'b0; end
                else if (lead_valid && (lead_slot == 3'd1)) lead_valid <= 1'b0;
            end
            if (trig[2]) begin
                gen[2] <= gen[2] + 4'd1; off[2] <= 24'sd0; ron[2] <= 1'b0; pcls[2] <= 2'd0;
                dpth[2] <= 12'd0; don[2] <= 1'b0; dcls[2] <= 1'b0;
                pos[2] <= {trig_fret[11:8], 12'd0};
                pend_fret[2] <= trig_fret[11:8];
                if (gap_cnt >= SAFE_CNT) ratio[2] <= fret_ratio(trig_fret[11:8]); else unity_pend[2] <= 1'b1;
                if (trig_usb[2]) begin lead_valid <= 1'b1; lead_slot <= 3'd2; applied_fret <= trig_fret[11:8]; slide_on <= 1'b0; end
                else if (lead_valid && (lead_slot == 3'd2)) lead_valid <= 1'b0;
            end
            if (trig[3]) begin
                gen[3] <= gen[3] + 4'd1; off[3] <= 24'sd0; ron[3] <= 1'b0; pcls[3] <= 2'd0;
                dpth[3] <= 12'd0; don[3] <= 1'b0; dcls[3] <= 1'b0;
                pos[3] <= {trig_fret[15:12], 12'd0};
                pend_fret[3] <= trig_fret[15:12];
                if (gap_cnt >= SAFE_CNT) ratio[3] <= fret_ratio(trig_fret[15:12]); else unity_pend[3] <= 1'b1;
                if (trig_usb[3]) begin lead_valid <= 1'b1; lead_slot <= 3'd3; applied_fret <= trig_fret[15:12]; slide_on <= 1'b0; end
                else if (lead_valid && (lead_slot == 3'd3)) lead_valid <= 1'b0;
            end
            if (trig[4]) begin
                gen[4] <= gen[4] + 4'd1; off[4] <= 24'sd0; ron[4] <= 1'b0; pcls[4] <= 2'd0;
                dpth[4] <= 12'd0; don[4] <= 1'b0; dcls[4] <= 1'b0;
                pos[4] <= {trig_fret[19:16], 12'd0};
                pend_fret[4] <= trig_fret[19:16];
                if (gap_cnt >= SAFE_CNT) ratio[4] <= fret_ratio(trig_fret[19:16]); else unity_pend[4] <= 1'b1;
                if (trig_usb[4]) begin lead_valid <= 1'b1; lead_slot <= 3'd4; applied_fret <= trig_fret[19:16]; slide_on <= 1'b0; end
                else if (lead_valid && (lead_slot == 3'd4)) lead_valid <= 1'b0;
            end
            if (trig[5]) begin
                gen[5] <= gen[5] + 4'd1; off[5] <= 24'sd0; ron[5] <= 1'b0; pcls[5] <= 2'd0;
                dpth[5] <= 12'd0; don[5] <= 1'b0; dcls[5] <= 1'b0;
                pos[5] <= {trig_fret[23:20], 12'd0};
                pend_fret[5] <= trig_fret[23:20];
                if (gap_cnt >= SAFE_CNT) ratio[5] <= fret_ratio(trig_fret[23:20]); else unity_pend[5] <= 1'b1;
                if (trig_usb[5]) begin lead_valid <= 1'b1; lead_slot <= 3'd5; applied_fret <= trig_fret[23:20]; slide_on <= 1'b0; end
                else if (lead_valid && (lead_slot == 3'd5)) lead_valid <= 1'b0;
            end

            // ---------- 演示/断连使目标失效（保留偏移做平滑回中） ----------
            if (!connected || demo) begin lead_valid <= 1'b0; slide_on <= 1'b0; end
            // Space/Esc：取消当前滑音（位置冻结；清音优先级由原机制处理）
            if (gtr_inhibit || kill) slide_on <= 1'b0;
            // 箭头重连resync：断连后须先松开两键
            if (!connected) arrow_resync <= 1'b1;
            else if (!bend_left && !bend_right) arrow_resync <= 1'b0;
            // V重连resync：断连后须先松开V再启用
            if (!connected) vib_resync <= 1'b1;
            else if (!vib_hold) vib_resync <= 1'b0;

            // ---------- Esc清理：直接丢弃全部表情事务 ----------
            if (kill) begin
                lead_valid <= 1'b0; unity_pend <= 6'd0; st <= ST_IDLE; slide_on <= 1'b0; applied_fret <= 4'd0;
                for (k = 0; k < 6; k = k + 1) begin
                    off[k] <= 24'sd0; ron[k] <= 1'b0; pcls[k] <= 2'd0;
                    rq[k] <= 11'd0; rr[k] <= 11'd0; rrem[k] <= 11'd0; rneg[k] <= 1'b0;
                    dpth[k] <= 12'd0; don[k] <= 1'b0; dcls[k] <= 1'b0;
                    pos[k] <= 17'd0; pend_fret[k] <= 4'd0;
                    ratio[k] <= RATIO_ONE;
                end
            end
        end
    end

    assign slot_ratio = {ratio[5], ratio[4], ratio[3], ratio[2], ratio[1], ratio[0]};
endmodule
