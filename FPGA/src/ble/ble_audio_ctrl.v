module ble_audio_ctrl(
    input clk,
    input rst_n,
    input ev_empty,
    input [23:0] ev_data,
    output reg ev_re,
    input [15:0] touch_keys,
    input [15:0] usb_piano_held,
    output reg [15:0] ble_piano_trig,
    output reg [15:0] ble_piano_rel,
    output reg [15:0] ble_piano_held,
    output reg [63:0] ble_piano_vel,
    output reg [1:0] ble_piano_oct,
    output reg ble_damp_on,
    output reg ble_pedal_delay,
    output reg [8:0] ble_drum_pulse,
    output reg [3:0] ble_drum_vel,
    output reg [5:0] ble_gtr_pluck,
    output reg [3:0] ble_gtr_fret,
    output reg [3:0] ble_gtr_vel,
    output reg ble_gtr_palm,
    output reg [1:0] ble_chord_sel,
    output reg ble_chord_sel_we,
    output reg ble_chord_trig,
    output reg [3:0] ble_chord_vel,
    output reg ble_chord_palm,
    output reg ble_chord_release,
    output reg [1:0] ble_bend,
    output reg ble_vib,
    output reg ble_glide,
    output reg [4:0] ble_slide_time,
    output reg ble_fx_set,
    output reg ble_fx_target,
    output reg ble_rev_set,
    output reg ble_rev_target,
    output reg ble_all_off
);
    localparam [7:0] EV_NOTE_ON = 8'h01;
    localparam [7:0] EV_NOTE_OFF = 8'h02;
    localparam [7:0] EV_DRUM = 8'h03;
    localparam [7:0] EV_GUITAR_OLD = 8'h04;
    localparam [7:0] EV_RELEASE_ALL = 8'h05;
    localparam [7:0] EV_ALL_OFF = 8'h06;
    localparam [7:0] EV_SESSION_START = 8'h07;
    localparam [7:0] EV_HEARTBEAT = 8'h08;
    localparam [7:0] EV_GTR_PLUCK = 8'h20;
    localparam [7:0] EV_GTR_FRET = 8'h21;
    localparam [7:0] EV_GTR_PALM = 8'h22;
    localparam [7:0] EV_CHORD_SELECT = 8'h23;
    localparam [7:0] EV_CHORD_TRIGGER = 8'h24;
    localparam [7:0] EV_CHORD_RELEASE = 8'h25;
    localparam [7:0] EV_BEND = 8'h26;
    localparam [7:0] EV_VIBRATO = 8'h27;
    localparam [7:0] EV_GLIDE = 8'h28;
    localparam [7:0] EV_SLIDE_TIME = 8'h29;
    localparam [7:0] EV_OVERDRIVE = 8'h2A;
    localparam [7:0] EV_REVERB = 8'h2B;
    localparam [7:0] EV_PIANO_OCT = 8'h30;
    localparam [7:0] EV_PIANO_DAMP = 8'h31;
    localparam [7:0] EV_PIANO_PEDAL_DELAY = 8'h32;
    localparam [7:0] EV_PIANO_PEDAL_RELEASE = 8'h33;
    localparam integer HEARTBEAT_TIMEOUT = 105000000;

    reg [26:0] hb_count;
    reg hb_seen;
    reg ev_pending;
    reg [15:0] pending_rel;
    integer i;
    wire [7:0] ev_code = ev_data[23:16];
    wire [7:0] key = ev_data[15:8];
    wire [7:0] value = ev_data[7:0];
    wire heartbeat_event = (!ev_empty) && (ev_code == EV_HEARTBEAT);
    wire session_event = (!ev_empty) && (ev_code == EV_SESSION_START);

    task release_all_ble;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                if ((ble_piano_held[i] || pending_rel[i]) &&
                    !(touch_keys[i] || usb_piano_held[i]))
                    ble_piano_rel[i] <= 1'b1;
                ble_piano_held[i] <= 1'b0;
            end
            pending_rel <= 16'd0;
            ble_chord_trig <= 1'b0;
            ble_chord_release <= 1'b1;
            ble_bend <= 2'd0;
            ble_vib <= 1'b0;
            ble_glide <= 1'b0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ev_re <= 1'b0;
            ble_piano_trig <= 0;
            ble_piano_rel <= 0;
            ble_piano_held <= 0;
            ble_piano_vel <= 0;
            ble_piano_oct <= 2'd1;
            ble_damp_on <= 1'b1;
            ble_pedal_delay <= 1'b0;
            ble_drum_pulse <= 0;
            ble_drum_vel <= 0;
            ble_gtr_pluck <= 0;
            ble_gtr_fret <= 0;
            ble_gtr_vel <= 15;
            ble_gtr_palm <= 1'b0;
            ble_chord_sel <= 2'd0;
            ble_chord_sel_we <= 1'b0;
            ble_chord_trig <= 1'b0;
            ble_chord_vel <= 15;
            ble_chord_palm <= 1'b0;
            ble_chord_release <= 1'b0;
            ble_bend <= 2'd0;
            ble_vib <= 1'b0;
            ble_glide <= 1'b0;
            ble_slide_time <= 5'd4;
            ble_fx_set <= 1'b0;
            ble_fx_target <= 1'b0;
            ble_rev_set <= 1'b0;
            ble_rev_target <= 1'b0;
            ble_all_off <= 1'b0;
            hb_count <= 0;
            hb_seen <= 1'b0;
            ev_pending <= 1'b0;
            pending_rel <= 0;
        end else begin
            ev_re <= 1'b0;
            ble_piano_trig <= 16'd0;
            ble_piano_rel <= 16'd0;
            ble_drum_pulse <= 9'd0;
            ble_gtr_pluck <= 6'd0;
            ble_chord_sel_we <= 1'b0;
            ble_chord_trig <= 1'b0;
            ble_chord_release <= 1'b0;
            ble_fx_set <= 1'b0;
            ble_rev_set <= 1'b0;
            ble_all_off <= 1'b0;
            ev_pending <= 1'b0;

            if (!ev_empty && !ev_pending) begin
                ev_re <= 1'b1;
                ev_pending <= 1'b1;
                case (ev_code)
                    EV_NOTE_ON: begin
                        if (key < 16) begin
                            pending_rel[key] <= 1'b0;
                            ble_piano_held[key] <= 1'b1;
                            ble_piano_vel[key*4 +: 4] <= (value == 0) ? 4'd1 : value[3:0];
                            ble_piano_trig[key] <= 1'b1;
                        end
                    end
                    EV_NOTE_OFF: begin
                        if (key < 16) begin
                            ble_piano_held[key] <= 1'b0;
                            if (ble_damp_on) begin
                                if (ble_pedal_delay)
                                    pending_rel[key] <= 1'b1;
                                else if (!(touch_keys[key] || usb_piano_held[key]))
                                    ble_piano_rel[key] <= 1'b1;
                            end
                        end
                    end
                    EV_DRUM: begin
                        if (key < 9) begin
                            ble_drum_pulse[key] <= 1'b1;
                            ble_drum_vel <= (value == 0) ? 4'd1 : value[3:0];
                        end
                    end
                    EV_GUITAR_OLD, EV_GTR_PLUCK: begin
                        if (key < 6) begin
                            ble_gtr_pluck[key] <= 1'b1;
                            ble_gtr_vel <= (value == 0) ? 4'd1 : value[3:0];
                        end
                    end
                    EV_GTR_FRET: begin
                        if (key <= 12) ble_gtr_fret <= key[3:0];
                    end
                    EV_GTR_PALM: begin
                        if (key < 2) ble_gtr_palm <= key[0];
                    end
                    EV_CHORD_SELECT: begin
                        if (key < 4) begin
                            ble_chord_sel <= key[1:0];
                            ble_chord_sel_we <= 1'b1;
                        end
                    end
                    EV_CHORD_TRIGGER: begin
                        ble_chord_trig <= 1'b1;
                        ble_chord_vel <= (value == 0) ? 4'd1 : value[3:0];
                        ble_chord_palm <= ble_gtr_palm;
                    end
                    EV_CHORD_RELEASE: begin
                        ble_chord_release <= 1'b1;
                    end
                    EV_BEND: begin
                        if (key < 3) ble_bend <= key[1:0];
                    end
                    EV_VIBRATO: begin
                        if (key < 2) ble_vib <= key[0];
                    end
                    EV_GLIDE: begin
                        if (key < 2) ble_glide <= key[0];
                    end
                    EV_SLIDE_TIME: begin
                        if (key >= 1 && key <= 15) ble_slide_time <= key[4:0];
                    end
                    EV_OVERDRIVE: begin
                        if (key < 2) begin
                            ble_fx_set <= 1'b1;
                            ble_fx_target <= key[0];
                        end
                    end
                    EV_REVERB: begin
                        if (key < 2) begin
                            ble_rev_set <= 1'b1;
                            ble_rev_target <= key[0];
                        end
                    end
                    EV_PIANO_OCT: begin
                        if (key < 3) ble_piano_oct <= key[1:0];
                    end
                    EV_PIANO_DAMP: begin
                        if (key < 2) ble_damp_on <= key[0];
                        if (key == 0) pending_rel <= 16'd0;
                    end
                    EV_PIANO_PEDAL_DELAY: begin
                        if (key < 2) begin
                            if (ble_pedal_delay && key == 0) begin
                                for (i = 0; i < 16; i = i + 1)
                                    if (pending_rel[i] && !(touch_keys[i] || usb_piano_held[i]))
                                        ble_piano_rel[i] <= 1'b1;
                                pending_rel <= 16'd0;
                            end
                            ble_pedal_delay <= key[0];
                        end
                    end
                    EV_PIANO_PEDAL_RELEASE: begin
                        for (i = 0; i < 16; i = i + 1)
                            if (pending_rel[i] && !(touch_keys[i] || usb_piano_held[i]))
                                ble_piano_rel[i] <= 1'b1;
                        pending_rel <= 16'd0;
                    end
                    EV_RELEASE_ALL: begin
                        release_all_ble;
                        ble_chord_sel <= 2'd0;
                        ble_chord_sel_we <= 1'b1;
                    end
                    EV_ALL_OFF: begin
                        ble_all_off <= 1'b1;
                        release_all_ble;
                    end
                    EV_SESSION_START: begin
                        release_all_ble;
                        ble_chord_sel <= 2'd0;
                        ble_chord_sel_we <= 1'b1;
                        ble_gtr_fret <= 4'd0;
                        ble_gtr_palm <= 1'b0;
                        ble_chord_palm <= 1'b0;
                        ble_piano_oct <= 2'd1;
                        ble_damp_on <= 1'b1;
                        ble_pedal_delay <= 1'b0;
                        ble_slide_time <= 5'd4;
                        hb_count <= 0;
                        hb_seen <= 1'b1;
                    end
                    EV_HEARTBEAT: begin
                        hb_count <= 0;
                        hb_seen <= 1'b1;
                    end
                    default:;
                endcase
            end

            // A heartbeat/session-start event has priority over the increment.
            if (!heartbeat_event && !session_event && hb_seen) begin
                if (hb_count >= HEARTBEAT_TIMEOUT - 1) begin
                    release_all_ble;
                    hb_count <= 0;
                    hb_seen <= 1'b0;
                end else begin
                    hb_count <= hb_count + 1'b1;
                end
            end
        end
    end
endmodule


