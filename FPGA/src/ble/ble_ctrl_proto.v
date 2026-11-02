module ble_ctrl_proto(
    input sys_clk,
    input rst_n,
    input uart_rx,
    output uart_tx,
    output reg [23:0] ev_data,
    output reg ev_we,
    input ev_full,
    output reg overflow,
    output reg [63:0] song_perf,
    output reg song_we,
    output reg [2:0] song_cmd,
    output reg [31:0] song_play_id,
    output reg [31:0] song_event_count,
    output reg [31:0] song_duration_samples,
    output reg [31:0] song_lead_samples
);
    localparam integer CLKS_PER_BIT = 434;
    localparam [7:0] H0 = 8'hA5;
    localparam [7:0] H1 = 8'h5A;
    localparam [7:0] TYPE_PING = 8'h01;
    localparam [7:0] TYPE_PING_RSP = 8'h81;
    localparam [7:0] TYPE_EVENT = 8'h10;
    localparam [7:0] TYPE_QUERY = 8'h11;
    localparam [7:0] TYPE_QUERY_RSP = 8'h91;
    localparam [7:0] TYPE_SONG_BEGIN = 8'h30;
    localparam [7:0] TYPE_SONG_EVENT = 8'h31;
    localparam [7:0] TYPE_SONG_PLAY = 8'h32;
    localparam [7:0] TYPE_SONG_STOP = 8'h33;
    localparam [2:0] P_H0=3'd0, P_H1=3'd1, P_TYPE=3'd2, P_SEQ=3'd3,
                     P_LEN=3'd4, P_PAYLOAD=3'd5, P_CRC=3'd6;
    localparam [2:0] T_IDLE=3'd0, T_WAIT=3'd1;
    localparam integer FRAME_TIMEOUT = 100000;

    wire [7:0] rx_data;
    wire rx_valid, rx_err;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx(
        .clk(sys_clk), .rst_n(rst_n), .rx(uart_rx),
        .data(rx_data), .valid(rx_valid), .frame_err(rx_err)
    );

    reg [7:0] tx_byte;
    reg tx_start;
    wire tx_busy;
    ble_uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx(
        .clk(sys_clk), .rst_n(rst_n), .start(tx_start),
        .data(tx_byte), .tx(uart_tx), .busy(tx_busy)
    );

    function [7:0] crc8_update;
        input [7:0] crc;
        input [7:0] value;
        integer i;
        reg [7:0] c;
        begin
            c = crc ^ value;
            for (i = 0; i < 8; i = i + 1)
                c = c[7] ? ((c << 1) ^ 8'h07) : (c << 1);
            crc8_update = c;
        end
    endfunction

    reg [2:0] pstate;
    reg [7:0] ptype, pseq, plen, pcrc;
    reg [3:0] pcount;
    reg [7:0] payload [0:15];
    reg [16:0] timeout_count;

    reg [7:0] tx_frame [0:15];
    reg [4:0] tx_len, tx_index;
    reg reply_pending, tx_seen;
    reg [2:0] tstate;

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            pstate <= P_H0;
            ptype <= 0; pseq <= 0; plen <= 0; pcrc <= 0; pcount <= 0;
            timeout_count <= 0;
            ev_data <= 0; ev_we <= 0; overflow <= 0;
            song_perf <= 0; song_we <= 0; song_cmd <= 0;
            song_play_id <= 0; song_event_count <= 0; song_duration_samples <= 0; song_lead_samples <= 0;
            tx_byte <= 0; tx_start <= 0;
            tx_len <= 0; tx_index <= 0; reply_pending <= 0; tx_seen <= 0; tstate <= T_IDLE;
        end else begin
            ev_we <= 1'b0;
            song_we <= 1'b0;
            song_cmd <= 3'd0;
            tx_start <= 1'b0;

            if (rx_valid) begin
                timeout_count <= 0;
                case (pstate)
                    P_H0: if (rx_data == H0) pstate <= P_H1;
                    P_H1: begin
                        if (rx_data == H1) pstate <= P_TYPE;
                        else if (rx_data == H0) pstate <= P_H1;
                        else pstate <= P_H0;
                    end
                    P_TYPE: begin
                        ptype <= rx_data;
                        pcrc <= crc8_update(8'h00, rx_data);
                        pstate <= P_SEQ;
                    end
                    P_SEQ: begin
                        pseq <= rx_data;
                        pcrc <= crc8_update(pcrc, rx_data);
                        pstate <= P_LEN;
                    end
                    P_LEN: begin
                        plen <= rx_data;
                        pcrc <= crc8_update(pcrc, rx_data);
                        pcount <= 0;
                        if (rx_data > 8'd16) pstate <= P_H0;
                        else if (rx_data == 0) pstate <= P_CRC;
                        else pstate <= P_PAYLOAD;
                    end
                    P_PAYLOAD: begin
                        payload[pcount] <= rx_data;
                        pcrc <= crc8_update(pcrc, rx_data);
                        if (pcount + 1'b1 == plen) pstate <= P_CRC;
                        else pcount <= pcount + 1'b1;
                    end
                    P_CRC: begin
                        if (rx_data == pcrc) begin
                            if (ptype == TYPE_SONG_BEGIN && plen == 16) begin
                                song_play_id <= {payload[3],payload[2],payload[1],payload[0]};
                                song_event_count <= {payload[7],payload[6],payload[5],payload[4]};
                                song_duration_samples <= {payload[11],payload[10],payload[9],payload[8]};
                                song_cmd <= 3'd1;
                            end else if (ptype == TYPE_SONG_EVENT && plen == 8) begin
                                song_perf <= {payload[7],payload[6],payload[5],payload[4],payload[3],payload[2],payload[1],payload[0]};
                                song_we <= 1'b1;
                            end else if (ptype == TYPE_SONG_PLAY && plen == 12) begin
                                song_play_id <= {payload[3],payload[2],payload[1],payload[0]};
                                song_lead_samples <= {payload[7],payload[6],payload[5],payload[4]};
                                song_cmd <= 3'd2;
                            end else if (ptype == TYPE_SONG_STOP && plen >= 4) begin
                                song_play_id <= {payload[3],payload[2],payload[1],payload[0]};
                                song_cmd <= 3'd3;
                            end else if (ptype == TYPE_EVENT && plen == 3) begin
                                if (ev_full) begin
                                    overflow <= 1'b1;
                                end else begin
                                    ev_data <= {payload[0], payload[1], payload[2]};
                                    ev_we <= 1'b1;
                                end
                            end else if (ptype == TYPE_PING && plen == 0) begin
                                if (!reply_pending && tstate == T_IDLE) begin
                                    tx_frame[0] <= H0;
                                    tx_frame[1] <= H1;
                                    tx_frame[2] <= TYPE_PING_RSP;
                                    tx_frame[3] <= pseq;
                                    tx_frame[4] <= 8'h00;
                                    tx_frame[5] <= crc8_update(
                                        crc8_update(crc8_update(8'h00, TYPE_PING_RSP), pseq), 8'h00);
                                    tx_len <= 5'd6;
                                    reply_pending <= 1'b1;
                                end
                            end else if (ptype == TYPE_QUERY && plen == 1 && payload[0] == 8'h01) begin
                                if (!reply_pending && tstate == T_IDLE) begin
                                    tx_frame[0] <= H0;
                                    tx_frame[1] <= H1;
                                    tx_frame[2] <= TYPE_QUERY_RSP;
                                    tx_frame[3] <= pseq;
                                    tx_frame[4] <= 8'd6;
                                    tx_frame[5] <= 8'h03; // protocol v3
                                    tx_frame[6] <= 8'hFF; // caps bits 7:0
                                    tx_frame[7] <= 8'hFF; // caps bits 15:8
                                    tx_frame[8] <= 8'h03; // caps bits 23:16: timed queue + bulk
                                    tx_frame[9] <= 8'h00; // caps bits 31:24
                                    tx_frame[10] <= {7'd0, overflow};
                                    tx_frame[11] <= crc8_update(
                                        crc8_update(crc8_update(
                                        crc8_update(crc8_update(
                                        crc8_update(crc8_update(crc8_update(
                                        crc8_update(8'h00, TYPE_QUERY_RSP), pseq), 8'h06),
                                        8'h03), 8'hFF), 8'hFF), 8'h03), 8'h00),
                                        {7'd0, overflow});
                                    tx_len <= 5'd12;
                                    reply_pending <= 1'b1;
                                end
                            end
                        end
                        pstate <= P_H0;
                    end
                    default: pstate <= P_H0;
                endcase
            end else if (rx_err) begin
                pstate <= P_H0;
                timeout_count <= 0;
            end else if (pstate != P_H0) begin
                if (timeout_count == FRAME_TIMEOUT) pstate <= P_H0;
                else timeout_count <= timeout_count + 1'b1;
            end

            if (reply_pending && !tx_busy) begin
                tx_byte <= tx_frame[0];
                tx_start <= 1'b1;
                tx_index <= 5'd1;
                reply_pending <= 1'b0;
                tx_seen <= 1'b0;
                tstate <= T_WAIT;
            end else if (tstate == T_WAIT) begin
                if (tx_busy) tx_seen <= 1'b1;
                else if (tx_seen) begin
                    if (tx_index >= tx_len) tstate <= T_IDLE;
                    else begin
                        tx_byte <= tx_frame[tx_index];
                        tx_start <= 1'b1;
                        tx_index <= tx_index + 1'b1;
                        tx_seen <= 1'b0;
                    end
                end
            end
        end
    end
endmodule

