// ADS1115 single-ended A0..A3 poller.
// 7-bit address 0x48 first, then 0x49. Single-shot, +/-4.096 V, 475 SPS.
// Conversion is completed by polling the OS bit in the config register.
module ads1115_ctrl(
    input clk,
    input rst_n,
    output reg i2c_start,
    output reg [2:0] i2c_op,
    output reg [7:0] i2c_din,
    input [7:0] i2c_dout,
    input i2c_ack,
    input i2c_done,
    input i2c_busy,
    output reg [15:0] raw0,
    output reg [15:0] raw1,
    output reg [15:0] raw2,
    output reg [15:0] raw3,
    output reg [6:0] addr_used,
    output reg device_present,
    output reg [15:0] seq,
    output reg [15:0] errors,
    output reg round_valid,
    output reg report_error,
    output reg [7:0] error_stage
);
    localparam [2:0] OP_START=3'd0, OP_RESTART=3'd1, OP_WRITE=3'd2,
                     OP_READ_ACK=3'd3, OP_READ_NACK=3'd4, OP_STOP=3'd5,
                     OP_RECOVER=3'd6;
    localparam [2:0] T_PROBE48=3'd0, T_PROBE49=3'd1, T_CONFIG=3'd2,
                     T_READCFG=3'd3, T_READDATA=3'd4, T_RECOVER=3'd5;

    // ---------------- transaction engine ----------------
    reg [2:0] txn_type;
    reg [6:0] txn_addr;
    reg [15:0] txn_cfg;
    reg [3:0] txn_idx;
    reg [3:0] txn_len;
    reg txn_busy, txn_done, txn_nack, start_sent;
    reg [21:0] txn_wait;
    reg [15:0] read_hi, read_lo, txn_rdata;
    reg start_req;
    reg [2:0] req_type;
    reg [6:0] req_addr;
    reg [15:0] req_cfg;
    reg [3:0] te_state;
    localparam [3:0] TE_IDLE=4'd0, TE_ISSUE=4'd1, TE_WAIT=4'd2;

    function [2:0] op_of;
        input [2:0] typ;
        input [3:0] idx;
        begin
            case (typ)
                T_PROBE48, T_PROBE49: begin
                    case (idx)
                        4'd0: op_of = OP_START;
                        4'd1: op_of = OP_WRITE;
                        default: op_of = OP_STOP;
                    endcase
                end
                T_CONFIG: begin
                    case (idx)
                        4'd0: op_of = OP_START;
                        4'd1,4'd2,4'd3,4'd4: op_of = OP_WRITE;
                        default: op_of = OP_STOP;
                    endcase
                end
                T_RECOVER: op_of = OP_RECOVER;
                default: begin // READCFG / READDATA: pointer, repeated START, read
                    case (idx)
                        4'd0: op_of = OP_START;
                        4'd1,4'd2: op_of = OP_WRITE;
                        4'd3: op_of = OP_RESTART;
                        4'd4: op_of = OP_WRITE;
                        4'd5: op_of = OP_READ_ACK;
                        4'd6: op_of = OP_READ_NACK;
                        default: op_of = OP_STOP;
                    endcase
                end
            endcase
        end
    endfunction

    function [7:0] din_of;
        input [2:0] typ;
        input [3:0] idx;
        input [6:0] a7;
        input [15:0] cfg;
        begin
            din_of = 8'h00;
            case (typ)
                T_PROBE48, T_PROBE49: if (idx == 4'd1) din_of = {a7, 1'b0};
                T_CONFIG: begin
                    if (idx == 4'd1) din_of = {a7, 1'b0};
                    else if (idx == 4'd2) din_of = 8'h01;
                    else if (idx == 4'd3) din_of = cfg[15:8];
                    else if (idx == 4'd4) din_of = cfg[7:0];
                end
                T_READCFG, T_READDATA: begin
                    if (idx == 4'd1) din_of = {a7, 1'b0};
                    else if (idx == 4'd2) din_of = (typ == T_READCFG) ? 8'h01 : 8'h00;
                    else if (idx == 4'd4) din_of = {a7, 1'b1};
                end
                default: din_of = 8'h00;
            endcase
        end
    endfunction

    function [3:0] len_of;
        input [2:0] typ;
        begin
            case (typ)
                T_PROBE48, T_PROBE49: len_of = 4'd3;
                T_CONFIG: len_of = 4'd6;
                T_RECOVER: len_of = 4'd1;
                default: len_of = 4'd8;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            txn_type <= T_PROBE48;
            txn_addr <= 7'h48;
            txn_cfg <= 16'h0000;
            txn_idx <= 4'd0;
            txn_len <= 4'd3;
            txn_busy <= 1'b0;
            txn_done <= 1'b0;
            txn_nack <= 1'b0;
            start_sent <= 1'b0;
            txn_wait <= 22'd0;
            read_hi <= 16'd0;
            read_lo <= 16'd0;
            txn_rdata <= 16'd0;
            te_state <= TE_IDLE;
            i2c_start <= 1'b0;
            i2c_op <= OP_START;
            i2c_din <= 8'd0;
        end else begin
            txn_done <= 1'b0;
            i2c_start <= 1'b0;
            if (txn_busy) begin
                if (txn_wait != 22'h3FFFFF) txn_wait <= txn_wait + 1'b1;
                else begin
                    txn_busy <= 1'b0;
                    txn_nack <= 1'b1;
                    txn_done <= 1'b1;
                    start_sent <= 1'b0;
                    te_state <= TE_IDLE;
                end
            end

            case (te_state)
                TE_IDLE: begin
                    if (!txn_busy && txn_done == 1'b0) begin
                        // waiting for a start request
                    end
                end
                TE_ISSUE: begin
                    if (!i2c_busy && !start_sent) begin
                        i2c_op <= op_of(txn_type, txn_idx);
                        i2c_din <= din_of(txn_type, txn_idx, txn_addr, txn_cfg);
                        i2c_start <= 1'b1;
                        start_sent <= 1'b1;
                        te_state <= TE_WAIT;
                    end
                end
                TE_WAIT: begin
                    if (i2c_done) begin
                        start_sent <= 1'b0;
                        if (op_of(txn_type, txn_idx) == OP_READ_ACK) begin
                            read_hi <= {read_hi[7:0], i2c_dout};
                        end else if (op_of(txn_type, txn_idx) == OP_READ_NACK) begin
                            read_lo <= {read_lo[7:0], i2c_dout};
                            txn_rdata <= {read_hi[7:0], i2c_dout};
                        end
                        if (op_of(txn_type, txn_idx) == OP_WRITE && !i2c_ack) begin
                            txn_busy <= 1'b0;
                            txn_nack <= 1'b1;
                            txn_done <= 1'b1;
                            te_state <= TE_IDLE;
                        end else if (txn_idx == txn_len - 1'b1) begin
                            txn_busy <= 1'b0;
                            txn_done <= 1'b1;
                            te_state <= TE_IDLE;
                        end else begin
                            txn_idx <= txn_idx + 1'b1;
                            te_state <= TE_ISSUE;
                        end
                    end
                end
                default: te_state <= TE_IDLE;
            endcase

            // Start request from the high-level controller.
            if (!txn_busy && !txn_done && te_state == TE_IDLE && start_req) begin
                txn_busy <= 1'b1;
                txn_done <= 1'b0;
                txn_nack <= 1'b0;
                txn_idx <= 4'd0;
                txn_len <= len_of(req_type);
                txn_type <= req_type;
                txn_addr <= req_addr;
                txn_cfg <= req_cfg;
                txn_wait <= 22'd0;
                start_sent <= 1'b0;
                read_hi <= 16'd0;
                read_lo <= 16'd0;
                te_state <= TE_ISSUE;
            end
        end
    end

    // ---------------- high-level ADC sequencer ----------------
    localparam [3:0] P_POWER=4'd0, P_PROBE48=4'd1, P_PROBE49=4'd2,
                     P_WAIT_PROBE=4'd3, P_CONFIG=4'd4, P_WAIT_CONFIG=4'd5,
                     P_WAIT_CNV=4'd6, P_POLL=4'd7, P_WAIT_POLL=4'd8,
                     P_WAIT_POLL_DELAY=4'd9, P_READ=4'd10, P_WAIT_READ=4'd11,
                     P_RECOVER=4'd12, P_WAIT_RECOVER=4'd13, P_RETRY=4'd14;
    reg [3:0] adc_state;
    reg [1:0] ch;
    reg [21:0] delay_cnt;
    reg [4:0] poll_cnt;
    reg [2:0] probe_phase;
    reg [6:0] probe_addr;
    reg [25:0] retry_cnt;

    function [15:0] cfg_for;
        input [1:0] c;
        reg [2:0] mux;
        begin
            case (c)
                2'd0: mux = 3'b100; // AIN0
                2'd1: mux = 3'b101;
                2'd2: mux = 3'b110;
                default: mux = 3'b111;
            endcase
            cfg_for = {1'b1, mux, 3'b001, 1'b1, 3'b110, 1'b0, 1'b0, 1'b0, 2'b11};
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_state <= P_POWER;
            ch <= 2'd0;
            delay_cnt <= 22'd0;
            poll_cnt <= 5'd0;
            probe_phase <= 3'd0;
            probe_addr <= 7'h48;
            retry_cnt <= 26'd0;
            raw0 <= 16'd0;
            raw1 <= 16'd0;
            raw2 <= 16'd0;
            raw3 <= 16'd0;
            addr_used <= 7'h00;
            device_present <= 1'b0;
            seq <= 16'd0;
            errors <= 16'd0;
            round_valid <= 1'b0;
            report_error <= 1'b0;
            error_stage <= 8'd0;
            start_req <= 1'b0;
            req_type <= T_PROBE48;
            req_addr <= 7'h48;
            req_cfg <= 16'd0;
        end else begin
            round_valid <= 1'b0;
            report_error <= 1'b0;
            start_req <= 1'b0;

            case (adc_state)
                P_POWER: begin
                    if (delay_cnt == 22'd2499999) begin
                        delay_cnt <= 22'd0;
                        probe_phase <= 3'd0;
                        adc_state <= P_PROBE48;
                    end else delay_cnt <= delay_cnt + 1'b1;
                end

                P_PROBE48: begin
                    if (!txn_busy) begin
                        req_type <= T_PROBE48;
                        req_addr <= 7'h48;
                        req_cfg <= 16'h0000;
                        start_req <= 1'b1;
                        probe_phase <= 3'd1;
                        adc_state <= P_WAIT_PROBE;
                    end
                end

                P_PROBE49: begin
                    if (!txn_busy) begin
                        req_type <= T_PROBE49;
                        req_addr <= 7'h49;
                        req_cfg <= 16'h0000;
                        start_req <= 1'b1;
                        probe_phase <= 3'd2;
                        adc_state <= P_WAIT_PROBE;
                    end
                end

                P_WAIT_PROBE: begin
                    if (txn_done) begin
                        if (!txn_nack) begin
                            addr_used <= (probe_phase == 3'd1) ? 7'h48 : 7'h49;
                            device_present <= 1'b1;
                            ch <= 2'd0;
                            adc_state <= P_CONFIG;
                        end else if (probe_phase == 3'd1) begin
                            adc_state <= P_PROBE49;
                        end else begin
                            device_present <= 1'b0;
                            addr_used <= 7'h00;
                            errors <= errors + 1'b1;
                            error_stage <= 8'd1;
                            report_error <= 1'b1;
                            adc_state <= P_RECOVER;
                        end
                    end
                end

                P_CONFIG: begin
                    if (!txn_busy) begin
                        req_type <= T_CONFIG;
                        req_addr <= addr_used;
                        req_cfg <= cfg_for(ch);
                        start_req <= 1'b1;
                        adc_state <= P_WAIT_CONFIG;
                    end
                end

                P_WAIT_CONFIG: begin
                    if (txn_done) begin
                        if (txn_nack) begin
                            errors <= errors + 1'b1;
                            error_stage <= 8'd2;
                            report_error <= 1'b1;
                            adc_state <= P_RECOVER;
                        end else begin
                            delay_cnt <= 22'd0;
                            poll_cnt <= 5'd0;
                            adc_state <= P_WAIT_CNV;
                        end
                    end
                end

                P_WAIT_CNV: begin
                    if (delay_cnt == 22'd9999) begin
                        delay_cnt <= 22'd0;
                        adc_state <= P_POLL;
                    end else delay_cnt <= delay_cnt + 1'b1;
                end

                P_POLL: begin
                    if (!txn_busy) begin
                        req_type <= T_READCFG;
                        req_addr <= addr_used;
                        req_cfg <= 16'h0000;
                        start_req <= 1'b1;
                        adc_state <= P_WAIT_POLL;
                    end
                end

                P_WAIT_POLL: begin
                    if (txn_done) begin
                        if (txn_nack) begin
                            errors <= errors + 1'b1;
                            error_stage <= 8'd3;
                            report_error <= 1'b1;
                            adc_state <= P_RECOVER;
                        end else if (txn_rdata[15]) begin
                            adc_state <= P_READ;
                        end else if (poll_cnt == 5'd20) begin
                            errors <= errors + 1'b1;
                            error_stage <= 8'd3;
                            report_error <= 1'b1;
                            adc_state <= P_RECOVER;
                        end else begin
                            poll_cnt <= poll_cnt + 1'b1;
                            delay_cnt <= 22'd0;
                            adc_state <= P_WAIT_POLL_DELAY;
                        end
                    end
                end

                P_WAIT_POLL_DELAY: begin
                    if (delay_cnt == 22'd4999) begin
                        delay_cnt <= 22'd0;
                        adc_state <= P_POLL;
                    end else delay_cnt <= delay_cnt + 1'b1;
                end

                P_READ: begin
                    if (!txn_busy) begin
                        req_type <= T_READDATA;
                        req_addr <= addr_used;
                        req_cfg <= 16'h0000;
                        start_req <= 1'b1;
                        adc_state <= P_WAIT_READ;
                    end
                end

                P_WAIT_READ: begin
                    if (txn_done) begin
                        if (txn_nack) begin
                            errors <= errors + 1'b1;
                            error_stage <= 8'd4;
                            report_error <= 1'b1;
                            adc_state <= P_RECOVER;
                        end else begin
                            case (ch)
                                2'd0: raw0 <= txn_rdata;
                                2'd1: raw1 <= txn_rdata;
                                2'd2: raw2 <= txn_rdata;
                                default: raw3 <= txn_rdata;
                            endcase
                            if (ch == 2'd3) begin
                                ch <= 2'd0;
                                seq <= seq + 1'b1;
                                round_valid <= 1'b1;
                                adc_state <= P_CONFIG;
                            end else begin
                                ch <= ch + 1'b1;
                                adc_state <= P_CONFIG;
                            end
                        end
                    end
                end

                P_RECOVER: begin
                    device_present <= 1'b0;
                    req_type <= T_RECOVER;
                    req_addr <= 7'h00;
                    req_cfg <= 16'h0000;
                    start_req <= 1'b1;
                    adc_state <= P_WAIT_RECOVER;
                end

                P_WAIT_RECOVER: begin
                    if (txn_done) begin
                        delay_cnt <= 22'd0;
                        adc_state <= P_RETRY;
                    end
                end

                P_RETRY: begin
                    if (retry_cnt == 26'd24999999) begin
                        retry_cnt <= 26'd0;
                        probe_phase <= 3'd0;
                        adc_state <= P_PROBE48;
                    end else retry_cnt <= retry_cnt + 1'b1;
                end

                default: adc_state <= P_POWER;
            endcase
        end
    end
endmodule



