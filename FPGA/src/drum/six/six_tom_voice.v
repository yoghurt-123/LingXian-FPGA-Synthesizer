module six_tom_voice(
    input clk,
    input rst_n,
    input sample_tick,
    input trig,
    input [3:0] vel,
    input cancel,
    input [12:0] base,
    output reg signed [15:0] pcm,
    output reg out_valid,
    output reg active,
    output reg rom_req,
    output reg [12:0] rom_addr,
    input [31:0] rom_data,
    input rom_valid
);
`include "six_drum_defs.vh"
    localparam [4:0] S_IDLE=0, S_HDR_REQ=1, S_HDR_WAIT=2,
        S_STG_REQ=3, S_STG_WAIT=4, S_PRIME_DONE=5, S_START=6,
        S_POS=7, S_DEC=8, S_DEC_WAIT=9, S_DEC_CODE=10, S_DEC_CHECK=11,
        S_CUR_DONE=12, S_CALC_NEW=13, S_NEW_ONLY=14, S_OLD_ENSURE=15,
        S_CALC_OLD=16, S_CROSS=17, S_OUT=18, S_WAIT=19, S_TAIL=20,
        S_TRANS_COPY=21, S_TRANS_REQ=22, S_TRANS_WAIT=23, S_TRANS_PRIME=24;

    reg [4:0] state, dec_ret;
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
    wire signed [15:0] cur_cub = cubic_calc(cur_win[cur_p0i], cur_win[cur_ix[2:0]],
        cur_win[cur_ix[2:0]+3'd1], cur_win[cur_ix[2:0]+3'd2], cur_frac);
    wire signed [15:0] old_cub = cubic_calc(old_win[old_p0i], old_win[old_ix[2:0]],
        old_win[old_ix[2:0]+3'd1], old_win[old_ix[2:0]+3'd2], old_frac);
    wire signed [31:0] vel_gain32 = 32'sd1 + $signed({28'd0,vel_lat});
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

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; dec_ret<=S_IDLE; dec_old<=0; dec_target<=0; ld<=0;
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
            for (i=0;i<8;i=i+1) begin cur_win[i]<=0; old_win[i]<=0; end
        end else begin
            out_valid<=0;
            rom_req<=0;
            if (cancel) begin
                active<=0; pcm<=0; old_valid<=0; state<=S_IDLE;
            end else begin
                case (state)
                S_IDLE: begin
                    if (sample_tick && trig) begin
                        active<=1; pcm<=0; n<=0; stage<=0; desc_stage<=0;
                        ld<=0; base_lat<=base; vel_lat<=(vel>15)?4'd15:vel;
                        old_valid<=0; state<=S_HDR_REQ;
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
                    end
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
                    end
                end
                S_PRIME_DONE: begin
                    n<=0; cur_pos<=0; state<=S_START;
                end
                S_START: begin
                    if (!active) state<=S_IDLE;
                    else if (n >= total_n) state<=S_TAIL;
                    else if (n != 0 && n == cur_next_start) state<=S_TRANS_COPY;
                    else state<=S_POS;
                end
                S_WAIT: begin
                    if (!active) state<=S_IDLE;
                    else if (sample_tick) begin
                        if (n >= total_n) state<=S_TAIL;
                        else if (n != 0 && n == cur_next_start) state<=S_TRANS_COPY;
                        else state<=S_POS;
                    end
                end
                S_TAIL: begin
                    if (sample_tick) begin
                        active<=0; pcm<=0; state<=S_IDLE;
                    end
                end
                S_POS: begin
                    if (!active) state<=S_IDLE;
                    else if (n >= total_n) state<=S_TAIL;
                    else begin
                        dec_old<=0; dec_target<=cur_ix + 16'd2;
                        dec_ret<=S_CUR_DONE; state<=S_DEC;
                    end
                end
                S_CUR_DONE: begin
                    state<=S_CALC_NEW;
                end
                S_CALC_NEW: begin
                    new_val<=cur_cub;
                    if (old_valid) begin
                        dec_old<=1; dec_target<=old_ix + 16'd2;
                        dec_ret<=S_OLD_ENSURE; state<=S_DEC;
                    end else begin
                        state<=S_NEW_ONLY;
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
                    old_val<=old_cub;
                    state<=S_CROSS;
                end
                S_CROSS: begin
                    cross_val<=old_val + (cross_prod_w >>> 16);
                    state<=S_OUT;
                end
                S_OUT: begin
                    pcm <= sat16((cross_val * vel_gain32) >>> 4);
                    out_valid<=1;
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
                    if (n+1 >= total_n) begin
                        active<=0;
                        state<=S_TAIL;
                    end else begin
                        state<=S_WAIT;
                    end
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
                    end
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
                    end
                end
                S_DEC_CODE: begin
                    if (dec_old) begin
                        old_p2<=old_p1; old_p1<=decoded;
                        old_idx<=(idx_next < 0) ? 7'd0 : ((idx_next > 88) ? 7'd88 : idx_next[6:0]);
                        old_win[d_nsamp[2:0]]<=decoded;
                        old_nsamp<=d_nsamp+16'd1;
                    end else begin
                        cur_p2<=cur_p1; cur_p1<=decoded;
                        cur_idx<=(idx_next < 0) ? 7'd0 : ((idx_next > 88) ? 7'd88 : idx_next[6:0]);
                        cur_win[d_nsamp[2:0]]<=decoded;
                        cur_nsamp<=d_nsamp+16'd1;
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
endmodule
