module usb_visualizer #(
    parameter [15:0] FRAME_TICKS = 16'd2413,
    parameter [31:0] SAMPLE_RATE = 32'd48254,
    parameter [8:0] WAVE_COUNT = 9'd256,
    parameter [7:0] BAND_COUNT = 8'd32
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire signed [15:0] pcm,
    input  wire               sample_valid,
    output wire               uart_tx,
    output reg                frame_done,
    output reg  [15:0]        frame_seq,
    output reg  [15:0]        dropped_frames
);
localparam [3:0] S_CAP=4'd0, S_GZ_START=4'd1, S_GZ_RD=4'd2, S_GZ_MUL=4'd3,
                 S_GZ_MAG=4'd4, S_TX_HEAD=4'd5, S_TX_WLOAD=4'd6,
                 S_TX_WWAIT=4'd7, S_TX_WAVE=4'd8, S_TX_SPEC=4'd9,
                 S_TX_CRC=4'd10, S_TX_DONE=4'd11, S_IDLE=4'd12;

reg [3:0] state;
reg [8:0] cap_cnt;
reg [2:0] cap_sub;
reg [6:0] cap_group;
reg signed [15:0] cap_min, cap_max;
(* syn_ramstyle = "block_ram" *) reg signed [15:0] samp_mem [0:511];
(* syn_ramstyle = "block_ram" *) reg [31:0] wave_snap [0:127];
reg [7:0] spec_snap [0:31];

reg [11:0] frame_tick;
reg [4:0] gz_band;
reg [8:0] gz_idx;
reg signed [31:0] gz_s1, gz_s2;
reg signed [15:0] gz_coeff;
reg signed [15:0] gz_sample_q;
reg [31:0] gz_mag;
reg [7:0] gz_level;
reg signed [31:0] dc_sum;
reg signed [15:0] dc_mean;

reg [7:0] wave_raddr;
reg [31:0] wave_q;
reg [7:0] wave_group;
reg [1:0] wave_phase;
reg [4:0] spec_idx;

reg [4:0] tx_byte_idx;
reg [3:0] tx_crc_phase;
reg [15:0] crc;
reg [7:0] byte_val;
reg [7:0] tx_data;
reg tx_start;
reg tx_issue, tx_seen;
reg tx_gap;
reg byte_done;
wire tx_busy;
wire tx_en = (state == S_TX_HEAD || state == S_TX_WAVE || state == S_TX_SPEC || state == S_TX_CRC);
wire crc_en = (state == S_TX_HEAD || state == S_TX_WAVE || state == S_TX_SPEC);

uart_tx #(.CLKS_PER_BIT(57)) u_uart (
    .clk(clk), .rst_n(rst_n), .start(tx_start), .data(tx_data),
    .tx(uart_tx), .busy(tx_busy)
);

function [7:0] hdr_byte;
    input [4:0] idx;
    input [15:0] seq;
    begin
        case (idx)
            5'd0: hdr_byte = 8'hA5;
            5'd1: hdr_byte = 8'h5A;
            5'd2: hdr_byte = 8'h01;
            5'd3: hdr_byte = 8'h02;
            5'd4: hdr_byte = seq[7:0];
            5'd5: hdr_byte = seq[15:8];
            5'd6: hdr_byte = 8'h7E;
            5'd7: hdr_byte = 8'hBC;
            5'd8: hdr_byte = 8'h00;
            5'd9: hdr_byte = 8'h00;
            5'd10: hdr_byte = 8'h00;
            5'd11: hdr_byte = 8'h01;
            5'd12: hdr_byte = 8'd32;
            5'd13: hdr_byte = 8'h00;
            5'd14: hdr_byte = 8'h20;
            5'd15: hdr_byte = 8'h02;
            5'd16: hdr_byte = 8'h01;
            default: hdr_byte = 8'h00;
        endcase
    end
endfunction

