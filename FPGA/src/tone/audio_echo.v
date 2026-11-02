// Minimal A3: fixed 4096-half-sample (about 169.8 ms) single echo.
// No feedback loop; A3 controls only dry/wet. The 4096-word RAM uses 12-bit
// pointers. Old contents are masked by fill until the ring has been rewritten.
module audio_echo #(
    parameter integer DEPTH = 4096
)(
    input clk,
    input rst_n,
    input sample_tick,
    input signed [15:0] pcm_in,
    input filter_on,
    input params_ok,
    input [8:0] a3_idx,
    input clear,
    output reg signed [15:0] pcm_out,
    output reg tail_active
);
    localparam [11:0] DEPTH_M1 = DEPTH - 1;
    localparam [1:0] E_IDLE = 2'd0;
    localparam [1:0] E_READ = 2'd1;
    localparam [1:0] E_WRITE = 2'd2;

    function signed [15:0] sat16;
        input signed [31:0] v;
        begin
            sat16 = (v > 32'sd32767) ? 16'sd32767 :
                    (v < -32'sd32768) ? -16'sd32768 : v[15:0];
        end
    endfunction

    (* ram_style = "block" *) reg signed [15:0] mem [0:DEPTH-1];
    reg [11:0] wr_addr;
    reg [11:0] rd_addr;
    reg [12:0] fill;
    reg [1:0] state;
    reg phase;
    reg signed [15:0] x_d1;
    reg signed [15:0] pre_half;
    reg signed [15:0] delayed_raw;
    reg signed [15:0] delayed_hold;
    reg [3:0] mix_q4;
    reg [15:0] tail_hold;

    wire [8:0] a3_safe = (a3_idx > 9'd412) ? 9'd412 : a3_idx;
    wire want_echo = filter_on && params_ok && (a3_safe > 9'd8);
    wire [10:0] mix_calc = ({{2{1'b0}}, a3_safe} << 1) + {2'b0, a3_safe};
    wire [3:0] target_mix = want_echo ? mix_calc[10:7] : 4'd0;

    wire signed [16:0] pre_sum = {{1{pcm_in[15]}}, pcm_in} + {{1{x_d1[15]}}, x_d1};
    wire signed [15:0] pre_now = pre_sum >>> 1;
    wire [11:0] rd_next = wr_addr; // full-ring delay: read before same address write

    wire signed [31:0] x32 = {{16{pcm_in[15]}}, pcm_in};
    wire signed [31:0] hold32 = {{16{delayed_hold[15]}}, delayed_hold};
    wire signed [31:0] diff32 = hold32 - x32;
    wire signed [35:0] diff36 = {{4{diff32[31]}}, diff32};
    wire signed [35:0] m0 = mix_q4[0] ? diff36 : 36'sd0;
    wire signed [35:0] m1 = mix_q4[1] ? (diff36 <<< 1) : 36'sd0;
    wire signed [35:0] m2 = mix_q4[2] ? (diff36 <<< 2) : 36'sd0;
    wire signed [35:0] m3 = mix_q4[3] ? (diff36 <<< 3) : 36'sd0;
    wire signed [35:0] mix_sum = m0 + m1 + m2 + m3;
    wire signed [31:0] out_sum = x32 + (mix_sum >>> 4);
    wire signed [15:0] out_sat = sat16(out_sum);
    wire input_loud = (pcm_in > 16'sd255) || (pcm_in < -16'sd255);
    wire delayed_loud = (delayed_hold > 16'sd255) || (delayed_hold < -16'sd255);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_addr <= 12'd0; rd_addr <= 12'd0; fill <= 13'd0;
            state <= E_IDLE; phase <= 1'b0;
            x_d1 <= 16'sd0; pre_half <= 16'sd0;
            delayed_raw <= 16'sd0; delayed_hold <= 16'sd0;
            mix_q4 <= 4'd0; tail_hold <= 16'd0;
            pcm_out <= 16'sd0; tail_active <= 1'b0;
        end else if (clear) begin
            wr_addr <= 12'd0; rd_addr <= 12'd0; fill <= 13'd0;
            state <= E_IDLE; phase <= 1'b0;
            x_d1 <= 16'sd0; pre_half <= 16'sd0;
            delayed_raw <= 16'sd0; delayed_hold <= 16'sd0;
            mix_q4 <= 4'd0; tail_hold <= 16'd0;
            pcm_out <= pcm_in; tail_active <= 1'b0;
        end else begin
            if (sample_tick) begin
                if (mix_q4 < target_mix) mix_q4 <= mix_q4 + 1'b1;
                else if (mix_q4 > target_mix) mix_q4 <= mix_q4 - 1'b1;
                pcm_out <= out_sat;
                if (mix_q4 != 4'd0 && (input_loud || delayed_loud)) tail_hold <= 16'd4096;
                else if (tail_hold != 16'd0) tail_hold <= tail_hold - 1'b1;
                tail_active <= (tail_hold != 16'd0) || (mix_q4 != 4'd0 && (input_loud || delayed_loud));
                x_d1 <= pcm_in;
                if (phase == 1'b0) phase <= 1'b1;
                else begin phase <= 1'b0; pre_half <= pre_now; end
            end

            case (state)
                E_IDLE: begin
                    if (sample_tick && phase == 1'b1) begin
                        rd_addr <= rd_next;
                        state <= E_READ;
                    end
                end
                E_READ: begin
                    delayed_raw <= mem[rd_addr];
                    state <= E_WRITE;
                end
                E_WRITE: begin
                    if (fill >= DEPTH[12:0]) delayed_hold <= delayed_raw;
                    else delayed_hold <= 16'sd0;
                    mem[wr_addr] <= pre_half;
                    if (fill < DEPTH[12:0]) fill <= fill + 1'b1;
                    wr_addr <= (wr_addr == DEPTH_M1) ? 12'd0 : wr_addr + 1'b1;
                    state <= E_IDLE;
                end
                default: state <= E_IDLE;
            endcase

            if (!want_echo && mix_q4 == 4'd0) begin
                wr_addr <= 12'd0; rd_addr <= 12'd0; fill <= 13'd0;
                delayed_raw <= 16'sd0; delayed_hold <= 16'sd0;
                state <= E_IDLE; phase <= 1'b0;
                x_d1 <= 16'sd0; pre_half <= 16'sd0;
                tail_hold <= 16'd0; tail_active <= 1'b0;
            end
        end
    end
endmodule
