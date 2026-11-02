// Timed music-hall event queue and legacy-BLE event expander.
// Runs in sys_clk.  An audio-domain toggle is the reliable sample-time tick;
// 1088 audio clocks per sample are never converted to a nominal 48 kHz.
module song_scheduler #(
    parameter integer QUEUE_AW = 7              // 128 slots
)(
    input sys_clk,
    input sys_rst_n,
    input audio_tick_toggle,
    input [63:0] in_perf,
    input in_we,
    input [2:0] in_cmd,                          // 0=begin,1=play,2=stop
    input [31:0] in_play_id,
    input [31:0] in_event_count,
    input [31:0] in_duration_samples,
    input [31:0] in_lead_samples,
    input ev_full,
    output reg [23:0] ev_data,
    output reg ev_we,
    output reg song_active
);

    (* syn_ramstyle = "block_ram" *) reg [63:0] qmem [0:(1<<QUEUE_AW)-1];
    reg [QUEUE_AW-1:0] q_wr, q_rd;
    reg [QUEUE_AW:0] q_count;
    reg [31:0] duration_samples;
    reg [31:0] sample_count;
    reg [31:0] start_at;
    reg playing, waiting_start;
    reg [1:0] tick_sync;
    reg tick_prev;
    reg release_pending;
    reg cur_valid;
    reg [1:0] sub;
    reg [2:0] cur_type;
    reg [7:0] cur_a, cur_b, cur_flags;
    reg pop_done;
    reg head_stall;
    reg clear_q;
    reg enq, deq;

    wire q_empty = (q_count == 0);
    wire q_full = (q_count == (1 << QUEUE_AW));
    reg [63:0] q_head_r;
    always @(posedge sys_clk) q_head_r <= qmem[q_rd];
    wire [31:0] q_head_time = q_head_r[31:0];
    wire [7:0] q_head_type = q_head_r[39:32];
    wire [7:0] q_head_a = q_head_r[47:40];
    wire [7:0] q_head_b = q_head_r[55:48];
    wire [7:0] q_head_flags = q_head_r[63:56];
    wire tick_edge = (tick_sync[1] != tick_prev);
    wire [31:0] position_now = waiting_start ? 32'd0 :
                               (sample_count >= start_at) ? (sample_count - start_at) : 32'd0;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            tick_sync <= 2'b00;
            tick_prev <= 1'b0;
            sample_count <= 32'd0;
        end else begin
            tick_sync <= {tick_sync[0], audio_tick_toggle};
            tick_prev <= tick_sync[1];
            if (tick_edge) sample_count <= sample_count + 32'd1;
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            q_wr <= 0; q_rd <= 0; q_count <= 0;
            duration_samples <= 0;
            start_at <= 0;
            playing <= 0; waiting_start <= 0;
            song_active <= 0;
            release_pending <= 0; cur_valid <= 0; sub <= 0;
            ev_data <= 0; ev_we <= 0;
        end else begin
            ev_we <= 1'b0;
            pop_done = 1'b0;
            head_stall <= 1'b0;
            clear_q = 1'b0;
            enq = 1'b0;
            deq = 1'b0;

            // Command inputs are one-cycle pulses from the UART parser.
            if (in_cmd == 3'd1) begin
                clear_q = 1'b1;
                duration_samples <= in_duration_samples;
                playing <= 1'b0; waiting_start <= 1'b0;
                song_active <= 1'b0; release_pending <= 1'b0;
                cur_valid <= 1'b0;
            end else if (in_cmd == 3'd2) begin
                start_at <= sample_count + in_lead_samples;
                waiting_start <= 1'b1;
                playing <= 1'b1;
                release_pending <= 1'b0;
            end else if (in_cmd == 3'd3) begin
                clear_q = 1'b1;
                playing <= 1'b0;
                waiting_start <= 1'b0;
                song_active <= 1'b0;
                cur_valid <= 1'b0;
                release_pending <= 1'b1;
            end

            // Queue write: ESP writes events in time order while the song is
            // being preloaded or streamed. Full queue is an explicit error.
            if (in_we && !q_full && !clear_q) begin
                enq = 1'b1;
                qmem[q_wr] <= in_perf;
                if (q_empty) head_stall <= 1'b1;
            end

            if (waiting_start && (sample_count >= start_at)) begin
                waiting_start <= 1'b0;
                song_active <= 1'b1;
            end

            if (playing && !waiting_start) begin
                if ((position_now >= duration_samples) && q_empty && !cur_valid && !head_stall) begin
                    clear_q = 1'b1;
                    playing <= 1'b0;
                    song_active <= 1'b0;
                    cur_valid <= 1'b0;
                    release_pending <= 1'b1;
                end else begin
                    // Drag the head event into the expander once its absolute
                    // sample time has arrived.  Do not advance early.
                    if (!cur_valid && !head_stall && !q_empty && (q_head_time <= position_now)) begin
                        cur_type <= q_head_type;
                        cur_a <= q_head_a;
                        cur_b <= q_head_b;
                        cur_flags <= q_head_flags;
                        cur_valid <= 1'b1;
                        sub <= 2'd0;
                    end
                end

                // Expand one performance record into one or more legacy BLE
                // events. A guitar pluck first sets fret and palm, then plucks.
                if (cur_valid && !ev_full && !clear_q) begin
                    ev_we <= 1'b1;
                    case (cur_type)
                        8'd1: begin ev_data <= {8'h01, cur_a, cur_b}; cur_valid <= 1'b0; pop_done=1'b1; end
                        8'd2: begin ev_data <= {8'h02, cur_a, 8'd0}; cur_valid <= 1'b0; pop_done=1'b1; end
                        8'd3: begin ev_data <= {8'h03, cur_a, cur_b}; cur_valid <= 1'b0; pop_done=1'b1; end
                        8'd4: begin
                            case (sub)
                                2'd0: ev_data <= {8'h21, 4'h0, cur_flags[3:0], 8'h00};
                                2'd1: ev_data <= {8'h22, {7'd0, cur_flags[4]}, 8'd0};
                                default: ev_data <= {8'h20, cur_a, cur_b};
                            endcase
                            if (sub == 2'd2) begin cur_valid <= 1'b0; pop_done=1'b1; end else sub <= sub + 2'd1;
                        end
                        8'd6: begin
                            // Parameters are ordered before dependent triggers by
                            // the score compiler. Performance type 6 maps only the
                            // currently supported legacy parameters.
                            case (cur_a)
                                8'd0: ev_data <= {8'h30, cur_b, 8'd0};
                                8'd1: ev_data <= {8'h21, cur_b, 8'd0};
                                8'd2: ev_data <= {8'h22, {7'd0,cur_b[0]}, 8'd0};
                                8'd3: ev_data <= {8'h2A, {7'd0,cur_b[0]}, 8'd0};
                                8'd4: ev_data <= {8'h2B, {7'd0,cur_b[0]}, 8'd0};
                                8'd5: ev_data <= {8'h31, {7'd0,cur_b[0]}, 8'd0};
                                8'd6: ev_data <= {8'h32, {7'd0,cur_b[0]}, 8'd0};
                                default: ev_data <= {8'h00, 8'd0, 8'd0};
                            endcase
                            cur_valid <= 1'b0;
                            pop_done=1'b1;
                        end
                        8'd7: begin ev_data <= {8'h05, 8'd0, 8'd0}; cur_valid <= 1'b0; pop_done=1'b1; end
                        8'd8: begin ev_data <= {8'h06, 8'd0, 8'd0}; cur_valid <= 1'b0; pop_done=1'b1; end
                        default: begin ev_data <= {8'h00, 8'd0, 8'd0}; cur_valid <= 1'b0; pop_done=1'b1; end
                    endcase

                    // Pop after the last expanded sub-event.
                    if (pop_done) begin
                        head_stall <= 1'b1;
                        if (!q_empty) begin
                            deq = 1'b1;
                        end
                        cur_valid <= 1'b0;
                        sub <= 2'd0;
                    end
                end
            end

            // Single queue bookkeeping point: BEGIN/STOP/end clear has
            // priority; otherwise count actual enqueue and dequeue events.
            if (clear_q) begin
                q_wr <= 0;
                q_rd <= 0;
                q_count <= 0;
            end else begin
                if (enq) q_wr <= q_wr + 1'b1;
                if (deq) q_rd <= q_rd + 1'b1;
                case ({enq, deq})
                    2'b00: q_count <= q_count;
                    2'b01: q_count <= q_count - 1'b1;
                    2'b10: q_count <= q_count + 1'b1;
                    2'b11: q_count <= q_count;
                endcase
            end

            // Stop/end release: send legacy BLE_RELEASE_ALL once. Physical TTP/USB
            // notes are not touched by that path in the existing audio controller.
            if (release_pending && !ev_full) begin
                ev_data <= {8'h05, 8'd0, 8'd0};
                ev_we <= 1'b1;
                release_pending <= 1'b0;
            end

        end
    end
endmodule
