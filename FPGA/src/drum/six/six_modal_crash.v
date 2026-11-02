`timescale 1ns/1ps
module six_modal_crash(
    input clk, input rst_n, input sample_tick, input trig,
    input [3:0] vel, input cancel,
    output reg signed [15:0] pcm, output reg out_valid, output reg active,
    output reg [8:0] state_addr, output reg state_we,
    output reg [31:0] state_wdata, input [31:0] state_rdata,
    output reg [12:0] rom_addr, input [31:0] rom_data,
    output reg [9:0] sine_addr, input signed [15:0] sine_data
);
    localparam [5:0] S_IDLE=0, S_PRE0=1, S_PRE1=2, S_INIT0=3, S_INIT1=4,
        S_INIT2=5, S_INIT3=6, S_INIT4=7, S_INIT5=8, S_INIT6=9,
        S_SCAN=10, S_N0=11, S_N0A=12, S_N1=13, S_N2=14, S_N3=15,
        S_N4=16, S_N5=17, S_N6=18, S_N7=19, S_K0=20, S_K0A=21,
        S_K1=22, S_K2=23, S_K3=24, S_K4=25, S_K5=26, S_K6=27,
        S_K7=28, S_K8=29, S_KNEXT=30, S_OUT=31, S_WAIT=32, S_N8=33;

    reg [5:0] state;
    reg [5:0] m;
    reg [31:0] n;
    reg knot_now;
    reg [5:0] seg;
    reg [31:0] next_knot;
    reg [3:0] vel_lat;
    reg [6:0] gmode;

    reg [31:0] phase_r, a_r, b_r, da_r, db_r, inc_r;
    reg [31:0] phase_next, a_next, b_next;
    reg signed [15:0] cos_r, sin_r;
    reg signed [47:0] sum;
    reg [31:0] cur_coef, next_coef, recip;
    reg [12:0] coeff_addr;

    wire [8:0] gsaddr = ({2'b0,gmode} << 2) + {2'b0,gmode};
    wire signed [15:0] a_hi = $signed(a_r[31:16]);
    wire signed [15:0] b_hi = $signed(b_r[31:16]);
    wire signed [31:0] prod_a = a_hi * cos_r;
    wire signed [31:0] prod_b = b_hi * sin_r;
    wire signed [15:0] cur_a = $signed(cur_coef[15:0]);
    wire signed [15:0] cur_b = $signed(cur_coef[31:16]);
    wire signed [15:0] nxt_a = $signed(next_coef[15:0]);
    wire signed [15:0] nxt_b = $signed(next_coef[31:16]);
    wire signed [63:0] da_prod = $signed(nxt_a - cur_a) * $signed(recip);
    wire signed [31:0] da_calc = da_prod >>> 16;
    wire signed [63:0] db_prod = $signed(nxt_b - cur_b) * $signed(recip);
    wire signed [31:0] db_calc = db_prod >>> 16;
    wire signed [47:0] modal_sum = sum >>> 15;
    wire [31:0] inc_addr = 32'd8 + {26'd0,m};
    wire [31:0] phase_use = phase_r + inc_r;
    wire signed [15:0] rom_nxt_a = $signed(rom_data[15:0]);
    wire signed [15:0] rom_nxt_b = $signed(rom_data[31:16]);
    wire signed [63:0] da_rom_prod = $signed(rom_nxt_a - cur_a) * $signed(recip);
    wire signed [31:0] da_rom = da_rom_prod >>> 16;
    wire signed [63:0] db_rom_prod = $signed(rom_nxt_b - cur_b) * $signed(recip);
    wire signed [31:0] db_rom = db_rom_prod >>> 16;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; m<=0; n<=0; knot_now<=0; seg<=0; next_knot<=0;
            vel_lat<=0; gmode<=0; active<=0; out_valid<=0; pcm<=0;
            phase_r<=0; a_r<=0; b_r<=0; da_r<=0; db_r<=0; inc_r<=0;
            phase_next<=0; a_next<=0; b_next<=0; cos_r<=0; sin_r<=0;
            sum<=0; cur_coef<=0; next_coef<=0; recip<=0; coeff_addr<=0;
            state_addr<=0; state_we<=0; state_wdata<=0; rom_addr<=0; sine_addr<=0;
        end else begin
            out_valid<=0;
            state_we<=0;
            if (cancel) begin
                active<=0; pcm<=0; state<=S_IDLE;
            end else case (state)
            S_IDLE: if (sample_tick && trig) begin
                active<=1; pcm<=0; n<=0; m<=0; gmode<=0; seg<=0;
                knot_now<=0; vel_lat<=(vel>15)?4'd15:vel; state<=S_PRE0;
            end
            S_PRE0: begin
                rom_addr <= 13'd95;
                state <= S_PRE1;
            end
            S_PRE1: begin
                recip <= rom_data;
                rom_addr <= 13'd57;
                seg <= 6'd1;
                state <= S_INIT0;
            end
            S_INIT0: begin
                if (m==6'd0) next_knot <= rom_data;
                coeff_addr <= 13'd133 + m*13'd39;
                rom_addr <= 13'd133 + m*13'd39;
                state <= S_INIT1;
            end
            S_INIT1: begin
                cur_coef <= rom_data;
                rom_addr <= coeff_addr + 13'd1;
                state <= S_INIT2;
            end
            S_INIT2: begin
                next_coef <= rom_data;
                state_addr <= gsaddr;
                state_we <= 1'b1;
                state_wdata <= 32'd0;
                state <= S_INIT3;
            end
            S_INIT3: begin
                da_r <= da_calc; db_r <= db_calc;
                a_r <= {cur_a,16'd0}; b_r <= {cur_b,16'd0};
                state_addr <= gsaddr + 9'd1;
                state_we <= 1'b1;
                state_wdata <= {cur_a,16'd0};
                state <= S_INIT4;
            end
            S_INIT4: begin
                state_addr <= gsaddr + 9'd2;
                state_we <= 1'b1;
                state_wdata <= {cur_b,16'd0};
                state <= S_INIT5;
            end
            S_INIT5: begin
                state_addr <= gsaddr + 9'd3;
                state_we <= 1'b1;
                state_wdata <= da_calc;
                state <= S_INIT6;
            end
            S_INIT6: begin
                state_addr <= gsaddr + 9'd4;
                state_we <= 1'b1;
                state_wdata <= db_calc;
                if (m==6'd47) begin m<=0; gmode<=0; state<=S_SCAN; end
                else begin m<=m+1; gmode<=gmode+1; state<=S_INIT0; end
            end
            S_SCAN: begin
                if (n >= 32'd144939) begin
                    active<=0; pcm<=0; state<=S_WAIT;
                end else begin
                    knot_now <= (n != 0 && n == next_knot);
                    sum <= 0; m <= 0; gmode <= 0;
                    coeff_addr <= 13'd133 + {9'd0,seg};
                    rom_addr <= 13'd95 + {9'd0,seg};
                    state_addr <= gsaddr;
                    state <= (n != 0 && n == next_knot) ? S_K0 : S_N0;
                end
            end
            S_N0: begin
                state_addr <= gsaddr + 9'd1;
                rom_addr <= inc_addr[12:0];
                state <= S_N0A;
            end
            S_N0A: begin
                phase_r <= state_rdata;
                inc_r <= rom_data;
                state_addr <= gsaddr + 9'd2;
                state <= S_N1;
            end
            S_N1: begin
                a_r <= state_rdata;
                state_addr <= gsaddr + 9'd3;
                sine_addr <= phase_use[31:22] + 10'd256;
                state <= S_N2;
            end
            S_N2: begin
                b_r <= state_rdata;
                state_addr <= gsaddr + 9'd4;
                sine_addr <= phase_use[31:22];
                state <= S_N3;
            end
            S_N3: begin
                da_r <= state_rdata;
                cos_r <= sine_data;
                state <= S_N4;
            end
            S_N4: begin
                db_r <= state_rdata;
                sin_r <= sine_data;
                state <= S_N5;
            end
            S_N5: begin
                sum <= sum + prod_a + prod_b;
                state_addr <= gsaddr;
                state_we <= 1'b1;
                state_wdata <= phase_use;
                state <= S_N6;
            end
            S_N6: begin
                state_addr <= gsaddr + 9'd1;
                state_we <= 1'b1;
                state_wdata <= a_r + da_r;
                state <= S_N7;
            end
            S_N7: begin
                state_addr <= gsaddr + 9'd2;
                state_we <= 1'b1;
                state_wdata <= b_r + db_r;
                state <= S_N8;
            end
            S_N8: begin
                if (m==6'd47) begin m<=0; state<=S_OUT; end
                else begin
                    m<=m+1; gmode<=gmode+1;
                    state_addr <= gsaddr + 9'd5;
                    state<=S_N0;
                end
            end
            S_K0: begin
                if (m==6'd0) recip <= rom_data;
                rom_addr <= inc_addr[12:0];
                state_addr <= gsaddr;
                state <= S_K0A;
            end
            S_K0A: begin
                phase_r <= state_rdata;
                inc_r <= rom_data;
                rom_addr <= coeff_addr;
                state <= S_K1;
            end
            S_K1: begin
                cur_coef <= rom_data;
                rom_addr <= coeff_addr + 13'd1;
                sine_addr <= phase_use[31:22] + 10'd256;
                state <= S_K2;
            end
            S_K2: begin
                a_r <= {cur_a,16'd0}; b_r <= {cur_b,16'd0};
                da_r <= da_rom; db_r <= db_rom;
                sine_addr <= phase_use[31:22];
                state_addr <= gsaddr;
                state_we <= 1'b1;
                state_wdata <= phase_use;
                state <= S_K3;
            end
            S_K3: begin
                cos_r <= sine_data;
                state_addr <= gsaddr + 9'd1;
                state_we <= 1'b1;
                state_wdata <= {cur_a,16'd0} + da_rom;
                state <= S_K4;
            end
            S_K4: begin
                sin_r <= sine_data;
                state_addr <= gsaddr + 9'd2;
                state_we <= 1'b1;
                state_wdata <= {cur_b,16'd0} + db_rom;
                state <= S_K5;
            end
            S_K5: begin
                sum <= sum + prod_a + prod_b;
                state_addr <= gsaddr + 9'd3;
                state_we <= 1'b1;
                state_wdata <= da_rom;
                state <= S_K6;
            end
            S_K6: begin
                state_addr <= gsaddr + 9'd4;
                state_we <= 1'b1;
                state_wdata <= db_rom;
                state <= S_K7;
            end
            S_K7: begin
                state <= S_K8;
            end
            S_K8: begin
                if (m==6'd47) begin
                    m<=0;
                    if (seg < 6'd38) begin
                        seg <= seg + 6'd1;
                        rom_addr <= 13'd57 + {9'd0,seg};
                        state <= S_KNEXT;
                    end else begin
                        next_knot <= 32'hffffffff;
                        state <= S_OUT;
                    end
                end else begin
                    m<=m+1; gmode<=gmode+1;
                    coeff_addr <= coeff_addr + 13'd39;
                    state_addr <= gsaddr + 9'd5;
                    state<=S_K0;
                end
            end
            S_KNEXT: begin
                next_knot <= rom_data;
                state <= S_OUT;
            end
            S_OUT: begin
                pcm <= (modal_sum > 32767) ? 16'sh7fff :
                       (modal_sum < -32768) ? 16'sh8000 : modal_sum[15:0];
                out_valid <= 1'b1;
                n <= n+1;
                if (n+1 >= 32'd144939) active<=0;
                state <= S_WAIT;
            end
            S_WAIT: begin
                if (sample_tick) begin
                    if (!active) state<=S_IDLE;
                    else begin sum<=0; m<=0; gmode<=0; state<=S_SCAN; end
                end
            end
            default: state<=S_IDLE;
            endcase
        end
    end
endmodule