function [15:0] crc_step;
    input [15:0] c;
    input [7:0] d;
    integer i;
    reg [15:0] x;
    begin
        x = c ^ {d, 8'h00};
        for (i = 0; i < 8; i = i + 1)
            x = x[15] ? ((x << 1) ^ 16'h1021) : (x << 1);
        crc_step = x;
    end
endfunction

function [5:0] msb64;
    input [63:0] v;
    integer i;
    reg found;
    begin
        msb64 = 6'd0; found = 1'b0;
        for (i=63;i>=0;i=i-1) begin
            if (!found && v[i]) begin msb64 = i[5:0]; found = 1'b1; end
        end
    end
endfunction

function signed [15:0] coef_of;
    input [4:0] b;
    begin
        case (b)
            5'd0: coef_of = 16'sd32766;
            5'd1: coef_of = 16'sd32758;
            5'd2: coef_of = 16'sd32746;
            5'd3: coef_of = 16'sd32729;
            5'd4: coef_of = 16'sd32706;
            5'd5: coef_of = 16'sd32679;
            5'd6: coef_of = 16'sd32647;
            5'd7: coef_of = 16'sd32610;
            5'd8: coef_of = 16'sd32568;
            5'd9: coef_of = 16'sd32522;
            5'd10: coef_of = 16'sd32470;
            5'd11: coef_of = 16'sd32413;
            5'd12: coef_of = 16'sd32352;
            5'd13: coef_of = 16'sd32214;
            5'd14: coef_of = 16'sd32058;
            5'd15: coef_of = 16'sd31881;
            5'd16: coef_of = 16'sd31581;
            5'd17: coef_of = 16'sd31238;
            5'd18: coef_of = 16'sd30715;
            5'd19: coef_of = 16'sd30118;
            5'd20: coef_of = 16'sd29269;
            5'd21: coef_of = 16'sd28106;
            5'd22: coef_of = 16'sd26557;
            5'd23: coef_of = 16'sd24548;
            5'd24: coef_of = 16'sd22006;
            5'd25: coef_of = 16'sd18538;
            5'd26: coef_of = 16'sd14010;
            5'd27: coef_of = 16'sd8351;
            5'd28: coef_of = 16'sd1608;
            5'd29: coef_of = -16'sd6393;
            5'd30: coef_of = -16'sd15091;
            5'd31: coef_of = -16'sd23732;
            default: coef_of = 16'sd0;
        endcase
    end
endfunction

wire signed [15:0] cap_min_n = (cap_sub == 0) ? pcm : ((pcm < cap_min) ? pcm : cap_min);
wire signed [15:0] cap_max_n = (cap_sub == 0) ? pcm : ((pcm > cap_max) ? pcm : cap_max);
wire signed [47:0] gz_prod = gz_s1 * gz_coeff;
wire signed [16:0] gz_x = {gz_sample_q[15],gz_sample_q} - {dc_mean[15],dc_mean};
wire signed [31:0] gz_s0 = {{15{gz_x[16]}}, gz_x} +
                           (gz_prod >>> 14) - gz_s2;
wire signed [23:0] gz_p1 = gz_s1 >>> 8;
wire signed [23:0] gz_p2 = gz_s2 >>> 8;
wire signed [47:0] gz_sq1 = gz_p1 * gz_p1;
wire signed [47:0] gz_sq2 = gz_p2 * gz_p2;
wire signed [47:0] gz_cross0 = gz_p1 * gz_p2;
wire signed [63:0] gz_cross = gz_cross0 * gz_coeff;
wire signed [63:0] gz_cross_shift = (gz_cross) >>> 14;
wire signed [63:0] gz_power = {{16{gz_sq1[47]}},gz_sq1} +
                         {{16{gz_sq2[47]}},gz_sq2} -
                         gz_cross_shift;
wire [63:0] gz_power_abs = gz_power[63] ? (~gz_power + 64'd1) : gz_power;
wire [5:0] gz_msb = msb64(gz_power_abs);
wire [7:0] gz_level_now = (gz_power_abs == 64'd0) ? 8'd0 :
                         (({gz_msb,3'b000} > 8'd255) ? 8'd255 : {gz_msb,3'b000});

always @* begin
    byte_val = 8'd0;
    case (state)
        S_TX_HEAD: byte_val = hdr_byte(tx_byte_idx, frame_seq);
        S_TX_WAVE: begin
            case (wave_phase)
                2'd0: byte_val = wave_q[7:0];
                2'd1: byte_val = wave_q[15:8];
                2'd2: byte_val = wave_q[23:16];
                default: byte_val = wave_q[31:24];
            endcase
        end
        S_TX_SPEC: byte_val = spec_snap[spec_idx];
        S_TX_CRC: byte_val = (tx_crc_phase == 0) ? crc[7:0] : crc[15:8];
        default: byte_val = 8'd0;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_CAP;
        cap_cnt <= 9'd0;
        cap_sub <= 3'd0;
        cap_group <= 7'd0;
        cap_min <= 16'sd0;
        cap_max <= 16'sd0;
        frame_tick <= 12'd0;
        gz_band <= 5'd0;
        gz_idx <= 9'd0;
        gz_s1 <= 32'sd0;
        gz_s2 <= 32'sd0;
        gz_coeff <= 16'sd0;
        gz_sample_q <= 16'sd0;
        gz_mag <= 32'd0;
        gz_level <= 8'd0;
        dc_sum <= 32'sd0;
        dc_mean <= 16'sd0;
        wave_raddr <= 8'd0;
        wave_q <= 32'd0;
        wave_group <= 8'd0;
        wave_phase <= 2'd0;
        spec_idx <= 5'd0;
        tx_byte_idx <= 5'd0;
        tx_crc_phase <= 4'd0;
        crc <= 16'hFFFF;
        tx_data <= 8'd0;
        tx_start <= 1'b0;
        tx_issue <= 1'b0;
        tx_seen <= 1'b0;
        tx_gap <= 1'b0;
        byte_done <= 1'b0;
        frame_done <= 1'b0;
        frame_seq <= 16'd0;
        dropped_frames <= 16'd0;
    end else begin
        tx_start <= 1'b0;
        byte_done <= 1'b0;
        frame_done <= 1'b0;

        if (sample_valid) begin
            if (frame_tick == FRAME_TICKS - 1) begin
                frame_tick <= 12'd0;
                if (state == S_IDLE) begin
                    state <= S_CAP;
                    dc_sum <= 32'sd0;
                    cap_cnt <= 9'd0;
                    cap_sub <= 3'd0;
                    cap_group <= 7'd0;
                    cap_min <= 16'sd0;
                    cap_max <= 16'sd0;
                end else begin
                    dropped_frames <= dropped_frames + 16'd1;
                end
            end else begin
                frame_tick <= frame_tick + 12'd1;
            end
        end

        if (tx_issue) begin
            if (tx_busy) tx_seen <= 1'b1;
            else if (tx_seen) begin
                tx_issue <= 1'b0;
                tx_seen <= 1'b0;
                tx_gap <= 1'b1;
                byte_done <= 1'b1;
            end
        end else if (tx_gap) begin
            tx_gap <= 1'b0;
        end else if (tx_en) begin
            tx_data <= byte_val;
            tx_start <= 1'b1;
            tx_issue <= 1'b1;
            if (crc_en) crc <= crc_step(crc, byte_val);
        end

        case (state)
            S_IDLE: begin
                // A frame slot starts capture; the timer is free-running.
            end
            S_CAP: begin
                if (sample_valid) begin
                    samp_mem[cap_cnt] <= pcm;
                    dc_sum <= dc_sum + {{16{pcm[15]}},pcm};
                    cap_min <= cap_min_n;
                    cap_max <= cap_max_n;
                    if (cap_sub == 3'd3) begin
                        wave_snap[cap_group] <= {cap_max_n, cap_min_n};
                        cap_sub <= 3'd0;
                        cap_group <= cap_group + 7'd1;
                    end else begin
                        cap_sub <= cap_sub + 3'd1;
                    end
                    if (cap_cnt == 9'd511) begin
                        state <= S_GZ_START;
                    end else begin
                        cap_cnt <= cap_cnt + 9'd1;
                    end
                end
            end
            S_GZ_START: begin
                dc_mean <= dc_sum >>> 9;
                gz_band <= 5'd0;
                gz_idx <= 9'd0;
                gz_s1 <= 32'sd0;
                gz_s2 <= 32'sd0;
                gz_coeff <= coef_of(4'd0);
                state <= S_GZ_RD;
            end
            S_GZ_RD: begin
                gz_sample_q <= samp_mem[gz_idx];
                state <= S_GZ_MUL;
            end
            S_GZ_MUL: begin
                gz_s2 <= gz_s1;
                gz_s1 <= gz_s0;
                if (gz_idx == 9'd511) begin
                    state <= S_GZ_MAG;
                end else begin
                    gz_idx <= gz_idx + 9'd1;
                    state <= S_GZ_RD;
                end
            end
            S_GZ_MAG: begin
                spec_snap[gz_band] <= gz_level_now;
                if (gz_band == 5'd31) begin
                    frame_seq <= frame_seq + 16'd1;
                    crc <= 16'hFFFF;
                    tx_byte_idx <= 5'd0;
                    tx_issue <= 1'b0;
                    tx_seen <= 1'b0;
                    state <= S_TX_HEAD;
                end else begin
                    gz_band <= gz_band + 5'd1;
                    gz_idx <= 9'd0;
                    gz_s1 <= 32'sd0;
                    gz_s2 <= 32'sd0;
                    gz_coeff <= coef_of(gz_band + 5'd1);
                    state <= S_GZ_RD;
                end
            end
            S_TX_HEAD: begin
                if (byte_done) begin
                    tx_issue <= 1'b0;
                    if (tx_byte_idx == 5'd19) begin
                        wave_group <= 8'd0;
                        wave_raddr <= 8'd0;
                        wave_phase <= 2'd0;
                        state <= S_TX_WLOAD;
                    end else begin
                        tx_byte_idx <= tx_byte_idx + 5'd1;
                    end
                end
            end
            S_TX_WLOAD: begin
                wave_raddr <= wave_group;
                state <= S_TX_WWAIT;
            end
            S_TX_WWAIT: begin
                wave_q <= wave_snap[wave_raddr];
                wave_phase <= 2'd0;
                tx_issue <= 1'b0;
                state <= S_TX_WAVE;
            end
            S_TX_WAVE: begin
                if (byte_done) begin
                    tx_issue <= 1'b0;
                    if (wave_phase == 2'd3) begin
                        wave_phase <= 2'd0;
                        if (wave_group == 8'd127) begin
                            spec_idx <= 5'd0;
                            state <= S_TX_SPEC;
                        end else begin
                            wave_group <= wave_group + 8'd1;
                            state <= S_TX_WLOAD;
                        end
                    end else begin
                        wave_phase <= wave_phase + 2'd1;
                    end
                end
            end
            S_TX_SPEC: begin
                if (byte_done) begin
                    tx_issue <= 1'b0;
                    if (spec_idx == 5'd31) begin
                        tx_crc_phase <= 4'd0;
                        state <= S_TX_CRC;
                    end else begin
                        spec_idx <= spec_idx + 5'd1;
                    end
                end
            end
            S_TX_CRC: begin
                if (byte_done) begin
                    tx_issue <= 1'b0;
                    if (tx_crc_phase == 4'd0) begin
                        tx_crc_phase <= 4'd1;
                    end else begin
                        frame_done <= 1'b1;
                        state <= S_TX_DONE;
                    end
                end
            end
            S_TX_DONE: begin
                state <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase
    end
end
endmodule
