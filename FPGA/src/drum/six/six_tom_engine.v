module six_tom_engine(
    input clk,
    input rst_n,
    input sample_tick,
    input [2:0] trig,
    input [3:0] vel,
    input cancel,
    output reg signed [15:0] pcm0, pcm1, pcm2,
    output reg [2:0] out_valid,
    output [2:0] active_o,
    output reg rom_req,
    output reg [12:0] rom_addr,
    input [31:0] rom_data,
    input rom_valid
);
`include "six_drum_defs.vh"
    reg [2:0] c_active;
    assign active_o = c_active;
    localparam [4:0] S_IDLE=0, S_HDR_REQ=1, S_HDR_WAIT=2,
        S_STG_REQ=3, S_STG_WAIT=4, S_PRIME_DONE=5, S_START=6,
        S_POS=7, S_DEC=8, S_DEC_WAIT=9, S_DEC_CODE=10, S_DEC_CHECK=11,
        S_CUR_DONE=12, S_CALC_NEW=13, S_NEW_ONLY=14, S_OLD_ENSURE=15,
        S_CALC_OLD=16, S_CROSS=17, S_OUT=18, S_WAIT=19, S_TAIL=20,
        S_TRANS_COPY=21, S_TRANS_REQ=22, S_TRANS_WAIT=23, S_TRANS_PRIME=24,
        S_LOAD_CTX=25, S_SAVE=26, S_CUB_WAIT=27, S_DEC_CODE2=28, S_DEC_CODE3=29,
        S_LD_WAIT=30, S_SV_WAIT=31;
    reg [4:0] state, dec_ret;
    reg active;
    reg signed [15:0] pcm;
    reg [1:0] ctx;
    reg [12:0] c_base[0:2];
    reg [3:0] c_vel[0:2];
    reg [2:0] c_old_valid;
    reg [2:0] c_pending;

    // Per-context state lives in one 256x32 RAM. The old register arrays
    // cost roughly 3000 FFs (and CLS); serial load/save costs ~55 cycles per
    // context, well inside the 1088-cycle sample budget.
    reg [7:0] ctx_addr;
    reg ctx_we;
    reg [31:0] ctx_wdata;
    wire [31:0] ctx_rdata;
    reg [5:0] ld_idx, sv_idx;
    reg ld_phase, sv_done;
    six_tom_ctx_ram uctx(.clk(clk), .we(ctx_we), .addr(ctx_addr),
                         .wdata(ctx_wdata), .rdata(ctx_rdata));
    reg dec_old;
    reg [15:0] dec_target;
    reg [31:0] ld;
    reg [12:0] base_lat;
    reg [3:0] vel_lat;
    reg [31:0] n, total_n;
    reg [1:0] stage, desc_stage;
    reg [15:0] fade_len;
    reg signed [15:0] tail_coef;
    reg [12:0] desc_off, desc_addr;

    reg [3:0] code_r;
    reg [15:0] diff_r;
    reg signed [8:0] idx_next_r;
    reg [15:0] nsamp_r;
    reg dec_old_r, sign_r;
    reg signed [15:0] decoded_r;
    reg signed [15:0] pred_r_q;

    reg [31:0] cur_start, cur_inc, cur_count, cur_next_start;
    reg [15:0] cur_data;
    reg cur_ar;
    reg [15:0] cur_seed;
    reg [6:0] cur_seedidx;
    reg signed [15:0] cur_p1, cur_p2;
    reg [6:0] cur_idx;
    reg [15:0] cur_nsamp;
    reg [15:0] cur_word_idx;
    reg [31:0] cur_word_data;
    reg cur_word_valid;
    reg signed [15:0] cur_win [0:7];
    reg [63:0] cur_pos;

    reg [31:0] old_start, old_inc, old_count;
    reg [15:0] old_data;
    reg old_ar;
    reg [15:0] old_seed;
    reg [6:0] old_seedidx;
    reg signed [15:0] old_p1, old_p2;
    reg [6:0] old_idx;
    reg [15:0] old_nsamp;
    reg [15:0] old_word_idx;
    reg [31:0] old_word_data;
    reg old_word_valid;
    reg signed [15:0] old_win [0:7];
    reg [63:0] old_pos;
    reg old_valid;
    reg [15:0] fade_cnt, fade_t, fade_err;

    reg signed [15:0] new_val, old_val, cross_val;
    reg signed [47:0] cross_prod;

    wire signed [15:0] d_p1 = dec_old ? old_p1 : cur_p1;
    wire signed [15:0] d_p2 = dec_old ? old_p2 : cur_p2;
    wire [6:0] d_idx = dec_old ? old_idx : cur_idx;
    wire [15:0] d_nsamp = dec_old ? old_nsamp : cur_nsamp;
    wire [31:0] d_count = dec_old ? old_count : cur_count;
    wire [15:0] d_data = dec_old ? old_data : cur_data;
    wire d_ar = dec_old ? old_ar : cur_ar;
    wire [15:0] d_seed = dec_old ? old_seed : cur_seed;
    wire [6:0] d_seedidx = dec_old ? old_seedidx : cur_seedidx;
    wire [15:0] d_word_idx = dec_old ? old_word_idx : cur_word_idx;
    wire [31:0] d_word_data = dec_old ? old_word_data : cur_word_data;
    wire d_word_valid = dec_old ? old_word_valid : cur_word_valid;

    wire [15:0] cur_ix = cur_pos[47:32] + 16'd2;
    wire [15:0] old_ix = old_pos[47:32] + 16'd2;
    wire [15:0] cur_frac = cur_pos[31:16];
    wire [15:0] old_frac = old_pos[31:16];
    wire [2:0] cur_p0i = cur_ix[2:0] - 3'd1;
    wire [2:0] old_p0i = old_ix[2:0] - 3'd1;

    wire [15:0] nib = d_nsamp - 16'd1;
    wire [15:0] byte_idx = nib >> 1;
    wire [15:0] word_idx = (d_data >> 2) + (byte_idx >> 2);
    wire [1:0] byte_lane = byte_idx[1:0];
    wire whigh = nib[0];
    wire [7:0] got_byte = d_word_data[{byte_lane,3'b000} +: 8];
    wire [3:0] code = whigh ? got_byte[7:4] : got_byte[3:0];
    wire signed [4:0] idelta = ima_index_delta(code[2:0]);
    wire signed [8:0] idx_next = $signed({2'b0,d_idx}) + idelta;
    wire [15:0] step = ima_step(d_idx);
    wire [15:0] diff = (step >> 3) + (code[2] ? step : 16'd0) +
                       (code[1] ? (step >> 1) : 16'd0) +
                       (code[0] ? (step >> 2) : 16'd0);
    wire signed [31:0] ar_full = (($signed(tail_coef) * $signed(d_p1)) >>> 14) - $signed(d_p2);
    wire signed [15:0] pred = d_ar ? sat16(ar_full) : d_p1;
    wire signed [15:0] decoded = sat16(pred + (code[3] ? -$signed({16'd0,diff}) : $signed({16'd0,diff})));
    wire signed [31:0] ar_full_r = (($signed(tail_coef) * $signed(d_p1)) >>> 14) - $signed(d_p2);
    wire signed [15:0] pred_r = d_ar ? sat16(ar_full_r) : d_p1;
    wire signed [15:0] decoded_rw_q = sat16(pred_r_q +
        (sign_r ? -$signed({16'd0,diff_r}) : $signed({16'd0,diff_r})));
    wire [15:0] cub_p0 = dec_old ? old_win[old_p0i] : cur_win[cur_p0i];
    wire [15:0] cub_p1 = dec_old ? old_win[old_ix[2:0]] : cur_win[cur_ix[2:0]];
    wire [15:0] cub_p2 = dec_old ? old_win[old_ix[2:0]+3'd1] : cur_win[cur_ix[2:0]+3'd1];
    wire [15:0] cub_p3 = dec_old ? old_win[old_ix[2:0]+3'd2] : cur_win[cur_ix[2:0]+3'd2];
    wire [15:0] cub_frac = dec_old ? old_frac : cur_frac;

    reg cub_start, cub_is_old;
    reg [1:0] cub_step;
    reg signed [23:0] cub_c0,cub_c1,cub_c2,cub_c3,cub_y1,cub_y2;
    reg [15:0] cub_sf;
    reg signed [23:0] cub_mul_a;
    reg cub_done;
    reg signed [15:0] cub_result;

    wire signed [23:0] sc0 = 2*$signed(cub_p1);
    wire signed [23:0] sc1 = $signed(cub_p2)-$signed(cub_p0);
    wire signed [23:0] sc2 = 2*$signed(cub_p0)-5*$signed(cub_p1)+4*$signed(cub_p2)-$signed(cub_p3);
    wire signed [23:0] sc3 = $signed(cub_p3)-$signed(cub_p0)+3*($signed(cub_p1)-$signed(cub_p2));
    wire signed [39:0] cub_prod = cub_mul_a * $signed({1'b0,cub_sf});

    always @* begin
        case(cub_step)
        2'd1: cub_mul_a = cub_c3;
        2'd2: cub_mul_a = cub_y1;
        2'd3: cub_mul_a = cub_y2;
        default: cub_mul_a = 64'sd0;
        endcase
    end

    wire [4:0] vel_gain5 = 5'd1 + {1'b0,vel_lat};
    wire signed [15:0] pcm_calc = sat16((cross_val * $signed({1'b0,vel_gain5})) >>> 4);
    wire signed [16:0] cross_diff = new_val - old_val;
    wire signed [47:0] cross_prod_w = cross_diff * $signed({1'b0,fade_t});
    wire [16:0] fade_next_t = fade_t + 17'd339 + ((fade_err + 16'd109) >= fade_len ? 17'd1 : 17'd0);
    wire [15:0] fade_next_e = ((fade_err + 16'd109) >= fade_len) ?
        (fade_err + 16'd109 - fade_len) : (fade_err + 16'd109);

    function signed [15:0] cubic_calc;
        input signed [15:0] p0, p1, p2, p3;
        input [15:0] frac;
        reg signed [63:0] c0, c1, c2, c3, y;
        begin
            c0 = 2 * $signed(p1);
            c1 = $signed(p2) - $signed(p0);
            c2 = 2 * $signed(p0) - 5 * $signed(p1) + 4 * $signed(p2) - $signed(p3);
            c3 = $signed(p3) - $signed(p0) + 3 * ($signed(p1) - $signed(p2));
            y = ((c3 * $signed({1'b0,frac})) >>> 16) + c2;
            y = ((y * $signed({1'b0,frac})) >>> 16) + c1;
            y = ((y * $signed({1'b0,frac})) >>> 16) + c0;
            cubic_calc = sat16(y >>> 1);
        end
    endfunction

    function [31:0] ctx_save_data;
        input [5:0] idx;
        begin
            case(idx)
            6'd0: ctx_save_data=n;
            6'd1: ctx_save_data=total_n;
            6'd2: ctx_save_data={28'd0,desc_stage,stage};
            6'd3: ctx_save_data={16'd0,fade_len};
            6'd4: ctx_save_data={{16{tail_coef[15]}},tail_coef};
            6'd5: ctx_save_data={19'd0,desc_off};
            6'd6: ctx_save_data={16'd0,fade_cnt};
            6'd7: ctx_save_data={16'd0,fade_t};
            6'd8: ctx_save_data={16'd0,fade_err};
            6'd9: ctx_save_data=cur_start;
            6'd10: ctx_save_data=cur_inc;
            6'd11: ctx_save_data=cur_count;
            6'd12: ctx_save_data=cur_next_start;
            6'd13: ctx_save_data={16'd0,cur_data};
            6'd14: ctx_save_data={16'd0,cur_seed};
            6'd15: ctx_save_data={16'd0,cur_nsamp};
            6'd16: ctx_save_data={16'd0,cur_word_idx};
            6'd17: ctx_save_data={18'd0,cur_idx,cur_seedidx};
            6'd18: ctx_save_data={{16{cur_p1[15]}},cur_p1};
            6'd19: ctx_save_data={{16{cur_p2[15]}},cur_p2};
            6'd20: ctx_save_data=cur_word_data;
            6'd21: ctx_save_data=cur_pos[31:0];
            6'd22: ctx_save_data=cur_pos[63:32];
            6'd23: ctx_save_data={30'd0,cur_word_valid,cur_ar};
            6'd24: ctx_save_data={16'd0,cur_win[0]};
            6'd25: ctx_save_data={16'd0,cur_win[1]};
            6'd26: ctx_save_data={16'd0,cur_win[2]};
            6'd27: ctx_save_data={16'd0,cur_win[3]};
            6'd28: ctx_save_data={16'd0,cur_win[4]};
            6'd29: ctx_save_data={16'd0,cur_win[5]};
            6'd30: ctx_save_data={16'd0,cur_win[6]};
            6'd31: ctx_save_data={16'd0,cur_win[7]};
            6'd32: ctx_save_data=old_start;
            6'd33: ctx_save_data=old_inc;
            6'd34: ctx_save_data=old_count;
            6'd35: ctx_save_data={16'd0,old_data};
            6'd36: ctx_save_data={16'd0,old_seed};
            6'd37: ctx_save_data={16'd0,old_nsamp};
            6'd38: ctx_save_data={16'd0,old_word_idx};
            6'd39: ctx_save_data={18'd0,old_idx,old_seedidx};
            6'd40: ctx_save_data={{16{old_p1[15]}},old_p1};
            6'd41: ctx_save_data={{16{old_p2[15]}},old_p2};
            6'd42: ctx_save_data=old_word_data;
            6'd43: ctx_save_data=old_pos[31:0];
            6'd44: ctx_save_data=old_pos[63:32];
            6'd45: ctx_save_data={30'd0,old_word_valid,old_ar};
            6'd46: ctx_save_data={16'd0,old_win[0]};
            6'd47: ctx_save_data={16'd0,old_win[1]};
            6'd48: ctx_save_data={16'd0,old_win[2]};
            6'd49: ctx_save_data={16'd0,old_win[3]};
            6'd50: ctx_save_data={16'd0,old_win[4]};
            6'd51: ctx_save_data={16'd0,old_win[5]};
            6'd52: ctx_save_data={16'd0,old_win[6]};
            6'd53: ctx_save_data={16'd0,old_win[7]};
            default: ctx_save_data=32'd0;
            endcase
        end
    endfunction

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; dec_ret<=S_IDLE; dec_old<=0; dec_target<=0; ld<=0;
            code_r<=0; diff_r<=0; idx_next_r<=0; nsamp_r<=0; dec_old_r<=0;
            sign_r<=0; decoded_r<=0; pred_r_q<=0;
            base_lat<=0; vel_lat<=0; n<=0; total_n<=0; stage<=0; desc_stage<=0;
            fade_len<=0; tail_coef<=0; desc_off<=0; desc_addr<=0;
            active<=0; pcm<=0; out_valid<=0; rom_req<=0; rom_addr<=0;
            cur_start<=0; cur_inc<=0; cur_count<=0; cur_next_start<=0;
            cur_data<=0; cur_ar<=0; cur_seed<=0; cur_seedidx<=0;
            cur_p1<=0; cur_p2<=0; cur_idx<=0; cur_nsamp<=0;
            cur_word_idx<=0; cur_word_data<=0; cur_word_valid<=0;
            cur_pos<=0; old_start<=0; old_inc<=0; old_count<=0;
            old_data<=0; old_ar<=0; old_seed<=0; old_seedidx<=0;
            old_p1<=0; old_p2<=0; old_idx<=0; old_nsamp<=0;
            old_word_idx<=0; old_word_data<=0; old_word_valid<=0;
            old_pos<=0; old_valid<=0; fade_cnt<=0; fade_t<=0; fade_err<=0;
            new_val<=0; old_val<=0; cross_val<=0; cross_prod<=0;
            cub_start<=0; cub_is_old<=0;
            ctx<=0; c_active<=0; c_pending<=0; c_old_valid<=0;
            c_base[0]<=13'd2470; c_base[1]<=13'd2747; c_base[2]<=13'd3034;
            c_vel[0]<=0; c_vel[1]<=0; c_vel[2]<=0;
            ctx_addr<=0; ctx_we<=0; ctx_wdata<=0;
            ld_idx<=0; sv_idx<=0; ld_phase<=0; sv_done<=0;
            pcm0<=0; pcm1<=0; pcm2<=0;
            for (i=0;i<8;i=i+1) begin cur_win[i]<=0; old_win[i]<=0; end
        end else begin
            out_valid<=0;
            rom_req<=0;
            cub_start<=0;
            if (sample_tick) begin
                if (trig[0]) begin c_pending[0]<=1; c_vel[0]<=(vel>15)?4'd15:vel; end
                if (trig[1]) begin c_pending[1]<=1; c_vel[1]<=(vel>15)?4'd15:vel; end
                if (trig[2]) begin c_pending[2]<=1; c_vel[2]<=(vel>15)?4'd15:vel; end
            end
            if (cancel) begin
                active<=0; pcm<=0; old_valid<=0; state<=S_IDLE;
                c_active<=0; c_pending<=0; pcm0<=0; pcm1<=0; pcm2<=0;
            end else begin
                case (state)
                S_IDLE: begin
                    if (sample_tick) begin
                        if (trig[0]) begin c_pending[0]<=1; c_vel[0]<=(vel>15)?4'd15:vel; end
                        if (trig[1]) begin c_pending[1]<=1; c_vel[1]<=(vel>15)?4'd15:vel; end
                        if (trig[2]) begin c_pending[2]<=1; c_vel[2]<=(vel>15)?4'd15:vel; end
                        ctx<=0;
                        state<=S_LOAD_CTX;
                    end
                end
                S_LOAD_CTX: begin
                    base_lat<=c_base[ctx];
                    vel_lat<=c_vel[ctx];
                    if (c_pending[ctx]) begin
                        active<=1; pcm<=0; n<=0; stage<=0; desc_stage<=0;
                        ld<=0; old_valid<=0; state<=S_HDR_REQ;
                    end else if (c_active[ctx]) begin
                        active<=1; old_valid<=c_old_valid[ctx];
                        ctx_addr<={ctx,6'd0}; ld_idx<=0; ld_phase<=0;
                        state<=S_LD_WAIT;
                    end else begin
                        if (ctx==2) state<=S_WAIT;
                        else begin ctx<=ctx+1; state<=S_LOAD_CTX; end
                    end
                end
                S_LD_WAIT: begin
                    if (!ld_phase) begin
                        ld_phase<=1;
                    end else begin
                        case (ld_idx)
                        6'd0: n<=ctx_rdata;
                        6'd1: total_n<=ctx_rdata;
                        6'd2: begin stage<=ctx_rdata[1:0]; desc_stage<=ctx_rdata[3:2]; end
                        6'd3: fade_len<=ctx_rdata[15:0];
                        6'd4: tail_coef<=ctx_rdata[15:0];
                        6'd5: desc_off<=ctx_rdata[12:0];
                        6'd6: fade_cnt<=ctx_rdata[15:0];
                        6'd7: fade_t<=ctx_rdata[15:0];
                        6'd8: fade_err<=ctx_rdata[15:0];
                        6'd9: cur_start<=ctx_rdata;
                        6'd10: cur_inc<=ctx_rdata;
                        6'd11: cur_count<=ctx_rdata;
                        6'd12: cur_next_start<=ctx_rdata;
                        6'd13: cur_data<=ctx_rdata[15:0];
                        6'd14: cur_seed<=ctx_rdata[15:0];
                        6'd15: cur_nsamp<=ctx_rdata[15:0];
                        6'd16: cur_word_idx<=ctx_rdata[15:0];
                        6'd17: begin cur_seedidx<=ctx_rdata[6:0]; cur_idx<=ctx_rdata[13:7]; end
                        6'd18: cur_p1<=ctx_rdata[15:0];
                        6'd19: cur_p2<=ctx_rdata[15:0];
                        6'd20: cur_word_data<=ctx_rdata;
                        6'd21: cur_pos[31:0]<=ctx_rdata;
                        6'd22: cur_pos[63:32]<=ctx_rdata;
                        6'd23: begin cur_ar<=ctx_rdata[0]; cur_word_valid<=ctx_rdata[1]; end
                        6'd24,6'd25,6'd26,6'd27,6'd28,6'd29,6'd30,6'd31:
                            cur_win[ld_idx-6'd24]<=ctx_rdata[15:0];
                        6'd32: old_start<=ctx_rdata;
                        6'd33: old_inc<=ctx_rdata;
                        6'd34: old_count<=ctx_rdata;
                        6'd35: old_data<=ctx_rdata[15:0];
                        6'd36: old_seed<=ctx_rdata[15:0];
                        6'd37: old_nsamp<=ctx_rdata[15:0];
                        6'd38: old_word_idx<=ctx_rdata[15:0];
                        6'd39: begin old_seedidx<=ctx_rdata[6:0]; old_idx<=ctx_rdata[13:7]; end
                        6'd40: old_p1<=ctx_rdata[15:0];
                        6'd41: old_p2<=ctx_rdata[15:0];
                        6'd42: old_word_data<=ctx_rdata;
                        6'd43: old_pos[31:0]<=ctx_rdata;
                        6'd44: old_pos[63:32]<=ctx_rdata;
                        6'd45: begin old_ar<=ctx_rdata[0]; old_word_valid<=ctx_rdata[1]; end
                        6'd46,6'd47,6'd48,6'd49,6'd50,6'd51,6'd52,6'd53:
                            old_win[ld_idx-6'd46]<=ctx_rdata[15:0];
                        default: ;
                        endcase
                        if (ld_idx==6'd53) state<=S_START;
                        else begin
                            ld_idx<=ld_idx+6'd1;
                            ctx_addr<={ctx,6'd0}+ld_idx+6'd1;
                            ld_phase<=0;
                        end
                    end
                end
                S_SAVE: begin
                    c_active[ctx]<=active;
                    c_old_valid[ctx]<=old_valid;
                    c_vel[ctx]<=vel_lat;
                    c_pending[ctx]<=0;
                    sv_idx<=0; sv_done<=0;
                    state<=S_SV_WAIT;
                end
                S_SV_WAIT: begin
                    if (!sv_done) begin
                        ctx_we<=1;
                        ctx_addr<={ctx,6'd0}+sv_idx;
                        ctx_wdata<=ctx_save_data(sv_idx);
                        if (sv_idx==6'd53) sv_done<=1;
                        else sv_idx<=sv_idx+6'd1;
                    end else begin
                        ctx_we<=0;
                        if (ctx==2) state<=S_WAIT;
                        else begin ctx<=ctx+1; state<=S_LOAD_CTX; end
                    end
                end
                S_HDR_REQ: begin
                    rom_addr<=base_lat + ld[12:0]; rom_req<=1; state<=S_HDR_WAIT;
                end
                S_HDR_WAIT: begin
                    if (rom_valid) begin
                        case (ld)
                        32'd1: total_n<=rom_data;
                        32'd3: fade_len<=rom_data[15:0];
                        32'd4: tail_coef<=rom_data[15:0];
                        32'd5: desc_off<=rom_data[12:0];
                        default: ;
                        endcase
                        if (ld==32'd5) begin
                            ld<=0; desc_addr<=base_lat + rom_data[12:0];
                            state<=S_STG_REQ;
                        end else begin
                            ld<=ld+1; state<=S_HDR_REQ;
                        end
                    end else rom_req<=1;
                end
                S_STG_REQ: begin
                    rom_addr<=desc_addr + ld[12:0]; rom_req<=1; state<=S_STG_WAIT;
                end
                S_STG_WAIT: begin
                    if (rom_valid) begin
                        case (ld)
                        32'd0: cur_start<=rom_data;
                        32'd1: cur_next_start<=rom_data;
                        32'd2: cur_inc<=rom_data;
                        32'd3: begin
                            cur_seed<=rom_data[15:0];
                            cur_seedidx<=rom_data[22:16] & 7'h7f;
                            cur_ar<=rom_data[23];
                        end
                        32'd4: cur_count<=rom_data;
                        32'd5: cur_data<=rom_data[15:0];
                        default: ;
                        endcase
                        if (ld==32'd5) begin
                            ld<=0; cur_pos<=0; cur_nsamp<=0;
                            cur_word_valid<=0; cur_word_idx<=0; cur_word_data<=0;
                            cur_p1<=0; cur_p2<=0; cur_idx<=0;
                            dec_old<=0; dec_target<=16'd4;
                            dec_ret<=S_PRIME_DONE; state<=S_DEC;
                        end else begin
                            ld<=ld+1; state<=S_STG_REQ;
                        end
                    end else rom_req<=1;
                end
                S_PRIME_DONE: begin
                    n<=0; cur_pos<=0; state<=S_START;
                end
                S_START: begin
                    if (!active) state<=S_SAVE;
                    else if (n >= total_n) begin active<=0; state<=S_SAVE; end
                    else if (n != 0 && n == cur_next_start) state<=S_TRANS_COPY;
                    else state<=S_POS;
                end
                S_WAIT: begin
                    if (sample_tick) begin
                        if (trig[0]) begin c_pending[0]<=1; c_vel[0]<=(vel>15)?4'd15:vel; end
                        if (trig[1]) begin c_pending[1]<=1; c_vel[1]<=(vel>15)?4'd15:vel; end
                        if (trig[2]) begin c_pending[2]<=1; c_vel[2]<=(vel>15)?4'd15:vel; end
                        ctx<=0;
                        state<=S_LOAD_CTX;
                    end
                end
                S_TAIL: begin
                    state<=S_SAVE;
                end
                S_POS: begin
                    if (!active) state<=S_SAVE;
                    else if (n >= total_n) begin active<=0; state<=S_SAVE; end
                    else begin
                        dec_old<=0; dec_target<=cur_ix + 16'd2;
                        dec_ret<=S_CUR_DONE; state<=S_DEC;
                    end
                end
                S_CUR_DONE: begin
                    state<=S_CALC_NEW;
                end
                S_CALC_NEW: begin
                    cub_start<=1; cub_is_old<=0; state<=S_CUB_WAIT;
                end
                S_CUB_WAIT: begin
                    if (cub_done) begin
                        if (cub_is_old) begin
                            old_val<=cub_result;
                            state<=S_CROSS;
                        end else begin
                            new_val<=cub_result;
                            if (old_valid) begin
                                dec_old<=1; dec_target<=old_ix + 16'd2;
                                dec_ret<=S_OLD_ENSURE; state<=S_DEC;
                            end else begin
                                state<=S_NEW_ONLY;
                            end
                        end
                    end
                end
                S_NEW_ONLY: begin
                    cross_val<=new_val;
                    state<=S_OUT;
                end
                S_OLD_ENSURE: begin
                    state<=S_CALC_OLD;
                end
                S_CALC_OLD: begin
                    cub_start<=1; cub_is_old<=1; state<=S_CUB_WAIT;
                end
                S_CROSS: begin
                    cross_val<=old_val + (cross_prod_w >>> 16);
                    state<=S_OUT;
                end
                S_OUT: begin
                    pcm <= pcm_calc;
                    case (ctx)
                    2'd0: pcm0 <= pcm_calc;
                    2'd1: pcm1 <= pcm_calc;
                    default: pcm2 <= pcm_calc;
                    endcase
                    out_valid[ctx]<=1'b1;
                    n<=n+1;
                    cur_pos<=cur_pos + {32'd0,cur_inc};
                    if (old_valid) begin
                        old_pos<=old_pos + {32'd0,old_inc};
                        if (fade_cnt + 16'd1 >= fade_len) begin
                            old_valid<=0;
                        end else begin
                            fade_cnt<=fade_cnt+16'd1;
                            fade_t<=fade_next_t[15:0];
                            fade_err<=fade_next_e;
                        end
                    end
                    if (n+1 >= total_n) active<=0;
                    state<=S_SAVE;
                end
                S_TRANS_COPY: begin
                    old_start<=cur_start; old_inc<=cur_inc; old_count<=cur_count;
                    old_data<=cur_data; old_ar<=cur_ar; old_seed<=cur_seed;
                    old_seedidx<=cur_seedidx; old_p1<=cur_p1; old_p2<=cur_p2;
                    old_idx<=cur_idx; old_nsamp<=cur_nsamp;
                    old_word_idx<=cur_word_idx; old_word_data<=cur_word_data;
                    old_word_valid<=cur_word_valid; old_pos<=cur_pos; old_valid<=1;
                    for (i=0;i<8;i=i+1) old_win[i]<=cur_win[i];
                    fade_cnt<=0; fade_t<=0; fade_err<=0;
                    desc_stage<=stage+2'd1;
                    desc_addr<=base_lat + desc_off + ((stage+2'd1)*6);
                    ld<=0; state<=S_TRANS_REQ;
                end
                S_TRANS_REQ: begin
                    rom_addr<=desc_addr + ld[12:0]; rom_req<=1; state<=S_TRANS_WAIT;
                end
                S_TRANS_WAIT: begin
                    if (rom_valid) begin
                        case (ld)
                        32'd0: cur_start<=rom_data;
                        32'd1: cur_next_start<=rom_data;
                        32'd2: cur_inc<=rom_data;
                        32'd3: begin
                            cur_seed<=rom_data[15:0];
                            cur_seedidx<=rom_data[22:16] & 7'h7f;
                            cur_ar<=rom_data[23];
                        end
                        32'd4: cur_count<=rom_data;
                        32'd5: cur_data<=rom_data[15:0];
                        default: ;
                        endcase
                        if (ld==32'd5) begin
                            ld<=0; stage<=desc_stage; cur_pos<=0; cur_nsamp<=0;
                            cur_word_valid<=0; cur_word_idx<=0; cur_word_data<=0;
                            dec_old<=0; dec_target<=16'd4;
                            dec_ret<=S_TRANS_PRIME; state<=S_DEC;
                        end else begin
                            ld<=ld+1; state<=S_TRANS_REQ;
                        end
                    end else rom_req<=1;
                end
                S_TRANS_PRIME: begin
                    cur_pos<=0; state<=S_POS;
                end
                S_DEC: begin
                    if (d_nsamp > dec_target || d_nsamp >= d_count) begin
                        state<=dec_ret;
                    end else if (d_nsamp == 16'd0) begin
                        if (dec_old) begin
                            old_win[0]<=$signed(d_seed); old_p1<=$signed(d_seed);
                            old_p2<=$signed(d_seed); old_idx<=d_seedidx;
                            old_nsamp<=16'd1;
                        end else begin
                            cur_win[0]<=$signed(d_seed); cur_p1<=$signed(d_seed);
                            cur_p2<=$signed(d_seed); cur_idx<=d_seedidx;
                            cur_nsamp<=16'd1;
                        end
                        state<=S_DEC_CHECK;
                    end else if (d_word_valid && d_word_idx == word_idx) begin
                        state<=S_DEC_CODE;
                    end else begin
                        rom_addr<=base_lat + word_idx[12:0]; rom_req<=1;
                        state<=S_DEC_WAIT;
                    end
                end
                S_DEC_WAIT: begin
                    if (rom_valid) begin
                        if (dec_old) begin
                            old_word_data<=rom_data; old_word_idx<=word_idx; old_word_valid<=1;
                        end else begin
                            cur_word_data<=rom_data; cur_word_idx<=word_idx; cur_word_valid<=1;
                        end
                        state<=S_DEC_CODE;
                    end else rom_req<=1;
                end
                S_DEC_CODE: begin
                    code_r<=code;
                    diff_r<=diff;
                    idx_next_r<=idx_next;
                    nsamp_r<=d_nsamp;
                    dec_old_r<=dec_old;
                    sign_r<=code[3];
                    pred_r_q<=pred_r;
                    state<=S_DEC_CODE2;
                end
                S_DEC_CODE2: begin
                    decoded_r<=decoded_rw_q;
                    state<=S_DEC_CODE3;
                end
                S_DEC_CODE3: begin
                    if (dec_old_r) begin
                        old_p2<=old_p1; old_p1<=decoded_r;
                        old_idx<=(idx_next_r < 0) ? 7'd0 : ((idx_next_r > 88) ? 7'd88 : idx_next_r[6:0]);
                        old_win[nsamp_r[2:0]]<=decoded_r;
                        old_nsamp<=nsamp_r+16'd1;
                    end else begin
                        cur_p2<=cur_p1; cur_p1<=decoded_r;
                        cur_idx<=(idx_next_r < 0) ? 7'd0 : ((idx_next_r > 88) ? 7'd88 : idx_next_r[6:0]);
                        cur_win[nsamp_r[2:0]]<=decoded_r;
                        cur_nsamp<=nsamp_r+16'd1;
                    end
                    state<=S_DEC_CHECK;
                end
                S_DEC_CHECK: begin
                    if (d_nsamp > dec_target || d_nsamp >= d_count) state<=dec_ret;
                    else state<=S_DEC;
                end
                default: state<=S_IDLE;
                endcase
            end
        end
    end

    // One shared multiplier, three sequential cubic steps. This removes two
    // 64x16 multipliers at the cost of a small operand mux.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cub_step<=0; cub_done<=0; cub_result<=0;
            cub_c0<=0; cub_c1<=0; cub_c2<=0; cub_c3<=0;
            cub_y1<=0; cub_y2<=0; cub_sf<=0;
        end else begin
            cub_done<=0;
            case(cub_step)
            2'd0: if (cub_start) begin
                cub_c0<=sc0; cub_c1<=sc1; cub_c2<=sc2; cub_c3<=sc3;
                cub_sf<=cub_frac;
                cub_step<=2'd1;
            end
            2'd1: begin
                cub_y1<=(cub_prod>>>16)+cub_c2;
                cub_step<=2'd2;
            end
            2'd2: begin
                cub_y2<=(cub_prod>>>16)+cub_c1;
                cub_step<=2'd3;
            end
            default: begin
                cub_result<=sat16(((cub_prod>>>16)+cub_c0)>>>1);
                cub_done<=1'b1;
                cub_step<=2'd0;
            end
            endcase
        end
    end
endmodule


