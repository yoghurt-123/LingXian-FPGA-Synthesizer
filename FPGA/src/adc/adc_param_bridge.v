// ADS1115 four-channel acquisition and a stable sys->audio parameter handshake.
// The I2C/ADC state machines run in the 50 MHz sys_clk domain.  The audio side
// receives a held 64-bit payload only after a toggle request and acknowledges it.
// A2/A3 are stored as reserved normalized targets; they do not affect audio.
module adc_param_bridge #(
    parameter integer TIMEOUT_CLKS = 5250000 // about 105 ms at 50 MHz
)(
    input sys_clk,
    input sys_rst_n,
    inout adc_scl,
    inout adc_sda,
    input audio_clk,
    input audio_rst_n,
    output [8:0] a0_idx,
    output [8:0] a1_idx,
    output [8:0] a2_idx,
    output [8:0] a3_idx,
    output [3:0] param_valid,
    output params_ok,
    (* keep *) output reg [8:0] reserved_a2,
    (* keep *) output reg [8:0] reserved_a3,
    (* keep *) output reg reserved_valid
);
    localparam [15:0] RAW_MAX = 16'd26400; // 3.3 V at PGA +/-4.096 V
    localparam [15:0] RAW_DEAD = 16'd800;  // about 0.1 V bottom dead zone
    localparam [8:0]  IDX_MAX = 9'd412;

    wire i2c_start;
    wire [2:0] i2c_op;
    wire [7:0] i2c_din;
    wire [7:0] i2c_dout;
    wire i2c_ack, i2c_done, i2c_busy;

    i2c_master #(.HALF_CLKS(250)) u_i2c(
        .clk(sys_clk), .rst_n(sys_rst_n),
        .start(i2c_start), .op(i2c_op), .din(i2c_din),
        .dout(i2c_dout), .ack(i2c_ack), .done(i2c_done), .busy(i2c_busy),
        .scl(adc_scl), .sda(adc_sda)
    );

    wire [15:0] raw0, raw1, raw2, raw3;
    wire [6:0] addr_used;
    wire device_present;
    wire [15:0] seq, errors;
    wire round_valid;
    wire report_error;
    wire [7:0] error_stage;

    ads1115_ctrl u_adc(
        .clk(sys_clk), .rst_n(sys_rst_n),
        .i2c_start(i2c_start), .i2c_op(i2c_op), .i2c_din(i2c_din),
        .i2c_dout(i2c_dout), .i2c_ack(i2c_ack), .i2c_done(i2c_done), .i2c_busy(i2c_busy),
        .raw0(raw0), .raw1(raw1), .raw2(raw2), .raw3(raw3),
        .addr_used(addr_used), .device_present(device_present),
        .seq(seq), .errors(errors), .round_valid(round_valid),
        .report_error(report_error), .error_stage(error_stage)
    );

    function [15:0] clamp_raw;
        input [15:0] v;
        begin
            if (v[15]) clamp_raw = 16'd0;
            else if (v > RAW_MAX) clamp_raw = RAW_MAX;
            else clamp_raw = v;
        end
    endfunction

    function [8:0] smooth_to_idx;
        input [17:0] v;
        reg [8:0] q;
        begin
            if (v <= {2'b0, RAW_DEAD}) smooth_to_idx = 9'd0;
            else begin
                q = v[14:6];
                smooth_to_idx = (q > IDX_MAX) ? IDX_MAX : q;
            end
        end
    endfunction

    wire [15:0] r0 = clamp_raw(raw0);
    wire [15:0] r1 = clamp_raw(raw1);
    wire [15:0] r2 = clamp_raw(raw2);
    wire [15:0] r3 = clamp_raw(raw3);

    reg [17:0] sm0, sm1, sm2, sm3;
    reg seen0, seen1, seen2, seen3;

    wire signed [18:0] d0 = $signed({1'b0, r0}) - $signed({1'b0, sm0});
    wire signed [18:0] d1 = $signed({1'b0, r1}) - $signed({1'b0, sm1});
    wire signed [18:0] d2 = $signed({1'b0, r2}) - $signed({1'b0, sm2});
    wire signed [18:0] d3 = $signed({1'b0, r3}) - $signed({1'b0, sm3});

    wire [17:0] sm0_n = !seen0 ? {2'b0, r0} :
                        (d0 > 19'sd8) ? (sm0 + (d0 >>> 2)) :
                        (d0 < -19'sd8) ? (sm0 + (d0 >>> 2)) : sm0;
    wire [17:0] sm1_n = !seen1 ? {2'b0, r1} :
                        (d1 > 19'sd8) ? (sm1 + (d1 >>> 2)) :
                        (d1 < -19'sd8) ? (sm1 + (d1 >>> 2)) : sm1;
    wire [17:0] sm2_n = !seen2 ? {2'b0, r2} :
                        (d2 > 19'sd8) ? (sm2 + (d2 >>> 2)) :
                        (d2 < -19'sd8) ? (sm2 + (d2 >>> 2)) : sm2;
    wire [17:0] sm3_n = !seen3 ? {2'b0, r3} :
                        (d3 > 19'sd8) ? (sm3 + (d3 >>> 2)) :
                        (d3 < -19'sd8) ? (sm3 + (d3 >>> 2)) : sm3;

    reg [25:0] timeout_cnt;
    reg adc_ok_sys;
    reg timeout_sent;
    wire timeout_hit = (timeout_cnt >= TIMEOUT_CLKS - 1);

    reg [8:0] sys_a0, sys_a1, sys_a2, sys_a3;
    reg [3:0] sys_valid;
    reg sys_ok;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            sm0 <= 18'd0; sm1 <= 18'd0; sm2 <= 18'd0; sm3 <= 18'd0;
            seen0 <= 1'b0; seen1 <= 1'b0; seen2 <= 1'b0; seen3 <= 1'b0;
            sys_a0 <= 9'd0; sys_a1 <= 9'd0; sys_a2 <= 9'd0; sys_a3 <= 9'd0;
            sys_valid <= 4'b0000;
            sys_ok <= 1'b0;
            timeout_cnt <= 26'd0;
            adc_ok_sys <= 1'b0;
            timeout_sent <= 1'b0;
        end else begin
            if (round_valid) begin
                sm0 <= sm0_n; sm1 <= sm1_n; sm2 <= sm2_n; sm3 <= sm3_n;
                seen0 <= 1'b1; seen1 <= 1'b1; seen2 <= 1'b1; seen3 <= 1'b1;
                sys_a0 <= smooth_to_idx(sm0_n);
                sys_a1 <= smooth_to_idx(sm1_n);
                sys_a2 <= smooth_to_idx(sm2_n);
                sys_a3 <= smooth_to_idx(sm3_n);
                sys_valid <= 4'b1111;
                sys_ok <= 1'b1;
                timeout_cnt <= 26'd0;
                adc_ok_sys <= 1'b1;
                timeout_sent <= 1'b0;
            end else begin
                if (!timeout_hit) timeout_cnt <= timeout_cnt + 26'd1;
                if (timeout_hit && adc_ok_sys && !timeout_sent) begin
                    adc_ok_sys <= 1'b0;
                    sys_ok <= 1'b0;
                    sys_valid <= 4'b0000;
                    timeout_sent <= 1'b1;
                end
            end
        end
    end

    // Held payload + toggle/ack handshake to the audio domain.
    reg [63:0] payload_hold;
    reg req_toggle;
    reg pending;
    reg payload_dirty;
    reg [1:0] ack_sync;
    reg ack_toggle;

    wire [63:0] payload_now = {sys_a0, sys_a1, sys_a2, sys_a3,
                               sys_valid, sys_ok, 23'd0};

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            payload_hold <= 64'd0;
            req_toggle <= 1'b0;
            pending <= 1'b0;
            payload_dirty <= 1'b0;
            ack_sync <= 2'b00;
        end else begin
            ack_sync <= {ack_sync[0], ack_toggle};

            if (round_valid || (timeout_hit && adc_ok_sys && !timeout_sent))
                payload_dirty <= 1'b1;

            if (!pending && payload_dirty) begin
                payload_hold <= payload_now;
                req_toggle <= ~req_toggle;
                pending <= 1'b1;
                payload_dirty <= 1'b0;
            end else if (pending && (ack_sync[1] == req_toggle)) begin
                pending <= 1'b0;
            end
        end
    end

    // Audio domain capture.  Payload is stable from request until ack.
    reg [1:0] req_sync;
    reg req_prev;
    reg [63:0] payload_cap;
    reg [8:0] aud_a0, aud_a1, aud_a2, aud_a3;
    reg [3:0] aud_valid;
    reg aud_ok;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            req_sync <= 2'b00;
            req_prev <= 1'b0;
            ack_toggle <= 1'b0;
            payload_cap <= 64'd0;
            aud_a0 <= 9'd0; aud_a1 <= 9'd0; aud_a2 <= 9'd0; aud_a3 <= 9'd0;
            aud_valid <= 4'b0000;
            aud_ok <= 1'b0;
            reserved_a2 <= 9'd0;
            reserved_a3 <= 9'd0;
            reserved_valid <= 1'b0;
        end else begin
            req_sync <= {req_sync[0], req_toggle};
            req_prev <= req_sync[1];
            if (req_sync[1] != req_prev) begin
                payload_cap <= payload_hold;
                ack_toggle <= req_sync[1];
                aud_a0 <= payload_hold[63:55];
                aud_a1 <= payload_hold[54:46];
                aud_a2 <= payload_hold[45:37];
                aud_a3 <= payload_hold[36:28];
                aud_valid <= payload_hold[27:24];
                aud_ok <= payload_hold[23];
                reserved_a2 <= payload_hold[45:37];
                reserved_a3 <= payload_hold[36:28];
                reserved_valid <= payload_hold[26] & payload_hold[27];
            end
        end
    end

    assign a0_idx = aud_a0;
    assign a1_idx = aud_a1;
    assign a2_idx = aud_a2;
    assign a3_idx = aud_a3;
    assign param_valid = aud_valid;
    assign params_ok = aud_ok;
endmodule
