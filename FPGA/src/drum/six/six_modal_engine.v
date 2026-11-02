`timescale 1ns/1ps
module six_modal_engine(
    input clk, input rst_n, input sample_tick,
    input [2:0] trig, input [3:0] vel, input cancel, input ce,
    output reg signed [15:0] pcm_cr, pcm_ho, pcm_ri,
    output reg [2:0] out_valid, output reg [2:0] active,
    output reg [8:0] state_addr, output reg state_we,
    output reg [31:0] state_wdata, input [31:0] state_rdata,
    output reg rom_req,
    output reg [12:0] rom_addr, input [31:0] rom_data, input rom_valid,
    output reg [9:0] sine_addr, input signed [15:0] sine_data
);
    // Per-mode phase increments are constant. Keep them in a small local ROM
    // so the shared parameter ROM is only used for segment loads and knots.
    reg [6:0] inc_raddr;
    wire [31:0] inc_rdata;
    six_inc_rom uinc(.clk(clk), .addr(inc_raddr), .data(inc_rdata));

    localparam [5:0] S_IDLE=0, S_PRE0=1, S_PRE1=2, S_INIT0=3, S_INIT1=4,
        S_INIT2=5, S_INIT3=6, S_INIT4=7, S_INIT5=8, S_INIT6=9,
        S_SCAN=10, S_N0=11, S_N0A=12, S_N1=13, S_N2=14, S_N3=15,
        S_N4=16, S_N5=17, S_N6=18, S_N7=19, S_N8=20, S_K0=21,
        S_K0A=22, S_K1=23, S_K2=24, S_K3=25, S_K4=26, S_K5=27,
        S_K6=28, S_K7=29, S_K8=30, S_KNEXT=31, S_OUT=32, S_WAIT=33;

    reg [5:0] state;
    reg [1:0] snd;
    reg [5:0] m;
    reg [2:0] pend;
    reg [31:0] n [0:2];
    reg [5:0] seg [0:2];
    reg [31:0] nextk [0:2];
    reg signed [47:0] sum;
    reg [3:0] vel_lat;
    reg [31:0] phase_r,a_r,b_r,da_r,db_r,inc_r;
    reg signed [15:0] cos_r,sin_r;
    reg [31:0] cur_coef,next_coef,recip;
    reg [12:0] coeff_addr;
    reg knot_now;

    wire rom_stall = ((state==S_PRE1)||(state==S_INIT0)||(state==S_INIT1)||
                      (state==S_INIT2)||((state==S_K0)&&(m==6'd0))||
                      (state==S_K1)||(state==S_K2)||(state==S_KNEXT)) && !rom_valid;

    wire [5:0] C = (snd==0)?6'd48:(snd==1)?6'd20:6'd28;
    wire [5:0] K = (snd==0)?6'd39:(snd==1)?6'd18:6'd23;
    wire [12:0] BASE = (snd==0)?13'd0:(snd==1)?13'd2006:13'd3340;
    wire [12:0] CO = (snd==0)?13'd133:(snd==1)?13'd63:13'd81;
    wire [12:0] IO = 13'd8;
    wire [12:0] KO = (snd==0)?13'd56:(snd==1)?13'd28:13'd36;
    wire [12:0] RO = (snd==0)?13'd95:(snd==1)?13'd46:13'd59;
    wire [6:0] GB = (snd==0)?7'd0:(snd==1)?7'd48:7'd68;
    wire [31:0] NN = (snd==0)?32'd144939:(snd==1)?32'd28923:32'd144805;
    wire [6:0] gm = GB + m;
    wire [8:0] gsaddr = ({2'b0,gm} << 2) + {2'b0,gm};
    wire [5:0] lastm = C - 6'd1;
    wire [31:0] inc_addr = {19'd0,BASE} + {19'd0,IO} + {26'd0,m};
    wire [31:0] phase_use = phase_r + inc_r;
    wire signed [15:0] a_hi = $signed(a_r[31:16]);
    wire signed [15:0] b_hi = $signed(b_r[31:16]);
    wire signed [31:0] prod_a = a_hi * cos_r;
    wire signed [31:0] prod_b = b_hi * sin_r;
    wire signed [15:0] cur_a = $signed(cur_coef[15:0]);
    wire signed [15:0] cur_b = $signed(cur_coef[31:16]);
    wire signed [15:0] nxt_a = $signed(next_coef[15:0]);
    wire signed [15:0] nxt_b = $signed(next_coef[31:16]);
    wire signed [63:0] da_prod = $signed(nxt_a-cur_a) * $signed(recip);
    wire signed [63:0] db_prod = $signed(nxt_b-cur_b) * $signed(recip);
    wire signed [31:0] da_calc = da_prod >>> 16;
    wire signed [31:0] db_calc = db_prod >>> 16;
    wire signed [63:0] da_rom_prod = $signed(nxt_a-cur_a) * $signed(recip);
    wire signed [63:0] db_rom_prod = $signed(nxt_b-cur_b) * $signed(recip);
    wire signed [31:0] da_rom = da_rom_prod >>> 16;
    wire signed [31:0] db_rom = db_rom_prod >>> 16;
    wire signed [47:0] modal_sum = sum >>> 15;
    wire [31:0] cyc_n = n[snd];
    wire [5:0] cyc_seg = seg[snd];
    wire signed [31:0] vel_gain32 = 32'sd1 + $signed({28'd0,vel_lat});
    wire signed [15:0] modal_s16 = (modal_sum > 32767) ? 16'sh7fff : (modal_sum < -32768) ? 16'sh8000 : modal_sum[15:0];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=S_IDLE; snd<=0; m<=0; pend<=0; sum<=0; vel_lat<=0;
            phase_r<=0; a_r<=0; b_r<=0; da_r<=0; db_r<=0; inc_r<=0;
            cos_r<=0; sin_r<=0; cur_coef<=0; next_coef<=0; recip<=0;
            coeff_addr<=0; knot_now<=0; state_addr<=0; state_we<=0;
            state_wdata<=0; rom_addr<=0; sine_addr<=0; active<=0; out_valid<=0;
            pcm_cr<=0; pcm_ho<=0; pcm_ri<=0; inc_raddr<=0;
            for(i=0;i<3;i=i+1) begin n[i]<=0; seg[i]<=0; nextk[i]<=0; end
        end else begin
            out_valid<=0; state_we<=0; rom_req<=0;
            if(sample_tick) begin
                if(trig[0]) begin pend[0]<=1; n[0]<=0; end
                if(trig[1]) begin pend[1]<=1; n[1]<=0; end
                if(trig[2]) begin pend[2]<=1; n[2]<=0; end
            end
            if(cancel) begin
                active<=0; pend<=0; pcm_cr<=0; pcm_ho<=0; pcm_ri<=0; state<=S_IDLE;
            end else if(rom_stall) begin
                rom_req<=1;
            end else if(ce || state==S_IDLE || state==S_WAIT) case(state)
            S_IDLE: if(sample_tick) begin
                if(trig[0]) begin pend[0]<=1; n[0]<=0; end
                if(trig[1]) begin pend[1]<=1; n[1]<=0; end
                if(trig[2]) begin pend[2]<=1; n[2]<=0; end
                vel_lat<=(vel>15)?4'd15:vel;
                if(|trig) begin snd<=0; m<=0; state<=S_PRE0; end
            end
            S_PRE0: begin
                if(pend[snd]) begin
                rom_req<=1;
                    rom_addr<=BASE+RO; state<=S_PRE1;
                end else begin
                    if(snd==2) begin snd<=0; state<=S_SCAN; end
                    else begin snd<=snd+1; state<=S_PRE0; end
                end
            end
            S_PRE1: begin
                recip<=rom_data;
                rom_req<=1;
                rom_addr<=BASE+KO+13'd1;
                state<=S_INIT0;
            end
            S_INIT0: begin
                if(m==0) nextk[snd]<=rom_data;
                coeff_addr<=BASE+CO+m*K;
                rom_req<=1;
                rom_addr<=BASE+CO+m*K;
                state<=S_INIT1;
            end
            S_INIT1: begin
                cur_coef<=rom_data;
                rom_req<=1;
                rom_addr<=coeff_addr+13'd1;
                state<=S_INIT2;
            end
            S_INIT2: begin
                next_coef<=rom_data;
                state_addr<=gsaddr; state_we<=1; state_wdata<=0;
                state<=S_INIT3;
            end
            S_INIT3: begin
                da_r<=da_calc; db_r<=db_calc;
                state_addr<=gsaddr+9'd1; state_we<=1; state_wdata<={cur_a,16'd0};
                state<=S_INIT4;
            end
            S_INIT4: begin
                state_addr<=gsaddr+9'd2; state_we<=1; state_wdata<={cur_b,16'd0};
                state<=S_INIT5;
            end
            S_INIT5: begin
                state_addr<=gsaddr+9'd3; state_we<=1; state_wdata<=da_calc;
                state<=S_INIT6;
            end
            S_INIT6: begin
                state_addr<=gsaddr+9'd4; state_we<=1; state_wdata<=db_calc;
                if(m==lastm) begin
                    m<=0; active[snd]<=1; seg[snd]<=6'd1; pend[snd]<=0;
                    if(snd==2) begin snd<=0; state<=S_SCAN; end
                    else begin snd<=snd+1; state<=S_PRE0; end
                end else begin m<=m+1; state<=S_INIT0; end
            end
            S_SCAN: begin
                if(snd==3) state<=S_WAIT;
                else if(!active[snd] || n[snd]>=NN) begin
                    if(snd==2) state<=S_WAIT; else begin snd<=snd+1; state<=S_SCAN; end
                end else begin
                    sum<=0; m<=0; knot_now<=(n[snd]!=0 && n[snd]==nextk[snd] && cyc_seg < K-6'd1);
                    coeff_addr<=BASE+CO+cyc_seg;
                    rom_addr<=BASE+RO+cyc_seg;
                    inc_raddr<=GB;
                    if(n[snd]!=0 && n[snd]==nextk[snd] && cyc_seg < K-6'd1) rom_req<=1;
                    state_addr<=gsaddr;
                    state<=(n[snd]!=0 && n[snd]==nextk[snd] && cyc_seg < K-6'd1)?S_K0:S_N0;
                end
            end
            S_N0: begin
                state_addr<=gsaddr+9'd1;
                state<=S_N0A;
            end
            S_N0A: begin
                phase_r<=state_rdata; inc_r<=inc_rdata;
                state_addr<=gsaddr+9'd2;
                state<=S_N1;
            end
            S_N1: begin
                a_r<=state_rdata;
                state_addr<=gsaddr+9'd3;
                sine_addr<=phase_use[31:22]+10'd256;
                state<=S_N2;
            end
            S_N2: begin
                b_r<=state_rdata;
                state_addr<=gsaddr+9'd4;
                sine_addr<=phase_use[31:22];
                state<=S_N3;
            end
            S_N3: begin
                da_r<=state_rdata; cos_r<=sine_data;
                state<=S_N4;
            end
            S_N4: begin
                db_r<=state_rdata; sin_r<=sine_data;
                state<=S_N5;
            end
            S_N5: begin
                sum<=sum+prod_a+prod_b;
                state_addr<=gsaddr; state_we<=1; state_wdata<=phase_use;
                state<=S_N6;
            end
            S_N6: begin
                state_addr<=gsaddr+9'd1; state_we<=1; state_wdata<=a_r+da_r;
                state<=S_N7;
            end
            S_N7: begin
                state_addr<=gsaddr+9'd2; state_we<=1; state_wdata<=b_r+db_r;
                state<=S_N8;
            end
            S_N8: begin
                if(m==lastm) begin
                    m<=0;
                    if(knot_now) begin
                        if(cyc_seg < K-6'd2) begin
                            seg[snd]<=cyc_seg+6'd1;
                            rom_addr<=BASE+KO+cyc_seg+13'd1; rom_req<=1;
                            state<=S_KNEXT;
                        end else begin
                            nextk[snd]<=32'hffffffff; state<=S_OUT;
                        end
                    end else state<=S_OUT;
                end else begin
                    m<=m+1;
                    inc_raddr<=gm+7'd1;
                    state_addr<=gsaddr+9'd5;
                    state<=S_N0;
                end
            end
            S_K0: begin
                if(m==0) recip<=rom_data;
                state_addr<=gsaddr;
                state<=S_K0A;
            end
            S_K0A: begin
                phase_r<=state_rdata; inc_r<=inc_rdata;
                rom_req<=1;
                rom_addr<=coeff_addr;
                state<=S_K1;
            end
            S_K1: begin
                cur_coef<=rom_data;
                rom_req<=1;
                rom_addr<=coeff_addr+13'd1;
                sine_addr<=phase_use[31:22]+10'd256;
                state<=S_K2;
            end
            S_K2: begin
                next_coef<=rom_data;
                sine_addr<=phase_use[31:22];
                state<=S_K3;
            end
            S_K3: begin
                a_r<={cur_a,16'd0}; b_r<={cur_b,16'd0};
                da_r<=da_rom; db_r<=db_rom;
                cos_r<=sine_data;
                state_addr<=gsaddr; state_we<=1; state_wdata<=phase_use;
                state<=S_K4;
            end
            S_K4: begin
                sin_r<=sine_data;
                state_addr<=gsaddr+9'd1; state_we<=1; state_wdata<={cur_a,16'd0}+da_rom;
                state<=S_K5;
            end
            S_K5: begin
                sum<=sum+prod_a+prod_b;
                state_addr<=gsaddr+9'd2; state_we<=1; state_wdata<={cur_b,16'd0}+db_rom;
                state<=S_K6;
            end
            S_K6: begin
                state_addr<=gsaddr+9'd3; state_we<=1; state_wdata<=da_rom;
                state<=S_K7;
            end
            S_K7: begin
                state_addr<=gsaddr+9'd4; state_we<=1; state_wdata<=db_rom;
                state<=S_K8;
            end
            S_K8: begin
                if(m==lastm) begin
                    m<=0;
                    if(cyc_seg < K-6'd2) begin
                        seg[snd]<=cyc_seg+6'd1;
                        rom_addr<=BASE+KO+cyc_seg+13'd1; rom_req<=1;
                        state<=S_KNEXT;
                    end else begin
                        nextk[snd]<=32'hffffffff; state<=S_OUT;
                    end
                end else begin
                    m<=m+1;
                    inc_raddr<=gm+7'd1;
                    coeff_addr<=coeff_addr+K;
                    state_addr<=gsaddr+9'd5;
                    state<=S_K0;
                end
            end
            S_KNEXT: begin
                nextk[snd]<=rom_data; state<=S_OUT;
            end
            S_OUT: begin
                case(snd)
                0: pcm_cr <= modal_s16;
                1: pcm_ho <= modal_s16;
                default: pcm_ri <= modal_s16;
                endcase
                out_valid[snd]<=1;
                n[snd]<=n[snd]+1;
                if(n[snd]+1>=NN) active[snd]<=0;
                if(snd==2) state<=S_WAIT;
                else begin snd<=snd+1; state<=S_SCAN; end
            end
            S_WAIT: if(sample_tick) begin
                if(|pend || |trig) begin snd<=0; m<=0; state<=S_PRE0; end
                else if(|active) begin snd<=0; state<=S_SCAN; end
                else state<=S_IDLE;
            end
            default: state<=S_IDLE;
            endcase
        end
    end
endmodule
