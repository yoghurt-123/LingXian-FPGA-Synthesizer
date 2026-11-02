// Guitar clean / overdrive chain, fixed-point, one voice instance per sample.
// A2 slider mode changes gain and clean/drive blend; KEY0 off restores drv_sel.
module guitar_fx #(
    parameter signed [9:0]  CLEAN_GAIN_Q8 = 10'sd300,
    parameter signed [9:0]  CLEAN_GAIN_A2_Q8 = 10'sd353,
    parameter signed [9:0]  CLEAN_GAIN_D3_Q8 = 10'sd330,
    parameter signed [9:0]  CLEAN_GAIN_G3_Q8 = 10'sd385,
    parameter signed [9:0]  CLEAN_GAIN_B3_Q8 = 10'sd425,
    parameter signed [9:0]  CLEAN_GAIN_E4_Q8 = 10'sd398,
    parameter signed [9:0]  CLEAN_GAIN_G2_Q8 = 10'sd303,
    parameter signed [9:0]  CLEAN_GAIN_A3_Q8 = 10'sd270,
    parameter signed [9:0]  DRIVE_POST_Q8 = 10'sd96,
    parameter signed [7:0]  DRIVE_DRY_Q8 = 8'sd108,
    parameter signed [15:0] PRE_A_Q15 = 16'sd21205,
    parameter signed [15:0] BQ_B0_Q13 = 16'sd491,
    parameter signed [15:0] BQ_B1_Q13 = 16'sd983,
    parameter signed [15:0] BQ_B2_Q13 = 16'sd491,
    parameter signed [15:0] BQ_A1_Q13 = -16'sd9813,
    parameter signed [15:0] BQ_A2_Q13 = 16'sd3586
)(
    input clk, input rst_n, input sample_tick,
    input signed [15:0] in,
    input clear,
    input drv_sel,
    input [8:0] drive_idx,
    input drive_slider,
    input [2:0] clean_note,
    output reg signed [15:0] data
);
    function signed [15:0] sat16;
        input signed [31:0] v;
        begin
            sat16 = (v > 32'sd32767) ? 16'sd32767 :
                    (v < -32'sd32768) ? -16'sd32768 : v[15:0];
        end
    endfunction
    function signed [31:0] sat23w;
        input signed [42:0] v;
        begin
            sat23w = (v > 43'sd8388607) ? 32'sd8388607 :
                     (v < -43'sd8388608) ? -32'sd8388608 : v[31:0];
        end
    endfunction
    function signed [31:0] sat23;
        input signed [31:0] v;
        begin
            sat23 = (v > 32'sd8388607) ? 32'sd8388607 :
                    (v < -32'sd8388608) ? -32'sd8388608 : v;
        end
    endfunction

    reg signed [15:0] in_r;
    reg signed [31:0] lp_y;
    reg signed [15:0] g15_r;
    reg signed [15:0] v15_r;
    reg signed [31:0] p2_r;
    reg signed [15:0] yc_r;
    reg signed [15:0] x15_r;
    reg signed [31:0] bq_y23_r;
    reg signed [15:0] bq_y15_r;
    reg signed [31:0] s1, s2;
    reg [3:0] st;
    reg [8:0] mix_q8;
    reg [10:0] drive_gain_q8;

    wire signed [31:0] in23 = in_r <<< 8;
    wire signed [31:0] lp_d = in23 - lp_y;
    wire signed [15:0] lp15 = drive_slider ? sat16(lp_d >>> 8) : (lp_d >>> 8);
    wire signed [31:0] lp_add = (PRE_A_Q15 * lp15) >>> 7;

    wire [8:0] a2_safe = (drive_idx > 9'd412) ? 9'd412 : drive_idx;
    wire [8:0] slider_mix = (a2_safe <= 9'd8) ? 9'd0 :
                            (a2_safe >= 9'd136) ? 9'd256 :
                            ((a2_safe - 9'd8) << 1);
    wire [8:0] target_mix = drive_slider ? slider_mix : (drv_sel ? 9'd256 : 9'd0);
    wire [10:0] a2_span = {a2_safe, 2'b00};
    wire [10:0] target_gain = drive_slider ? (11'd256 + a2_span) : 11'd1024;

    wire signed [42:0] g23_p = lp_y * $signed({1'b0, drive_gain_q8});
    wire signed [31:0] g23_legacy = sat23(lp_y <<< 2);
    wire signed [31:0] g23 = drive_slider ? sat23w(g23_p >>> 8) : g23_legacy;
    wire signed [15:0] g15 = g23 >>> 8;
    wire signed [31:0] p2 = g15_r * g15_r;
    wire signed [31:0] c14 = 32'sd24576 - (p2_r >>> 17);
    wire signed [31:0] yc_p = v15_r * c14;
    wire signed [31:0] y23c = {{16{yc_r[15]}}, yc_r} <<< 8;

    wire signed [31:0] bq_y = ((BQ_B0_Q13 * x15_r) >>> 5) + s1;
    wire signed [31:0] bq_y_s = sat23(bq_y);
    wire signed [15:0] bq_y15_s = sat16(bq_y_s >>> 8);
    wire signed [31:0] bq_s2 = ((BQ_B2_Q13 * x15_r) >>> 5) -
                               ((BQ_A2_Q13 * bq_y15_r) >>> 5);
    wire signed [31:0] bq_s1 = ((BQ_B1_Q13 * x15_r) >>> 5) -
                               ((BQ_A1_Q13 * bq_y15_r) >>> 5) + s2;

    wire signed [9:0] cln_gain = (clean_note == 3'd1) ? CLEAN_GAIN_A2_Q8 :
                                (clean_note == 3'd2) ? CLEAN_GAIN_D3_Q8 :
                                (clean_note == 3'd3) ? CLEAN_GAIN_G3_Q8 :
                                (clean_note == 3'd4) ? CLEAN_GAIN_B3_Q8 :
                                (clean_note == 3'd5) ? CLEAN_GAIN_E4_Q8 :
                                (clean_note == 3'd6) ? CLEAN_GAIN_G2_Q8 :
                                (clean_note == 3'd7) ? CLEAN_GAIN_A3_Q8 : CLEAN_GAIN_Q8;
    wire signed [15:0] drv_o = sat16((sat16(bq_y23_r >>> 8) * DRIVE_POST_Q8) >>> 8);
    wire signed [31:0] dry_k = DRIVE_DRY_Q8;
    wire signed [31:0] dry_p = in_r * dry_k;
    wire signed [15:0] dry16 = dry_p >>> 8;
    wire signed [31:0] drv_mix = {{16{drv_o[15]}}, drv_o} + {{16{dry16[15]}}, dry16};
    wire signed [15:0] drv_out = sat16(drv_mix);
    wire signed [15:0] cln_o = sat16((in_r * cln_gain) >>> 8);

    wire signed [31:0] cln32 = {{16{cln_o[15]}}, cln_o};
    wire signed [31:0] drv32 = {{16{drv_out[15]}}, drv_out};
    wire signed [31:0] blend_diff32 = drv32 - cln32;
    wire signed [39:0] blend_p32 = blend_diff32 * $signed({1'b0, mix_q8});
    wire signed [31:0] blend32 = cln32 + (blend_p32 >>> 8);
    wire signed [15:0] blend_sat = sat16(blend32);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_r <= 16'sd0; lp_y <= 32'sd0; g15_r <= 16'sd0; v15_r <= 16'sd0;
            p2_r <= 32'sd0; yc_r <= 16'sd0; x15_r <= 16'sd0;
            bq_y23_r <= 32'sd0; bq_y15_r <= 16'sd0; s1 <= 32'sd0; s2 <= 32'sd0;
            st <= 4'd0; data <= 16'sd0; mix_q8 <= 9'd0; drive_gain_q8 <= 11'd1024;
        end else if (clear) begin
            in_r <= 16'sd0; lp_y <= 32'sd0; g15_r <= 16'sd0; v15_r <= 16'sd0;
            p2_r <= 32'sd0; yc_r <= 16'sd0; x15_r <= 16'sd0;
            bq_y23_r <= 32'sd0; bq_y15_r <= 16'sd0; s1 <= 32'sd0; s2 <= 32'sd0;
            st <= 4'd0; data <= 16'sd0; mix_q8 <= 9'd0; drive_gain_q8 <= 11'd1024;
        end else if (sample_tick) begin
            in_r <= in;
            st <= 4'd1;
            if (mix_q8 < target_mix) mix_q8 <= mix_q8 + 1'b1;
            else if (mix_q8 > target_mix) mix_q8 <= mix_q8 - 1'b1;
            if (drive_gain_q8 < target_gain) drive_gain_q8 <= drive_gain_q8 + 1'b1;
            else if (drive_gain_q8 > target_gain) drive_gain_q8 <= drive_gain_q8 - 1'b1;
        end else case (st)
            4'd0: ;
            4'd1: begin lp_y <= lp_y + lp_add; st <= 4'd2; end
            4'd2: begin g15_r <= g15; st <= 4'd3; end
            4'd3: begin v15_r <= g15_r; p2_r <= p2; st <= 4'd4; end
            4'd4: begin yc_r <= sat16(yc_p >>> 14); st <= 4'd5; end
            4'd5: begin x15_r <= y23c >>> 8; st <= 4'd6; end
            4'd6: begin bq_y23_r <= bq_y_s; bq_y15_r <= drive_slider ? bq_y15_s : (bq_y >>> 8); st <= 4'd7; end
            4'd7: begin s1 <= bq_s1; st <= 4'd8; end
            4'd8: begin s2 <= bq_s2; st <= 4'd9; end
            4'd9: begin data <= blend_sat; st <= 4'd0; end
            default: st <= 4'd0;
        endcase
    end
endmodule
