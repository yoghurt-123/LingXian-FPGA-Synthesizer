// 吉他声部控制：USB六弦请求锁存与调度、平滑制音、清音/过载切换。
// S2模式解耦后不再有吉他/钢琴互斥；请求只来自USB QWERTY、和弦UIOP、F3效果和F6演示。
// 旧触摸吉他分支（KEY7齐奏/KEY8制音/KEY9效果/KEY10扫弦）已删除，TTP固定钢琴。
// ★请求锁存（本轮重构）：每个按键一位独立锁存（req_pend），先锁存再调度——
//   同拍多键任意组合都不丢失；没有 if/else 默认分支（结构上消除“默认落到 E2”的幽灵触发）。
//   调度在每个采样节拍执行一个请求（同拍多请求按固定位序逐拍执行，间隔 21us 不可闻）。
// ★单音弦池分配：槽3..5 动态分配 A2/D3/G3/B3/E4：
//   同音重复触发优先复用原槽（立即重触发）；否则空闲槽优先；满槽替换"最早触发"的声部：
//   先按槽 1~2ms 淡出，等槽释放后再写音色字段（按槽锁存，旧音发声中绝不改）并触发。
// ★效果切换：F3 只改选择（不拨弦、不触发）；有空闲即静音应用；发声中切换先平滑制音等待，
//   不产生、不遗留、不补发任何演奏请求（请求本来就来自按键锁存）。
// ★制音（USB Space/断连/Esc）：清空全部待播放/替换请求并平滑制音。
module guitar_ctrl #(
    parameter integer FX_SETTLE  = 724    // ★音色切换前的效果器尾音等待采样数：724≈15ms
)(
    input clk, input rst_n, input sample_tick,
    input pluck_solo,         // USB Q E2
    input pluck_a2,           // USB W A2（第5弦空弦）
    input pluck_d3,           // USB E D3（第4弦空弦）
    input pluck_g3,           // USB R G3（第3弦空弦）
    input pluck_b3,           // USB T B3（第2弦空弦）
    input pluck_e4,           // USB Y E4（第1弦空弦）
    input mute_key,           // USB Space/断连/Esc 制音
    input pool_reset,         // 演示播放器结束：复位池分配状态（软复位）
    input fx_key,             // USB F3 清音/过载切换
    input [5:0] pluck_usb,    // ★USB手动来源掩码（与pluck_solo..e4同拍）：供弯音主奏绑定
    input [3:0] fret_in,      // ★本拍有效品位选择（同报告选品优先，见guitar_expression_keys）
    input ctrl_in,            // ★左Ctrl：USB手持拨弦的掌根闷音修饰（随请求锁存）
    input chord_hold,         // ★D：和弦执行器忙，E2请求等待（不可丢弃）
    input [5:0] slot_busy,    // 池槽占用反馈（bit3..5，来自音源：pending|playing）
    input [23:0] pluck_vel,
    input [5:0] ble_pluck,
    input [3:0] ble_fret,
    input [3:0] ble_vel,
    input ble_palm,
    input ble_fx_set,
    input ble_fx_value,   // ★各请求键力度码（4位/键：[3:0]=E2 [7:4]=A2 [11:8]=D3 [15:12]=G3 [19:16]=B3 [23:20]=E4）
    output reg [5:0] fade_req,// 按槽替换淡出请求（1~2ms 短释放，独立于全局制音）
    output reg solo_wr,       // 池槽音色字段写使能（仅在槽空闲时写）
    output reg [1:0] solo_slot,
    output reg [3:0] solo_note,
    output reg [3:0] solo_vel,// ★本轮：随音色字段一起写出的力度码
    output reg e2_vel_wr,     // ★本轮：E2专用槽力度字段写使能
    output reg [3:0] e2_vel,  // ★本轮：E2专用槽力度码（齐奏/扫弦按触摸默认15）
    input voice_active,       // 吉他音源是否在发声（含制音释放中）
    output reg [5:0] trig,    // 拨弦触发（每声部一位）
    output reg [5:0] trig_usb,// ★本拍触发的USB手动来源位（与trig同拍，槽位对应）
    output reg [23:0] trig_fret,// ★本拍触发的品位（6槽×4位，非USB源为0）
    output reg [5:0] trig_mute, // ★本拍触发的掌根闷音（6槽×1位，仅USB来源）
    output reg voice_mute,    // 平滑制音脉冲
    output reg drv_sel,       // 音频路径：0=清音 1=过载（只在静音后改变）
    output reg fx_wanted      // 已选择的音色（彩灯显示/下次演奏用）
);
    localparam N_A2 = 4'd3, N_D3 = 4'd4, N_G3 = 4'd5, N_B3 = 4'd6, N_E4 = 4'd7;   // guitar_note_params.vh 音色号（0..9 四位）
    reg [9:0] settle;                 // 效果尾音等待计数
    reg [5:0] next_trig;
    // ★请求锁存（每键一位）：bit0=E2 1=A2 2=D3 3=G3 4=B3 5=E4
    reg [5:0] req_pend;
    // ★本轮：每请求键的力度元数据，在收到pluck时锁存（有效性跟随req_pend位/rep_valid，清除请求即失效）
    reg [3:0] req_vel [0:5];
    reg [5:0] req_usb;                // ★每请求键的USB来源（与req_pend同步锁存）
    reg [3:0] req_fret [0:5];         // ★每请求键的品位（USB手动）
    reg [3:0] rep_fret;
    reg [5:0] req_mute;               // ★每请求键的掌根闷音（仅USB来源时取Ctrl）
    reg rep_mute;
    // ---- 单音弦池状态 ----
    reg [3:0] pool_note [0:2];        // 池槽当前音色（与音源 note_lat/top 字段一致，仅在写字段时更新）
    reg [1:0] pool_age  [0:2];        // 触发新旧：越大越新（≤3）；"最早触发"=最小
    reg rep_valid;                    // 替换等待中：淡出完成→写音色→触发
    reg rep_usb;                      // ★替换等待携带的USB来源位
    reg [1:0] rep_slot; reg [3:0] rep_note; reg [1:0] rep_tt;
    reg [3:0] rep_velocity;           // ★本轮：替换等待携带的力度（淡出完成后与音色一起提交）
    reg [3:0] pnote; reg [3:0] pnote_vel; reg [3:0] pnote_fret; reg pnote_mute; reg pnote_usb; reg [1:0] smatch, sfree, sold, ssel, minage;   // 分配临时量
    integer kk;                       // 分配循环变量
    // 音源静音判定：音源不发声，且效果链残余尾音等待结束（不依赖瞬时 PCM 过零）
    wire voice_quiet = (!voice_active) && (settle == 10'd0);
    wire fx_ok = (fx_wanted == drv_sel) || voice_quiet;   // 音色已一致或已静音：可调度/应用
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            settle <= 10'd0;
        end else if (sample_tick) begin
            if (voice_active) settle <= FX_SETTLE;
            else if (settle != 10'd0) settle <= settle - 1'b1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trig <= 6'b000000; trig_usb <= 6'b000000; trig_fret <= 24'd0; trig_mute <= 6'b000000; voice_mute <= 1'b0; drv_sel <= 1'b0; fx_wanted <= 1'b0;
            req_pend <= 6'd0;
            fade_req <= 6'b000000; solo_wr <= 1'b0; solo_slot <= 2'd0; solo_note <= 3'd0;
            solo_vel <= 4'd15; e2_vel_wr <= 1'b0; e2_vel <= 4'd15; rep_velocity <= 4'd15;
            for (kk = 0; kk < 6; kk = kk + 1) req_vel[kk] <= 4'd15;
            req_usb <= 6'b000000;
            for (kk = 0; kk < 6; kk = kk + 1) req_fret[kk] <= 4'd0;
            rep_fret <= 4'd0; rep_mute <= 1'b0; req_mute <= 6'b000000;
            pool_note[0] <= N_A2; pool_note[1] <= N_D3; pool_note[2] <= N_G3;
            pool_age[0] <= 2'd0; pool_age[1] <= 2'd0; pool_age[2] <= 2'd0;
            rep_valid <= 1'b0; rep_slot <= 2'd0; rep_note <= 3'd0; rep_tt <= 2'd0; rep_usb <= 1'b0;
        end else begin
            trig <= 6'b000000; trig_usb <= 6'b000000; trig_fret <= 24'd0; trig_mute <= 6'b000000; voice_mute <= 1'b0; solo_wr <= 1'b0; e2_vel_wr <= 1'b0;
            // F3 效果选择：只改选择，不拨弦、不触发（应用见下方静音判定）
            if (fx_key) fx_wanted <= ~fx_wanted;
            if (ble_fx_set) fx_wanted <= ble_fx_value;
            if (mute_key) begin
                // Space/断连/Esc：取消待播放/替换请求，平滑制音后保持静音
                req_pend <= 6'd0;
                rep_valid <= 1'b0; rep_tt <= 2'd0; fade_req <= 6'b000000;
                voice_mute <= 1'b1;
            end
            else begin
                // 演示结束的池状态复位（与手动调度独立，软复位）
                if (pool_reset) begin
                    pool_note[0] <= N_A2; pool_note[1] <= N_D3; pool_note[2] <= N_G3;
                    pool_age[0] <= 2'd0; pool_age[1] <= 2'd0; pool_age[2] <= 2'd0;
                    rep_valid <= 1'b0; rep_tt <= 2'd0; fade_req <= 6'b000000;
                end
                // ---- 请求锁存：每键独立一位，同拍任意组合都不丢失；力度随请求一起锁存 ----
                if (pluck_solo)  begin req_pend[0] <= 1'b1; req_vel[0] <= pluck_vel[3:0]; req_usb[0] <= pluck_usb[0]; req_fret[0] <= fret_in; req_mute[0] <= pluck_usb[0] & ctrl_in; end
                if (pluck_a2)    begin req_pend[1] <= 1'b1; req_vel[1] <= pluck_vel[7:4]; req_usb[1] <= pluck_usb[1]; req_fret[1] <= fret_in; req_mute[1] <= pluck_usb[1] & ctrl_in; end
                if (pluck_d3)    begin req_pend[2] <= 1'b1; req_vel[2] <= pluck_vel[11:8]; req_usb[2] <= pluck_usb[2]; req_fret[2] <= fret_in; req_mute[2] <= pluck_usb[2] & ctrl_in; end
                if (pluck_g3)    begin req_pend[3] <= 1'b1; req_vel[3] <= pluck_vel[15:12]; req_usb[3] <= pluck_usb[3]; req_fret[3] <= fret_in; req_mute[3] <= pluck_usb[3] & ctrl_in; end
                if (pluck_b3)    begin req_pend[4] <= 1'b1; req_vel[4] <= pluck_vel[19:16]; req_usb[4] <= pluck_usb[4]; req_fret[4] <= fret_in; req_mute[4] <= pluck_usb[4] & ctrl_in; end
                if (pluck_e4)    begin req_pend[5] <= 1'b1; req_vel[5] <= pluck_vel[23:20]; req_usb[5] <= pluck_usb[5]; req_fret[5] <= fret_in; req_mute[5] <= pluck_usb[5] & ctrl_in; end
                // BLE requests use the same per-key latch, but carry their own
                // fret/velocity/palm metadata. req_usb doubles as the "manual
                // trigger" flag for pitch-bend lead binding.
                if (ble_pluck[0]) begin req_pend[0] <= 1'b1; req_vel[0] <= ble_vel; req_usb[0] <= 1'b1; req_fret[0] <= ble_fret; req_mute[0] <= ble_palm; end
                if (ble_pluck[1]) begin req_pend[1] <= 1'b1; req_vel[1] <= ble_vel; req_usb[1] <= 1'b1; req_fret[1] <= ble_fret; req_mute[1] <= ble_palm; end
                if (ble_pluck[2]) begin req_pend[2] <= 1'b1; req_vel[2] <= ble_vel; req_usb[2] <= 1'b1; req_fret[2] <= ble_fret; req_mute[2] <= ble_palm; end
                if (ble_pluck[3]) begin req_pend[3] <= 1'b1; req_vel[3] <= ble_vel; req_usb[3] <= 1'b1; req_fret[3] <= ble_fret; req_mute[3] <= ble_palm; end
                if (ble_pluck[4]) begin req_pend[4] <= 1'b1; req_vel[4] <= ble_vel; req_usb[4] <= 1'b1; req_fret[4] <= ble_fret; req_mute[4] <= ble_palm; end
                if (ble_pluck[5]) begin req_pend[5] <= 1'b1; req_vel[5] <= ble_vel; req_usb[5] <= 1'b1; req_fret[5] <= ble_fret; req_mute[5] <= ble_palm; end
                // 效果待应用且有请求：对现存音平滑制音（缩短等待）；不产生任何触发
                if ((|req_pend) && (fx_wanted != drv_sel) && !voice_quiet) voice_mute <= 1'b1;
                if (sample_tick) begin
                    next_trig = 6'b000000;
                    if (fx_ok) begin
                        // 调度：同拍多请求按固定位序逐拍各执行一个（先锁存、再调度、不吞键）
                        if (req_pend[0] && !chord_hold) begin
                            req_pend[0] <= 1'b0; next_trig = 6'b000001;    // E2 单音
                            trig_usb[0] <= req_usb[0];
                            trig_fret[3:0] <= req_usb[0] ? req_fret[0] : 4'd0;
                            trig_mute[0] <= req_usb[0] ? req_mute[0] : 1'b0;
                            e2_vel <= req_vel[0]; e2_vel_wr <= 1'b1;
                        end
                        else if (|req_pend[5:1]) begin
                            // ★单音弦池分配：同音原槽 → 空闲槽 → 替换最早触发；替换前先按槽淡出
                            if      (req_pend[1]) begin pnote = N_A2; pnote_vel = req_vel[1]; pnote_usb = req_usb[1]; pnote_fret = req_fret[1]; pnote_mute = req_mute[1]; req_pend[1] <= 1'b0; end
                            else if (req_pend[2]) begin pnote = N_D3; pnote_vel = req_vel[2]; pnote_usb = req_usb[2]; pnote_fret = req_fret[2]; pnote_mute = req_mute[2]; req_pend[2] <= 1'b0; end
                            else if (req_pend[3]) begin pnote = N_G3; pnote_vel = req_vel[3]; pnote_usb = req_usb[3]; pnote_fret = req_fret[3]; pnote_mute = req_mute[3]; req_pend[3] <= 1'b0; end
                            else if (req_pend[4]) begin pnote = N_B3; pnote_vel = req_vel[4]; pnote_usb = req_usb[4]; pnote_fret = req_fret[4]; pnote_mute = req_mute[4]; req_pend[4] <= 1'b0; end
                            else                  begin pnote = N_E4; pnote_vel = req_vel[5]; pnote_usb = req_usb[5]; pnote_fret = req_fret[5]; pnote_mute = req_mute[5]; req_pend[5] <= 1'b0; end
                            smatch = 2'd3; sfree = 2'd3; sold = 2'd3; minage = 2'd3;
                            for (kk = 0; kk < 3; kk = kk + 1) begin
                                if (pool_note[kk] == pnote) smatch = kk;
                                if (!slot_busy[kk + 3] && sfree == 2'd3) sfree = kk;   // 最低索引空闲槽
                                if (slot_busy[kk + 3] && pool_age[kk] <= minage) begin minage = pool_age[kk]; sold = kk; end
                            end
                            if (smatch != 2'd3) ssel = smatch;        // 同音复用原槽（忙=立即重触发，与现行为一致）
                            else if (sfree != 2'd3) ssel = sfree;     // 空闲优先
                            else ssel = sold;                          // 满槽：替换最早触发
                            if (slot_busy[ssel + 3] && (pool_note[ssel] != pnote)) begin
                                // 替换：先淡出；等待槽释放后再写音色字段并触发（旧音发声期间不改字段）
                                // 力度随替换等待一起携带，槽释放后与音色一起提交
                                fade_req[ssel + 3] <= 1'b1;
                                rep_valid <= 1'b1; rep_slot <= ssel; rep_note <= pnote; rep_tt <= 2'd0;
                                rep_velocity <= pnote_vel; rep_usb <= pnote_usb; rep_fret <= pnote_fret; rep_mute <= pnote_mute;
                            end else begin
                                // 立即触发（含同音重触发）：音色与力度字段随本次请求一起写出
                                solo_wr <= 1'b1; solo_slot <= ssel; solo_note <= pnote; solo_vel <= pnote_vel;
                                pool_note[ssel] <= pnote;
                                next_trig[ssel + 3] = 1'b1;
                                trig_usb[ssel + 3] <= pnote_usb;
                                trig_fret[{{1'b0,ssel}+3'd3, 2'b00} +: 4] <= pnote_usb ? pnote_fret : 4'd0;
                                trig_mute[{1'b0,ssel}+3'd3] <= pnote_usb ? pnote_mute : 1'b0;
                            end
                            for (kk = 0; kk < 3; kk = kk + 1)
                                pool_age[kk] <= (kk == ssel) ? 2'd3 : ((pool_age[kk] > 2'd0) ? pool_age[kk] - 2'd1 : 2'd0);
                        end
                    end
                    trig <= next_trig;
                    // 静音后应用最新音色（空闲切换与等待切换共用）
                    if (voice_quiet) begin
                        if (fx_wanted != drv_sel) drv_sel <= fx_wanted;
                    end
                end
                // ---- 池替换等待序列：淡出完成（槽空闲）→ 写音色字段（按槽锁存）→ 触发 ----
                if (rep_valid) begin
                    case (rep_tt)
                        2'd0: if (!slot_busy[rep_slot + 3]) begin
                                  solo_wr <= 1'b1; solo_slot <= rep_slot; solo_note <= rep_note;
                                  solo_vel <= rep_velocity;          // 力度与音色同时字段化后触发
                                  pool_note[rep_slot] <= rep_note;
                                  fade_req <= 6'b000000;
                                  rep_tt <= 2'd1;
                              end
                        2'd1: begin solo_wr <= 1'b0; rep_tt <= 2'd2; end
                        2'd2: begin trig[rep_slot + 3] <= 1'b1; trig_usb[rep_slot + 3] <= rep_usb; trig_fret[{{1'b0,rep_slot}+3'd3, 2'b00} +: 4] <= rep_usb ? rep_fret : 4'd0; trig_mute[{1'b0,rep_slot}+3'd3] <= rep_usb ? rep_mute : 1'b0; rep_tt <= 2'd3; end
                        default: begin rep_tt <= 2'd0; rep_valid <= 1'b0; end
                    endcase
                end
            end
        end
    end
endmodule
