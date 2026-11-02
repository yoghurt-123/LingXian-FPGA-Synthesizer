`timescale 1ns/1ps
module six_noise_engine(
    input clk, input rst_n, input sample_tick,
    input [1:0] trig, input cancel, input rom_valid,
    output reg signed [15:0] pcm_hat, pcm_ride,
    output reg [1:0] out_valid,
    output [1:0] active_o,
    output reg rom_req,
    output reg [12:0] rom_addr,
    input [31:0] rom_data
);
    localparam [4:0] S_IDLE=0, S_LD_RECIP_REQ=1, S_LD_RECIP_WAIT=2,
        S_LD_CUR_REQ=3, S_LD_CUR_WAIT=4, S_LD_NXT_REQ=5, S_LD_NXT_WAIT=6,
        S_LD_CALC=7, S_LD_KNOT_REQ=8, S_LD_KNOT_WAIT=9, S_RUN=10,
        S_COMP1=11, S_COMP2=15, S_COMP3=16, S_COMP4=17, S_TERM=18, S_PCM=19, S_LD_DELTA=20,
        S_WAIT=12, S_LOAD_CTX=13, S_SAVE=14, S_LD_WAIT=21, S_SV_WAIT=22, S_COMP2B=23;
    reg [4:0] state;
    reg [0:0] ctx;
    reg active;
    reg signed [15:0] pcm;
    reg [1:0] c_active, c_pending;
    reg [5:0] ctx_addr;
    reg ctx_we;
    reg [31:0] ctx_wdata;
    wire [31:0] ctx_rdata;
    reg [4:0] ld_idx, sv_idx;
    reg ld_phase, sv_done;
    six_noise_ctx_ram unctx(.clk(clk),.we(ctx_we),.addr(ctx_addr),.wdata(ctx_wdata),.rdata(ctx_rdata));
    integer i;
    assign active_o=c_active;
    wire [2:0] NB = ctx ? 3'd2 : 3'd4;
    wire [5:0] K = ctx ? 6'd23 : 6'd18;
    wire [31:0] NN = ctx ? 32'd144805 : 32'd28923;
    wire [12:0] APP = ctx ? 13'd4070 : 13'd2434;
    wire [12:0] RO = ctx ? 13'd3399 : 13'd2052;
    wire [12:0] KO = ctx ? 13'd3376 : 13'd2034;
    wire [31:0] SEED = ctx ? 32'h135ca5ee : 32'h13589de2;
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
    reg signed [63:0] lp0p_r,lp1p_r,lp2p_r;
    reg signed [15:0] white;
    reg signed [15:0] wn_r;
    reg [31:0] env0_u,env1_u,env2_u,env3_u;
    reg signed [31:0] a0_r,a1_r,a2_r,a3_r;
    reg [1:0] tstep, dstep;
    reg [15:0] dg_n, dg_c;
    reg signed [31:0] sum_acc,sum4_r;
    reg signed [31:0] t_a;
    reg [31:0] t_e;
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
    always @* begin
        case(dstep)
        2'd0: begin dg_n=gnxt0; dg_c=gcur0; end
        2'd1: begin dg_n=gnxt1; dg_c=gcur1; end
        2'd2: begin dg_n=gnxt2; dg_c=gcur2; end
        default: begin dg_n=gnxt3; dg_c=gcur3; end
        endcase
    end
    wire signed [63:0] dlt_sel = ($signed(dg_n)-$signed(dg_c))*$signed(recip);
    wire [31:0] x1 = xors ^ (xors << 13);
    wire [31:0] x2 = x1 ^ (x1 >> 17);
    wire [31:0] x3 = x2 ^ (x2 << 5);
    wire signed [15:0] wn = x3[31:16] - 16'd32768;
    wire signed [47:0] z = $signed(wn_r) * 65536;
    wire signed [63:0] lp0p = (z - lp0) * 4925;
    wire signed [63:0] lp1p = (z - lp1) * 18209;
    wire signed [63:0] lp2p = (z - lp2) * 42411;
    wire signed [31:0] a0 = (NB==4) ? (lp0 >>> 16) : (lp1 >>> 16);
    wire signed [31:0] a1 = (NB==4) ? ((lp1 >>> 16) - (lp0 >>> 16)) : (wn_r - (lp1 >>> 16));
    wire signed [31:0] a2 = (lp2 >>> 16) - (lp1 >>> 16);
    wire signed [31:0] a3 = wn_r - (lp2 >>> 16);
    always @* begin
        case(tstep)
        2'd0: begin t_a=a0_r; t_e=env0_u; end
        2'd1: begin t_a=a1_r; t_e=env1_u; end
        2'd2: begin t_a=a2_r; t_e=env2_u; end
        default: begin t_a=a3_r; t_e=env3_u; end
        endcase
    end
    wire signed [63:0] t_prod = t_a * $signed(t_e[31:16]);
    wire signed [31:0] t_term = t_prod >>> 15;

    function [31:0] ctx_save_data;
        input [4:0] idx;
        begin
            case(idx)
            5'd0: ctx_save_data=n;
            5'd1: ctx_save_data={26'd0,seg};
            5'd2: ctx_save_data=nextk;
            5'd3: ctx_save_data=xors;
            5'd4: ctx_save_data=recip;
            5'd5: ctx_save_data=lp0[31:0];
            5'd6: ctx_save_data={16'd0,lp0[47:32]};
            5'd7: ctx_save_data=lp1[31:0];
            5'd8: ctx_save_data={16'd0,lp1[47:32]};
            5'd9: ctx_save_data=lp2[31:0];
            5'd10: ctx_save_data={16'd0,lp2[47:32]};
            5'd11: ctx_save_data=env0;
            5'd12: ctx_save_data=env1;
            5'd13: ctx_save_data=env2;
            5'd14: ctx_save_data=env3;
            5'd15: ctx_save_data=del0;
            5'd16: ctx_save_data=del1;
            5'd17: ctx_save_data=del2;
            5'd18: ctx_save_data=del3;
            default: ctx_save_data=32'd0;
            endcase
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=S_IDLE; n<=0; seg<=0; load_seg<=0; nextk<=0; seed<=0;
            recip<=0; j<=0; active<=0; out_valid<=0; pcm<=0;
            gcur0<=0;gcur1<=0;gcur2<=0;gcur3<=0;
            gnxt0<=0;gnxt1<=0;gnxt2<=0;gnxt3<=0;
            env0<=0;env1<=0;env2<=0;env3<=0;
            del0<=0;del1<=0;del2<=0;del3<=0;
            lp0<=0;lp1<=0;lp2<=0; white<=0; b0<=0;b1<=0;b2<=0;b3<=0;
            wn_r<=0; env0_u<=0;env1_u<=0;env2_u<=0;env3_u<=0;
            a0_r<=0;a1_r<=0;a2_r<=0;a3_r<=0;
            tstep<=0; sum_acc<=0; sum4_r<=0;
            dstep<=0;
            nsum<=0; xors<=0; curw<=0; nxtw<=0; curg<=0; nxtg<=0;
            init_phase<=0; rom_addr<=0;
            ctx<=0; c_active<=0; c_pending<=0;
            pcm_hat<=0; pcm_ride<=0;
            ctx_addr<=0; ctx_we<=0; ctx_wdata<=0;
            ld_idx<=0; sv_idx<=0; ld_phase<=0; sv_done<=0;
        end else begin
            out_valid<=0;
            rom_req<=0;
            if(sample_tick) begin
                if(trig[0]) c_pending[0]<=1;
                if(trig[1]) c_pending[1]<=1;
            end
            if(cancel) begin
                active<=0; pcm<=0; state<=S_IDLE;
                c_active<=0; c_pending<=0; pcm_hat<=0; pcm_ride<=0;
            end else case(state)
            S_IDLE: if(sample_tick) begin
                if(trig[0]) c_pending[0]<=1;
                if(trig[1]) c_pending[1]<=1;
                ctx<=0; state<=S_LOAD_CTX;
            end
            S_LOAD_CTX: begin
                if(c_pending[ctx]) begin
                    active<=1; pcm<=0; n<=0; seg<=0; load_seg<=0; j<=0;
                    xors<=SEED; lp0<=0; lp1<=0; lp2<=0; init_phase<=1;
                    state<=S_LD_RECIP_REQ;
                end else if(c_active[ctx]) begin
                    active<=1;
                    ctx_addr<={ctx,5'd0}; ld_idx<=0; ld_phase<=0;
                    state<=S_LD_WAIT;
                end else begin
                    if(ctx==1) state<=S_WAIT;
                    else begin ctx<=1; state<=S_LOAD_CTX; end
                end
            end
            S_LD_WAIT: begin
                if(!ld_phase) ld_phase<=1;
                else begin
                    case(ld_idx)
                    5'd0: n<=ctx_rdata;
                    5'd1: seg<=ctx_rdata[5:0];
                    5'd2: nextk<=ctx_rdata;
                    5'd3: xors<=ctx_rdata;
                    5'd4: recip<=ctx_rdata;
                    5'd5: lp0[31:0]<=ctx_rdata;
                    5'd6: lp0[47:32]<=ctx_rdata[15:0];
                    5'd7: lp1[31:0]<=ctx_rdata;
                    5'd8: lp1[47:32]<=ctx_rdata[15:0];
                    5'd9: lp2[31:0]<=ctx_rdata;
                    5'd10: lp2[47:32]<=ctx_rdata[15:0];
                    5'd11: env0<=ctx_rdata;
                    5'd12: env1<=ctx_rdata;
                    5'd13: env2<=ctx_rdata;
                    5'd14: env3<=ctx_rdata;
                    5'd15: del0<=ctx_rdata;
                    5'd16: del1<=ctx_rdata;
                    5'd17: del2<=ctx_rdata;
                    default: del3<=ctx_rdata;
                    endcase
                    if(ld_idx==5'd18) begin
                        if(n!=0 && n==nextk && seg<K-1) begin
                            load_seg<=seg; state<=S_LD_RECIP_REQ;
                        end else state<=S_COMP1;
                    end else begin
                        ld_idx<=ld_idx+5'd1;
                        ctx_addr<={ctx,5'd0}+ld_idx+5'd1;
                        ld_phase<=0;
                    end
                end
            end
            S_SAVE: begin
                c_active[ctx]<=active; c_pending[ctx]<=0;
                sv_idx<=0; sv_done<=0; state<=S_SV_WAIT;
            end
            S_SV_WAIT: begin
                if(!sv_done) begin
                    ctx_we<=1; ctx_addr<={ctx,5'd0}+sv_idx;
                    ctx_wdata<=ctx_save_data(sv_idx);
                    if(sv_idx==5'd18) sv_done<=1;
                    else sv_idx<=sv_idx+5'd1;
                end else begin
                    ctx_we<=0;
                    if(ctx==1) state<=S_WAIT;
                    else begin ctx<=1; state<=S_LOAD_CTX; end
                end
            end            S_LD_RECIP_REQ: begin
                rom_req<=1; rom_addr<=RO+load_seg; state<=S_LD_RECIP_WAIT;
            end
            S_LD_RECIP_WAIT: begin
                if(rom_valid) begin
                    recip<=rom_data; state<=S_LD_CUR_REQ;
                end else rom_req<=1;
            end
            S_LD_CUR_REQ: begin
                rom_req<=1; rom_addr<=gword; state<=S_LD_CUR_WAIT;
            end
            S_LD_CUR_WAIT: begin
                if(rom_valid) begin
                    curw<=rom_data; state<=S_LD_NXT_REQ;
                end else rom_req<=1;
            end
            S_LD_NXT_REQ: begin
                rom_req<=1; rom_addr<=APP + (nidx>>1); state<=S_LD_NXT_WAIT;
            end
            S_LD_NXT_WAIT: begin
                if(rom_valid) begin
                    nxtw<=rom_data;
                    case(j)
                    0: begin gcur0<=gval; gnxt0<=gnval; end
                    1: begin gcur1<=gval; gnxt1<=gnval; end
                    2: begin gcur2<=gval; gnxt2<=gnval; end
                    default: begin gcur3<=gval; gnxt3<=gnval; end
                    endcase
                    if(j+1>=NB) begin j<=0; state<=S_LD_CALC; end
                    else begin j<=j+1; state<=S_LD_CUR_REQ; end
                end else rom_req<=1;
            end
            S_LD_CALC: begin
                env0<={gcur0,16'd0}; env1<={gcur1,16'd0};
                env2<={gcur2,16'd0}; env3<={gcur3,16'd0};
                dstep<=0;
                state<=S_LD_DELTA;
            end
            S_LD_DELTA: begin
                case(dstep)
                2'd0: del0<=dlt_sel>>>16;
                2'd1: del1<=dlt_sel>>>16;
                2'd2: del2<=dlt_sel>>>16;
                default: del3<=dlt_sel>>>16;
                endcase
                if(dstep==2'd3) begin
                    rom_req<=1;
                    if(init_phase) rom_addr<=KO+13'd1;
                    else if(load_seg < K-2) rom_addr<=KO+load_seg+13'd1;
                    else rom_addr<=KO+load_seg;
                    state<=S_LD_KNOT_WAIT;
                end else dstep<=dstep+2'd1;
            end
            S_LD_KNOT_WAIT: begin
                if(rom_valid) begin
                    if(init_phase) begin
                        nextk<=rom_data; seg<=6'd1; init_phase<=0; state<=S_COMP1;
                    end else if(load_seg < K-2) begin
                        nextk<=rom_data; seg<=load_seg+6'd1; state<=S_COMP1;
                    end else begin
                        nextk<=32'hffffffff; seg<=load_seg; state<=S_COMP1;
                    end
                end else rom_req<=1;
            end
            S_RUN: if(sample_tick) begin
                if(!active || n>=NN) begin active<=0; state<=S_IDLE; end
                else if(n!=0 && n==nextk) begin
                    load_seg<=seg; state<=S_LD_RECIP_REQ;
                end else state<=S_COMP1;
            end
            S_COMP1: begin
                xors <= x3;
                white <= wn;
                wn_r <= wn;
                env0_u<=env0; env1_u<=env1; env2_u<=env2; env3_u<=env3;
                env0 <= env0 + del0; env1 <= env1 + del1;
                env2 <= env2 + del2; env3 <= env3 + del3;
                n <= n + 1;
                if (n+1 >= NN) active <= 0;
                state <= S_COMP2;
            end
            S_COMP2: begin
                lp0p_r <= lp0p; lp1p_r <= lp1p; lp2p_r <= lp2p;
                state <= S_COMP2B;
            end
            S_COMP2B: begin
                lp0 <= lp0 + (lp0p_r >>> 16);
                lp1 <= lp1 + (lp1p_r >>> 16);
                lp2 <= lp2 + (lp2p_r >>> 16);
                state <= S_COMP3;
            end
            S_COMP3: begin
                a0_r<=a0; a1_r<=a1; a2_r<=a2; a3_r<=a3;
                state <= S_COMP4;
            end
            S_COMP4: begin
                tstep<=0; sum_acc<=0;
                state<=S_TERM;
            end
            S_TERM: begin
                sum_acc <= sum_acc + t_term;
                if (tstep == ((NB==4) ? 2'd3 : 2'd1)) begin
                    sum4_r <= sum_acc + t_term;
                    state<=S_PCM;
                end else begin
                    tstep<=tstep+2'd1;
                end
            end
            S_PCM: begin
                pcm <= (sum4_r > 32767) ? 16'sh7fff : (sum4_r < -32768) ? 16'sh8000 : sum4_r[15:0];
                case(ctx)
                1'd0: pcm_hat <= (sum4_r > 32767) ? 16'sh7fff : (sum4_r < -32768) ? 16'sh8000 : sum4_r[15:0];
                default: pcm_ride <= (sum4_r > 32767) ? 16'sh7fff : (sum4_r < -32768) ? 16'sh8000 : sum4_r[15:0];
                endcase
                out_valid[ctx] <= 1'b1;
                state <= S_SAVE;
            end
            S_WAIT: if(sample_tick) begin
                if(trig[0]) c_pending[0]<=1;
                if(trig[1]) c_pending[1]<=1;
                ctx<=0; state<=S_LOAD_CTX;
            end
            default: state<=S_IDLE;
            endcase
        end
    end
endmodule





