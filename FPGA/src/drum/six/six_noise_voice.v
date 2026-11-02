`timescale 1ns/1ps
module six_noise_voice #(
    parameter integer NB = 4,
    parameter integer K  = 18,
    parameter integer N  = 28923,
    parameter [12:0] APP = 2429,
    parameter [12:0] RO  = 46,
    parameter [12:0] KO  = 28,
    parameter [31:0] SEED = 32'h13589de2
)(
    input clk, input rst_n, input sample_tick, input trig, input cancel,
    output reg signed [15:0] pcm, output reg out_valid, output reg active,
    output reg [12:0] rom_addr, input [31:0] rom_data
);
    localparam [4:0] S_IDLE=0, S_LD_RECIP_REQ=1, S_LD_RECIP_WAIT=2,
        S_LD_CUR_REQ=3, S_LD_CUR_WAIT=4, S_LD_NXT_REQ=5, S_LD_NXT_WAIT=6,
        S_LD_CALC=7, S_LD_KNOT_REQ=8, S_LD_KNOT_WAIT=9, S_RUN=10,
        S_COMP=11, S_WAIT=12;
    reg [4:0] state;
    reg [31:0] n;
    reg [5:0] seg, load_seg;
    reg [31:0] nextk;
    reg [31:0] seed;
    reg [31:0] recip;
    reg [3:0] j;
    reg [15:0] gcur0,gcur1,gcur2,gcur3;
    reg [15:0] gnxt0,gnxt1,gnxt2,gnxt3;
    reg [31:0] env0,env1,env2,env3;
    reg [31:0] del0,del1,del2,del3;
    reg signed [47:0] lp0,lp1,lp2;
    reg signed [15:0] white;
    reg signed [31:0] b0,b1,b2,b3;
    reg signed [31:0] nsum;
    reg [31:0] xors;
    reg [31:0] curw, nxtw;
    reg [15:0] curg, nxtg;
    reg init_phase;
    wire [15:0] idx = load_seg + j*K;
    wire [12:0] gword = APP + (idx >> 1);
    wire [15:0] nidx = (load_seg==K-1) ? idx : idx + 16'd1;
    wire [15:0] gval = idx[0] ? curw[31:16] : curw[15:0];
    wire [15:0] gnval = nidx[0] ? rom_data[31:16] : rom_data[15:0];
    wire signed [63:0] dlt0 = ($signed(gnxt0)-$signed(gcur0))*$signed(recip);
    wire signed [63:0] dlt1 = ($signed(gnxt1)-$signed(gcur1))*$signed(recip);
    wire signed [63:0] dlt2 = ($signed(gnxt2)-$signed(gcur2))*$signed(recip);
    wire signed [63:0] dlt3 = ($signed(gnxt3)-$signed(gcur3))*$signed(recip);
    wire [31:0] x1 = xors ^ (xors << 13);
    wire [31:0] x2 = x1 ^ (x1 >> 17);
    wire [31:0] x3 = x2 ^ (x2 << 5);
    wire signed [15:0] wn = x3[31:16] - 16'd32768;
    wire signed [47:0] z = $signed(wn) * 65536;
    wire signed [63:0] lp0p = (z - lp0) * 4925;
    wire signed [63:0] lp1p = (z - lp1) * 18209;
    wire signed [63:0] lp2p = (z - lp2) * 42411;
    wire signed [47:0] lp0n = lp0 + (lp0p >>> 16);
    wire signed [47:0] lp1n = lp1 + (lp1p >>> 16);
    wire signed [47:0] lp2n = lp2 + (lp2p >>> 16);
    wire signed [31:0] a0 = (NB==4) ? (lp0n >>> 16) : (lp1n >>> 16);
    wire signed [31:0] a1 = (NB==4) ? ((lp1n >>> 16) - (lp0n >>> 16)) : (wn - (lp1n >>> 16));
    wire signed [31:0] a2 = (lp2n >>> 16) - (lp1n >>> 16);
    wire signed [31:0] a3 = wn - (lp2n >>> 16);
    wire signed [63:0] t0 = a0 * $signed(env0[31:16]);
    wire signed [63:0] t1 = a1 * $signed(env1[31:16]);
    wire signed [63:0] t2 = a2 * $signed(env2[31:16]);
    wire signed [63:0] t3 = a3 * $signed(env3[31:16]);
    wire signed [31:0] term0 = (NB==4) ? (t0 >>> 15) : 0;
    wire signed [31:0] term1 = (NB==4) ? (t1 >>> 15) : (t0 >>> 15);
    wire signed [31:0] term2 = (NB==4) ? (t2 >>> 15) : (t1 >>> 15);
    wire signed [31:0] term3 = (NB==4) ? (t3 >>> 15) : 0;
    wire signed [31:0] sum4 = (NB==4) ? (term0+term1+term2+term3) : (term1+term2);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=S_IDLE; n<=0; seg<=0; load_seg<=0; nextk<=0; seed<=0;
            recip<=0; j<=0; active<=0; out_valid<=0; pcm<=0;
            gcur0<=0;gcur1<=0;gcur2<=0;gcur3<=0;
            gnxt0<=0;gnxt1<=0;gnxt2<=0;gnxt3<=0;
            env0<=0;env1<=0;env2<=0;env3<=0;
            del0<=0;del1<=0;del2<=0;del3<=0;
            lp0<=0;lp1<=0;lp2<=0; white<=0; b0<=0;b1<=0;b2<=0;b3<=0;
            nsum<=0; xors<=0; curw<=0; nxtw<=0; curg<=0; nxtg<=0;
            init_phase<=0; rom_addr<=0;
        end else begin
            out_valid<=0;
            if(cancel) begin
                active<=0; pcm<=0; state<=S_IDLE;
            end else case(state)
            S_IDLE: if(sample_tick && trig) begin
                active<=1; pcm<=0; n<=0; seg<=0; load_seg<=0; j<=0;
                seed<=SEED; xors<=SEED; lp0<=0; lp1<=0; lp2<=0;
                init_phase<=1; state<=S_LD_RECIP_REQ;
            end
            S_LD_RECIP_REQ: begin
                rom_addr<=RO+load_seg; state<=S_LD_RECIP_WAIT;
            end
            S_LD_RECIP_WAIT: begin
                recip<=rom_data; state<=S_LD_CUR_REQ;
            end
            S_LD_CUR_REQ: begin
                rom_addr<=gword; state<=S_LD_CUR_WAIT;
            end
            S_LD_CUR_WAIT: begin
                curw<=rom_data; state<=S_LD_NXT_REQ;
            end
            S_LD_NXT_REQ: begin
                rom_addr<=APP + (nidx>>1); state<=S_LD_NXT_WAIT;
            end
            S_LD_NXT_WAIT: begin
                nxtw<=rom_data;
                case(j)
                0: begin gcur0<=gval; gnxt0<=gnval; end
                1: begin gcur1<=gval; gnxt1<=gnval; end
                2: begin gcur2<=gval; gnxt2<=gnval; end
                default: begin gcur3<=gval; gnxt3<=gnval; end
                endcase
                if(j+1>=NB) begin j<=0; state<=S_LD_CALC; end
                else begin j<=j+1; state<=S_LD_CUR_REQ; end
            end
            S_LD_CALC: begin
                env0<={gcur0,16'd0}; env1<={gcur1,16'd0};
                env2<={gcur2,16'd0}; env3<={gcur3,16'd0};
                del0<=dlt0>>>16;
                del1<=dlt1>>>16;
                del2<=dlt2>>>16;
                del3<=dlt3>>>16;
                if(init_phase) begin
                    rom_addr<=KO+13'd1; state<=S_LD_KNOT_WAIT;
                end else begin
                    if(load_seg < K-2) rom_addr<=KO+load_seg+13'd1;
                    else rom_addr<=KO+load_seg;
                    state<=S_LD_KNOT_WAIT;
                end
            end
            S_LD_KNOT_WAIT: begin
                if(init_phase) begin
                    nextk<=rom_data; seg<=6'd1; init_phase<=0; state<=S_COMP;
                end else if(load_seg < K-2) begin
                    nextk<=rom_data; seg<=load_seg+6'd1; state<=S_COMP;
                end else begin
                    nextk<=32'hffffffff; seg<=load_seg; state<=S_COMP;
                end
            end
            S_RUN: if(sample_tick) begin
                if(!active || n>=N) begin active<=0; state<=S_IDLE; end
                else if(n!=0 && n==nextk) begin
                    load_seg<=seg; state<=S_LD_RECIP_REQ;
                end else state<=S_COMP;
            end
            S_COMP: begin
                xors <= x3;
                lp0 <= lp0n; lp1 <= lp1n; lp2 <= lp2n;
                white <= wn;
                env0 <= env0 + del0; env1 <= env1 + del1;
                env2 <= env2 + del2; env3 <= env3 + del3;
                pcm <= (sum4 > 32767) ? 16'sh7fff : (sum4 < -32768) ? 16'sh8000 : sum4[15:0];
                out_valid <= 1'b1;
                n <= n + 1;
                if (n+1 >= N) active <= 0;
                state <= S_WAIT;
            end            S_WAIT: if(sample_tick) begin
                if(!active) state<=S_IDLE;
                else if(n!=0 && n==nextk && seg < K-1) begin load_seg<=seg; state<=S_LD_RECIP_REQ; end
                else state<=S_COMP;
            end
            default: state<=S_IDLE;
            endcase
        end
    end
endmodule
