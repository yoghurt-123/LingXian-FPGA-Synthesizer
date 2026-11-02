// Shared post-mix one-pole low-pass/high-pass branch for the four slider ADC.
// One 18x18 DSP multiplier is time-multiplexed: LP, HP, then dry/wet crossfade.
// Filter state updates only on sample_tick, in the audio clock domain.
// Fixed processing latency is one audio sample (1088 audio clocks).
module adc_filter_audio (
    input clk,
    input rst_n,
    input sample_tick,
    input signed [15:0] pcm_in,
    input [15:0] panic_gain,
    input filter_on,
    input [8:0] a0_idx,
    input [8:0] a1_idx,
    input [3:0] param_valid,
    input params_ok,
    output reg signed [15:0] pcm_out
);
    localparam [8:0] IDX_MAX = 9'd412;

    localparam [3:0] S_IDLE      = 4'd0;
    localparam [3:0] S_WAIT_LP1   = 4'd1;
    localparam [3:0] S_READ_LP    = 4'd2;
    localparam [3:0] S_WAIT_HP1   = 4'd3;
    localparam [3:0] S_READ_HP    = 4'd4;
    localparam [3:0] S_LP_MUL     = 4'd5;
    localparam [3:0] S_LP_ACC     = 4'd6;
    localparam [3:0] S_HP_MUL     = 4'd7;
    localparam [3:0] S_HP_ACC     = 4'd8;
    localparam [3:0] S_XF_MUL     = 4'd9;
    localparam [3:0] S_XF_PROD    = 4'd10;
    localparam [3:0] S_XF_OUT     = 4'd11;
    localparam [3:0] S_DONE       = 4'd12;

    reg [8:0] rom_addr;
    wire [31:0] rom_dout;
    filter_coeff_rom u_rom(.clk(clk), .addr(rom_addr), .dout(rom_dout));

    function signed [35:0] sx16;
        input signed [15:0] v;
        begin sx16 = {{20{v[15]}}, v}; end
    endfunction
    function signed [35:0] sx18;
        input signed [17:0] v;
        begin sx18 = {{18{v[17]}}, v}; end
    endfunction

    function signed [17:0] sat18;
        input signed [35:0] v;
        begin
            if (v > 36'sd131071) sat18 = 18'sd131071;
            else if (v < -36'sd131072) sat18 = -18'sd131072;
            else sat18 = v[17:0];
        end
    endfunction

    function signed [15:0] sat16;
        input signed [35:0] v;
        begin
            if (v > 36'sd32767) sat16 = 16'sd32767;
            else if (v < -36'sd32768) sat16 = -16'sd32768;
            else sat16 = v[15:0];
        end
    endfunction

    function [8:0] clamp_idx;
        input [8:0] v;
        begin
            clamp_idx = (v > IDX_MAX) ? IDX_MAX : v;
        end
    endfunction

    wire [8:0] a0_safe = clamp_idx(a0_idx);
    wire [8:0] a1_safe = clamp_idx(a1_idx);
    wire positions_at_bottom = (a0_safe == 9'd0) && (a1_safe == 9'd0);
    wire effect_request = filter_on && params_ok && !positions_at_bottom;
    wire panic_clear = (panic_gain == 16'd0);

    reg [3:0] state;
    reg signed [17:0] x18, lp_prev, lp_out, y_lp, y_hp;
    reg signed [15:0] dry_d, wet16;
    reg signed [17:0] mult_a;
    reg signed [17:0] mult_b;
    reg signed [35:0] mult_p;
    reg [15:0] lp_alpha, hp_a;
    reg [8:0] idx_lp_cur, idx_hp_cur, idx_lp_tgt, idx_hp_tgt;
    reg [9:0] mix;

    wire [8:0] lp_next = (idx_lp_tgt > idx_lp_cur) ? (idx_lp_cur + 9'd1) :
                         (idx_lp_tgt < idx_lp_cur) ? (idx_lp_cur - 9'd1) : idx_lp_cur;
    wire [8:0] hp_next = (idx_hp_tgt > idx_hp_cur) ? (idx_hp_cur + 9'd1) :
                         (idx_hp_tgt < idx_hp_cur) ? (idx_hp_cur - 9'd1) : idx_hp_cur;

    wire signed [17:0] hp_calc = sat18((mult_p >>> 15) + sx18(lp_out) - sx18(lp_prev));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            x18 <= 18'sd0;
            lp_prev <= 18'sd0;
            y_lp <= 18'sd0;
            y_hp <= 18'sd0;
            dry_d <= 16'sd0;
            wet16 <= 16'sd0;
            mult_a <= 18'sd0;
            mult_b <= 18'sd0;
            mult_p <= 36'sd0;
            lp_alpha <= 16'd0;
            hp_a <= 16'd0;
            idx_lp_cur <= 9'd0;
            idx_hp_cur <= 9'd0;
            idx_lp_tgt <= 9'd0;
            idx_hp_tgt <= 9'd0;
            rom_addr <= 9'd0;
            mix <= 10'd0;
            pcm_out <= 16'sd0;
        end else if (panic_clear) begin
            state <= S_IDLE;
            x18 <= 18'sd0;
            lp_prev <= 18'sd0;
            y_lp <= 18'sd0;
            y_hp <= 18'sd0;
            dry_d <= 16'sd0;
            wet16 <= 16'sd0;
            mult_a <= 18'sd0;
            mult_b <= 18'sd0;
            mult_p <= 36'sd0;
            idx_lp_cur <= 9'd0;
            idx_hp_cur <= 9'd0;
            mix <= 10'd0;
            pcm_out <= 16'sd0;
        end else begin
            if (sample_tick && (state == S_IDLE)) begin
                x18 <= {{2{pcm_in[15]}}, pcm_in};
                dry_d <= pcm_in;
                idx_lp_tgt <= a0_safe;
                idx_hp_tgt <= a1_safe;
                idx_lp_cur <= lp_next;
                idx_hp_cur <= hp_next;
                rom_addr <= lp_next;
                state <= S_WAIT_LP1;
            end

            if (sample_tick) begin
                if (effect_request && (mix < 10'd512)) mix <= mix + 10'd1;
                else if (!effect_request && (mix > 10'd0)) mix <= mix - 10'd1;
            end

            case (state)
                S_IDLE: begin
                end
                S_WAIT_LP1: state <= S_READ_LP;
                S_READ_LP: begin
                    lp_alpha <= rom_dout[31:16];
                    rom_addr <= hp_next;
                    state <= S_WAIT_HP1;
                end
                S_WAIT_HP1: state <= S_READ_HP;
                S_READ_HP: begin
                    hp_a <= rom_dout[15:0];
                    mult_a <= sat18(sx18(x18) - sx18(y_lp));
                    mult_b <= {2'b00, lp_alpha};
                    state <= S_LP_MUL;
                end
                S_LP_MUL: begin
                    mult_p <= mult_a * mult_b;
                    state <= S_LP_ACC;
                end
                S_LP_ACC: begin
                    lp_out <= sat18(sx18(y_lp) + (mult_p >>> 15));
                    y_lp <= sat18(sx18(y_lp) + (mult_p >>> 15));
                    mult_a <= y_hp;
                    mult_b <= {2'b00, hp_a};
                    state <= S_HP_MUL;
                end
                S_HP_MUL: begin
                    mult_p <= mult_a * mult_b;
                    state <= S_HP_ACC;
                end
                S_HP_ACC: begin
                    y_hp <= hp_calc;
                    lp_prev <= lp_out;
                    wet16 <= sat16(hp_calc);
                    state <= S_XF_MUL;
                end
                S_XF_MUL: begin
                    mult_a <= sat18(sx16(wet16) - sx16(dry_d));
                    mult_b <= {8'd0, mix};
                    state <= S_XF_PROD;
                end
                S_XF_PROD: begin
                    mult_p <= mult_a * mult_b;
                    state <= S_XF_OUT;
                end
                S_XF_OUT: begin
                    if (mix == 10'd0) pcm_out <= dry_d;
                    else pcm_out <= sat16(sx16(dry_d) + ((mult_p + 36'sd256) >>> 9));
                    state <= S_DONE;
                end
                S_DONE: state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

