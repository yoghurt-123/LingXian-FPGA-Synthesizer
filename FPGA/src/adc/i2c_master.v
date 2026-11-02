// 100 kHz open-drain I2C master for a 50 MHz input clock.
// Only START/RESTART/WRITE/READ_ACK/READ_NACK/STOP/RECOVER operations are
// issued by the controller. SCL/SDA are driven low or released high-Z.
module i2c_master #(
    parameter integer HALF_CLKS = 250,
    parameter SIM_PUSH_PULL = 0
)(
    input clk,
    input rst_n,
    input start,
    input [2:0] op,
    input [7:0] din,
    output reg [7:0] dout,
    output reg ack,
    output reg done,
    output reg busy,
    inout scl,
    inout sda
);
    localparam [2:0] OP_START      = 3'd0;
    localparam [2:0] OP_RESTART    = 3'd1;
    localparam [2:0] OP_WRITE      = 3'd2;
    localparam [2:0] OP_READ_ACK   = 3'd3;
    localparam [2:0] OP_READ_NACK  = 3'd4;
    localparam [2:0] OP_STOP       = 3'd5;
    localparam [2:0] OP_RECOVER    = 3'd6;

    localparam [3:0] S_IDLE = 4'd0, S_START = 4'd1, S_RESTART = 4'd2,
                     S_WRITE = 4'd3, S_READ = 4'd4, S_STOP = 4'd5,
                     S_RECOVER = 4'd6;

    reg scl_low, sda_low;
    assign scl = SIM_PUSH_PULL ? ~scl_low : (scl_low ? 1'b0 : 1'bz);
    assign sda = sda_low ? 1'b0 : 1'bz;

    reg [1:0] sda_sync;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) sda_sync <= 2'b11;
        else sda_sync <= {sda_sync[0], sda};

    reg [8:0] half_cnt;
    wire half_tick = (half_cnt == HALF_CLKS - 1);

    reg [3:0] state;
    reg [2:0] op_r;
    reg [7:0] data_r, shift_r;
    reg [3:0] phase;
    reg [2:0] bit_idx;
    reg [3:0] recover_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_low <= 1'b0;
            sda_low <= 1'b0;
            dout <= 8'd0;
            ack <= 1'b0;
            done <= 1'b0;
            busy <= 1'b0;
            state <= S_IDLE;
            op_r <= 3'd0;
            data_r <= 8'd0;
            shift_r <= 8'd0;
            phase <= 4'd0;
            bit_idx <= 3'd0;
            recover_cnt <= 4'd9;
            half_cnt <= 9'd0;
        end else begin
            if (half_tick) half_cnt <= 9'd0;
            else half_cnt <= half_cnt + 1'b1;

            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    ack <= 1'b0;
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        done <= 1'b0;
                        ack <= 1'b0;
                        op_r <= op;
                        data_r <= din;
                        shift_r <= 8'd0;
                        phase <= 4'd0;
                        bit_idx <= 3'd0;
                        half_cnt <= 9'd0;
                        case (op)
                            OP_START: begin
                                scl_low <= 1'b0;
                                sda_low <= 1'b0;
                                state <= S_START;
                            end
                            OP_RESTART: begin
                                scl_low <= 1'b0;
                                sda_low <= 1'b0;
                                state <= S_RESTART;
                            end
                            OP_WRITE: begin
                                scl_low <= 1'b1;
                                sda_low <= ~din[7];
                                state <= S_WRITE;
                            end
                            OP_READ_ACK, OP_READ_NACK: begin
                                scl_low <= 1'b1;
                                sda_low <= 1'b0;
                                state <= S_READ;
                            end
                            OP_STOP: begin
                                scl_low <= 1'b1;
                                sda_low <= 1'b1;
                                state <= S_STOP;
                            end
                            OP_RECOVER: begin
                                scl_low <= 1'b1;
                                sda_low <= 1'b0;
                                recover_cnt <= 4'd9;
                                state <= S_RECOVER;
                            end
                            default: begin
                                state <= S_IDLE;
                                busy <= 1'b0;
                                done <= 1'b1;
                            end
                        endcase
                    end
                end

                S_START: begin
                    if (half_tick) begin
                        case (phase)
                            4'd0: begin sda_low <= 1'b1; phase <= 4'd1; end
                            4'd1: begin scl_low <= 1'b1; phase <= 4'd2; end
                            default: begin
                                state <= S_IDLE; busy <= 1'b0; done <= 1'b1;
                            end
                        endcase
                    end
                end

                S_RESTART: begin
                    if (half_tick) begin
                        case (phase)
                            4'd0: begin sda_low <= 1'b1; phase <= 4'd1; end
                            4'd1: begin scl_low <= 1'b1; phase <= 4'd2; end
                            default: begin
                                state <= S_IDLE; busy <= 1'b0; done <= 1'b1;
                            end
                        endcase
                    end
                end

                S_WRITE: begin
                    if (half_tick) begin
                        case (phase)
                            4'd0: begin
                                scl_low <= 1'b0; // release SCL high
                                phase <= 4'd1;
                            end
                            4'd1: begin
                                scl_low <= 1'b1; // SCL low
                                if (bit_idx == 3'd7) begin
                                    sda_low <= 1'b0; // release for ACK
                                    phase <= 4'd2;
                                end else begin
                                    bit_idx <= bit_idx + 1'b1;
                                    sda_low <= ~data_r[6];
                                    data_r <= {data_r[6:0], 1'b0};
                                    phase <= 4'd0;
                                end
                            end
                            4'd2: begin
                                scl_low <= 1'b0; // ACK bit high
                                phase <= 4'd3;
                            end
                            4'd3: begin
                                ack <= ~sda_sync[1];
                                scl_low <= 1'b1;
                                phase <= 4'd4;
                            end
                            default: begin
                                state <= S_IDLE; busy <= 1'b0; done <= 1'b1;
                            end
                        endcase
                    end
                end

                S_READ: begin
                    if (half_tick) begin
                        case (phase)
                            4'd0: begin
                                sda_low <= 1'b0;
                                scl_low <= 1'b0; // SCL high
                                phase <= 4'd1;
                            end
                            4'd1: begin
                                shift_r <= {shift_r[6:0], sda_sync[1]};
                                scl_low <= 1'b1; // SCL low
                                if (bit_idx == 3'd7) phase <= 4'd2;
                                else begin
                                    bit_idx <= bit_idx + 1'b1;
                                    phase <= 4'd3;
                                end
                            end
                            4'd2: begin
                                // Master ACK (low) for READ_ACK, NACK (release) for READ_NACK.
                                sda_low <= (op_r == OP_READ_ACK);
                                phase <= 4'd4;
                            end
                            4'd3: begin
                                scl_low <= 1'b0; // low half before next data bit
                                phase <= 4'd0;
                            end
                            4'd4: begin
                                scl_low <= 1'b0; // ACK bit high
                                phase <= 4'd5;
                            end
                            4'd5: begin
                                scl_low <= 1'b1; // ACK low
                                sda_low <= 1'b0;
                                phase <= 4'd6;
                            end
                            default: begin
                                dout <= shift_r;
                                state <= S_IDLE; busy <= 1'b0; done <= 1'b1;
                            end
                        endcase
                    end
                end

                S_STOP: begin
                    if (half_tick) begin
                        case (phase)
                            4'd0: begin scl_low <= 1'b1; sda_low <= 1'b1; phase <= 4'd1; end
                            4'd1: begin scl_low <= 1'b0; phase <= 4'd2; end
                            4'd2: begin sda_low <= 1'b0; phase <= 4'd3; end
                            default: begin state <= S_IDLE; busy <= 1'b0; done <= 1'b1; end
                        endcase
                    end
                end

                S_RECOVER: begin
                    if (half_tick) begin
                        case (phase)
                            4'd0: begin scl_low <= 1'b0; phase <= 4'd1; end
                            4'd1: begin scl_low <= 1'b1; phase <= 4'd2; end
                            4'd2: begin
                                if (recover_cnt == 4'd1) begin
                                    recover_cnt <= 4'd0;
                                    scl_low <= 1'b1;
                                    sda_low <= 1'b1;
                                    phase <= 4'd3;
                                end else begin
                                    recover_cnt <= recover_cnt - 4'd1;
                                    sda_low <= 1'b0;
                                    phase <= 4'd0;
                                end
                            end
                            default: begin
                                scl_low <= 1'b0;
                                sda_low <= 1'b0;
                                state <= S_IDLE; busy <= 1'b0; done <= 1'b1;
                            end
                        endcase
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule



