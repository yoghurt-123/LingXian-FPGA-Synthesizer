// D：USB和弦执行器（U/I/O/P选预设并三音齐奏；单弦走独立六弦入口）。
// 三段式：整份快照事件锁存 → 4深命令FIFO → 三槽准备(RESERVE/FADE_WAIT/WRITE_META/ARMED)→统一提交。
// 槽0..2为和弦槽（可编程base_note/velocity/mute/fret由顶层ch_note/ch_vel寄存器承载）；
// E2单音、触摸和弦、演示进入时由顶层显式写回各自原字段。取消最高优先级，最终fire端再次禁止。
module guitar_chord_engine (
    input clk, input rst_n, input sample_tick,
    input [3:0] chord_key,      // {P,O,I,U} 音频域保持（bit0=U=C, bit1=I=G, bit2=O=Dm, bit3=P=Am）
    input ble_select_we,        // BLE chord selection (no trigger)
    input [1:0] ble_select,
    input ble_trigger,          // BLE trigger selected chord
    input [3:0] ble_vel,
    input ble_palm,
    input ble_release,          // cancel a pending BLE trigger only
    input [3:0] vel_now,        // 本报告有效力度（USB小键盘/Shift后的有效值）
    input ctrl_in,              // 本报告有效左Ctrl
    input cancel,               // Space/Esc/断连/模式切换（音频域，电平）
    input fx_ready,             // 目标效果==实际效果（统一效果切换握手）
    output reg chord_mute_req,  // 等效果切换时的平滑制音请求
    input [5:0] slot_busy,      // 音源槽占用（pending|playing）
    input [11:0] ch_bases,      // 顶层槽0..2当前base_note反馈 {n2,n1,n0}
    output reg chord_wr,        // 元数据写使能（逐槽）
    output reg [1:0] wr_slot,
    output reg [3:0] wr_note,
    output reg [3:0] wr_vel_meta, // 预留（顶层写ch_vel的字段）
    output reg [5:0] ch_trig,
    output reg [23:0] ch_trig_fret,
    output reg [5:0] ch_trig_mute,
    output reg [5:0] ch_fade,   // 槽0..2淡出请求
    output chord_hold,          // 执行器忙：单弦E2/触摸和弦/扫弦请求等待（不可丢弃）
    output reg [15:0] chord_overflow
);
    localparam [1:0] DIR_L = 2'd0, DIR_J = 2'd1, DIR_K = 2'd2;
    localparam [2:0] S_IDLE=3'd0, S_RESERVE=3'd1, S_FADE=3'd2, S_WRITE=3'd3,
                     S_ARM=3'd4, S_FIRE=3'd5, S_WAIT=3'd6, S_DONE=3'd7;
    // ---- 报告事件锁存 ----
    reg [3:0] key_d;
    wire [3:0] key_press = chord_key & ~key_d;
    reg [1:0] preset;
    // ---- FIFO ----
    reg [8:0] fifo [0:3];
    reg [1:0] fifo_wr, fifo_rd;
    reg [2:0] fifo_cnt;
    reg ble_pend;
    // ---- 执行器 ----
    reg [2:0] st;
    reg [1:0] c_preset, c_dir;
    reg [3:0] c_vel;
    reg c_ctrl;
    reg [3:0] note_k0, note_k1, note_k2;
    reg [3:0] fret_k0, fret_k1, fret_k2;
    reg [1:0] step;             // 已发起的音序号 0..2
    reg [15:0] wait_cnt;
    reg [2:0] wr_cnt;
    reg mute_off;               // 握手：效果提交后先撤销静音至少一拍，再起音
    wire cancel_now = cancel;
    // 预设音/品表（物理弦品：slot0/1/2=三根最低弦的基音×品位倍率）
    wire [3:0] new_preset = key_press;
    wire preset_ok = (new_preset == 4'b0001) || (new_preset == 4'b0010) || (new_preset == 4'b0100) || (new_preset == 4'b1000);
    wire [1:0] preset_new = (new_preset == 4'b0001) ? 2'd0 : (new_preset == 4'b0010) ? 2'd1 : (new_preset == 4'b0100) ? 2'd2 : 2'd3;
    wire [1:0] preset_eff = preset_ok ? preset_new : preset;
    // U/I/O/P 按下即演奏该和弦（三音齐奏）；多键同报不是合法单新选，不改变预设
    wire cmd_press = preset_ok;
    wire [1:0] cmd_dir = DIR_L;
    wire [8:0] cmd_val = {preset_eff, cmd_dir, vel_now, ctrl_in};
    wire exec_idle = (st == S_IDLE);
    wire pop_w = exec_idle && (fifo_cnt != 3'd0) && !cancel_now;
    wire push_w = cmd_press && !cancel_now && ((fifo_cnt < 3'd4) || pop_w);
    wire ble_push_w = ble_pend && !cancel_now && !push_w && ((fifo_cnt < 3'd4) || pop_w);
    wire [2:0] cnt_next = fifo_cnt + push_w + ble_push_w - pop_w;
    wire [8:0] head = fifo[fifo_rd];
    wire [8:0] ble_cmd = {preset, DIR_L, ble_vel, ble_palm};
    // 槽准备参数（选择表，寄存器化进执行器）
    function [3:0] note_of; input [1:0] p; input [1:0] k; begin
        case (p)
            2'd0: note_of = (k==2'd0) ? 4'd3 : (k==2'd1) ? 4'd4 : 4'd5;   // Q=C: A2,D3,G3
            2'd1: note_of = (k==2'd0) ? 4'd0 : (k==2'd1) ? 4'd3 : 4'd4;   // W=G: E2,A2,D3
            2'd2: note_of = (k==2'd0) ? 4'd4 : (k==2'd1) ? 4'd4 : 4'd5;   // E=Dm: D3,D3,G3
            default: note_of = (k==2'd0) ? 4'd3 : (k==2'd1) ? 4'd4 : 4'd6; // R=Am: A2,D3,B3
        endcase
    end endfunction
    function [3:0] fret_of; input [1:0] p; input [1:0] k; begin
        case (p)
            2'd0: fret_of = (k==2'd0) ? 4'd3 : (k==2'd1) ? 4'd2 : 4'd0; // Q=C: A2+3, D3+2, G3+0
            2'd1: fret_of = (k==2'd0) ? 4'd3 : (k==2'd1) ? 4'd2 : 4'd0; // W=G: E2+3, A2+2, D3+0
            2'd2: fret_of = (k==2'd0) ? 4'd0 : (k==2'd1) ? 4'd3 : 4'd2; // E=Dm: D3+0, D3+3, G3+2
            default: fret_of = (k==2'd0) ? 4'd0 : (k==2'd1) ? 4'd2 : 4'd1; // R=Am: A2+0, D3+2, B3+1
        endcase
    end endfunction
    // 淡出所需：槽忙且base不同才淡出；同base直接重触发
    wire [2:0] need_fade = { slot_busy[2] && (ch_bases[11:8] != note_k2),
                             slot_busy[1] && (ch_bases[7:4]  != note_k1),
                             slot_busy[0] && (ch_bases[3:0]  != note_k0) };
    wire [2:0] still_busy = { slot_busy[2] ^ (ch_bases[11:8] != note_k2),
                              slot_busy[1] ^ (ch_bases[7:4]  != note_k1),
                              slot_busy[0] ^ (ch_bases[3:0]  != note_k0) };
    // 方向顺序：J 正向0→2，K 反向2→0
    wire [1:0] seq_idx = (c_dir == DIR_K) ? (2'd2 - step) : step;
    assign chord_hold = (st != S_IDLE) && !cancel_now;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_d <= 4'd0; preset <= 2'd0;
            fifo_wr <= 2'd0; fifo_rd <= 2'd0; fifo_cnt <= 3'd0; ble_pend <= 1'b0;
            st <= S_IDLE; c_preset <= 2'd0; c_dir <= 2'd0; c_vel <= 4'd15; c_ctrl <= 1'b0;
            note_k0 <= 4'd0; note_k1 <= 4'd3; note_k2 <= 4'd4;
            fret_k0 <= 4'd0; fret_k1 <= 4'd2; fret_k2 <= 4'd2;
            step <= 2'd0; wait_cnt <= 16'd0; wr_cnt <= 3'd0; mute_off <= 1'b0;
            chord_wr <= 1'b0; wr_slot <= 2'd0; wr_note <= 4'd0; wr_vel_meta <= 4'd15;
            ch_trig <= 6'd0; ch_trig_fret <= 24'd0; ch_trig_mute <= 6'd0; ch_fade <= 6'd0; chord_mute_req <= 1'b0;
            chord_overflow <= 16'd0;
        end else begin
            ch_trig <= 6'd0; ch_trig_fret <= 24'd0; ch_trig_mute <= 6'd0;
            ch_fade <= 6'd0; chord_wr <= 1'b0;
            if (ble_select_we) preset <= ble_select;
            if (ble_trigger) ble_pend <= 1'b1;
            if (ble_release) ble_pend <= 1'b0;
            if (sample_tick) begin
                key_d <= chord_key;
                // 预设：唯一新选才更新；重复同键/多键同拍无副作用
                if (preset_ok) preset <= preset_new;
                // FIFO 统一下一状态（计数只提交一次）
                fifo_cnt <= cnt_next;
                if (push_w) begin fifo[fifo_wr] <= cmd_val; fifo_wr <= fifo_wr + 2'd1; end
                if (ble_push_w) begin
                    fifo[fifo_wr] <= ble_cmd;
                    fifo_wr <= fifo_wr + 2'd1;
                    ble_pend <= 1'b0;
                end
                if (pop_w) fifo_rd <= fifo_rd + 2'd1;
                if (cmd_press && !push_w && !cancel_now) begin
                    if (chord_overflow != 16'hFFFF) chord_overflow <= chord_overflow + 16'd1;
                end
                if (ble_pend && !ble_push_w && !cancel_now) begin
                    if (chord_overflow != 16'hFFFF) chord_overflow <= chord_overflow + 16'd1;
                end
            end
            // 执行器
            case (st)
                S_IDLE: begin
                    if (sample_tick && pop_w) begin
                        c_preset <= head[8:7]; c_dir <= head[6:5]; c_vel <= head[4:1]; c_ctrl <= head[0];
                        note_k0 <= note_of(head[8:7], 2'd0); note_k1 <= note_of(head[8:7], 2'd1); note_k2 <= note_of(head[8:7], 2'd2);
                        fret_k0 <= fret_of(head[8:7], 2'd0); fret_k1 <= fret_of(head[8:7], 2'd1); fret_k2 <= fret_of(head[8:7], 2'd2);
                        step <= 2'd0; wr_cnt <= 3'd0; mute_off <= 1'b0;
                        st <= S_RESERVE;
                    end
                end
                S_RESERVE: begin
                    if (need_fade != 3'b000) begin
                        ch_fade <= {3'b0, need_fade};
                        st <= S_FADE;
                    end else st <= S_WRITE;
                end
                S_FADE: begin
                    ch_fade <= {3'b0, need_fade};
                    if (need_fade == 3'b000) st <= S_WRITE;
                end
                S_WRITE: begin
                    if (sample_tick) begin
                        chord_wr <= 1'b1;
                        wr_slot <= wr_cnt[1:0];
                        case (wr_cnt)
                            3'd0: begin wr_note <= note_k0; wr_vel_meta <= (c_vel > 4'd7) ? 4'd7 : c_vel; end
                            3'd1: begin wr_note <= note_k1; wr_vel_meta <= (c_vel > 4'd7) ? 4'd7 : c_vel; end
                            default: begin wr_note <= note_k2; wr_vel_meta <= (c_vel > 4'd7) ? 4'd7 : c_vel; end
                        endcase
                        if (wr_cnt == 3'd2) st <= S_ARM;
                        else wr_cnt <= wr_cnt + 3'd1;
                    end
                end
                S_ARM: begin
                    if (sample_tick) begin
                        if (fx_ready) begin
                            // Release global mute before submitting the saved chord.
                            chord_mute_req <= 1'b0;
                            step <= 2'd0; st <= S_FIRE;
                        end
                        else chord_mute_req <= 1'b1;   // 暂存命令，请求平滑制音，等待效果提交后再起音
                    end
                end
                S_FIRE: begin
                    if (!fx_ready) begin
                        // The target may change again between ARM and FIRE.
                        chord_mute_req <= 1'b1;
                        st <= S_ARM;
                    end else if (sample_tick) begin
                        // 统一提交：L 三音同位；J/K 先发方向首音
                        if (c_dir == DIR_L) begin
                            ch_trig <= 6'b000111;
                            ch_trig_fret <= {4'd0, 4'd0, fret_k2, fret_k1, fret_k0};
                            ch_trig_mute <= {3'b0, {3{c_ctrl}}};
                            st <= S_DONE;
                        end else begin
                            case (seq_idx)
                                2'd0: begin ch_trig <= 6'b000001; ch_trig_fret <= {20'd0, fret_k0}; end
                                2'd1: begin ch_trig <= 6'b000010; ch_trig_fret <= {16'd0, fret_k1, 4'd0}; end
                                default: begin ch_trig <= 6'b000100; ch_trig_fret <= {12'd0, fret_k2, 8'd0}; end
                            endcase
                            ch_trig_mute <= {3'b0, {3{c_ctrl}}};
                            step <= 2'd1;
                            wait_cnt <= (c_dir == DIR_J) ? 16'd385 : 16'd289;
                            st <= S_WAIT;
                        end
                    end
                end
                S_WAIT: begin
                    if (sample_tick) begin
                        if (wait_cnt != 16'd0) wait_cnt <= wait_cnt - 16'd1;
                        else begin
                            case (seq_idx)
                                2'd0: begin ch_trig <= 6'b000001; ch_trig_fret <= {20'd0, fret_k0}; end
                                2'd1: begin ch_trig <= 6'b000010; ch_trig_fret <= {16'd0, fret_k1, 4'd0}; end
                                default: begin ch_trig <= 6'b000100; ch_trig_fret <= {12'd0, fret_k2, 8'd0}; end
                            endcase
                            ch_trig_mute <= {3'b0, {3{c_ctrl}}};
                            if (step == 2'd2) st <= S_DONE;
                            else begin
                                step <= step + 2'd1;
                                wait_cnt <= (c_dir == DIR_J) ? 16'd385 : 16'd289;
                            end
                        end
                    end
                end
                S_DONE: begin
                    if (sample_tick) st <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
            // 取消最高优先级：清队列与执行状态，并禁止当拍提交
            if (cancel_now) begin
                st <= S_IDLE; fifo_cnt <= 3'd0; fifo_wr <= 2'd0; fifo_rd <= 2'd0; mute_off <= 1'b0; ble_pend <= 1'b0;
                ch_trig <= 6'd0; ch_trig_fret <= 24'd0; ch_trig_mute <= 6'd0; ch_fade <= 6'd0; chord_mute_req <= 1'b0;
                chord_wr <= 1'b0; chord_mute_req <= 1'b0;
            end
        end
    end
endmodule
