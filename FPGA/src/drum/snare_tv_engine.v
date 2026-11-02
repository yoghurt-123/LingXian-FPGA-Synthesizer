// N 军鼓：12 频带、320 段非均匀（前 200 段 1ms，尾部 6.7ms）Codex 压缩模型。
// 独立声部，仅替换旧 N；C 底鼓与 M 闭镲模块不受影响。
module snare_tv_engine(
    input clk, input rst_n, input sample_tick,
    input [8:0] trig, input [3:0] vel, input cancel,
    output reg signed [15:0] data, output reg active, output reg ack
);
    localparam SEGS = 320;
    localparam S_IDLE=4'd0, S_LAT=4'd1, S_KT=4'd2, S_KL=4'd3, S_UPD=4'd4,
               S_PLAY=4'd5, S_VEL=4'd6, S_OUT=4'd7, S_MIX=4'd8,
               S_UPD_RD=4'd9, S_UPD_WR=4'd10;

    reg [3:0] st;
    reg [8:0] work;
    reg [3:0] vel_lat;
    reg [4:0] kvel;
    reg vcancel, act;
    reg [8:0] kcnt, kseg;
    reg [31:0] ph [0:11];
    reg signed [31:0] amp [0:11];
    reg [3:0] kb, ld;
    reg [1:0] ldph;
    reg start_phi;

    reg signed [47:0] acc;
    reg [9:0] sidx;
    reg [4:0] sc;
    reg [2:0] phs;
    reg signed [23:0] mula;
    reg signed [15:0] mulb;
    reg signed [47:0] prod;
    reg signed [23:0] s16;
    reg signed [15:0] vgain;
    reg signed [31:0] mix;

    reg [11:0] raddr;
    reg [3:0] paddr;
    wire signed [31:0] r_amp, r_dap, r_inc;
    wire [31:0] r_phi;
    wire signed [15:0] sine;
    snare_rom u_rom(.clk(clk), .addr(raddr), .amp(r_amp), .dap(r_dap), .inc(r_inc));
    snare_phi_rom u_phi(.clk(clk), .addr(paddr), .data(r_phi));
    sine_rom u_sin(.clk(clk), .addr(sidx), .data(sine));

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st<=S_IDLE; work<=0; vel_lat<=8; kvel<=0; vcancel<=0; act<=0;
            kcnt<=0; kseg<=0; kb<=0; ld<=0; ldph<=0; start_phi<=0;
            acc<=0; sidx<=0; sc<=0; phs<=0; mula<=0; mulb<=0; prod<=0;
            s16<=0; vgain<=0; mix<=0; raddr<=0; paddr<=0;
            data<=0; active<=0; ack<=0;
            for (i=0;i<12;i=i+1) begin ph[i]<=0; amp[i]<=0; end
        end else begin
            ack<=0;
            case (st)
            S_IDLE: if (sample_tick) begin
                work<=trig; vel_lat<=(vel>15)?4'd15:vel; vcancel<=cancel; ack<=1;
                acc<=0; mix<=0; sc<=0; phs<=0; st<=S_LAT;
            end
            S_LAT: begin
                if (vcancel) begin act<=0; active<=0; data<=0; st<=S_IDLE; end
                else if (work[1]) begin
                    act<=1; kcnt<=0; kseg<=0; kvel<={1'b0,vel_lat}+1'b1;
                    ld<=0; ldph<=0; start_phi<=1; st<=S_KT;
                end else if (act) st<=S_UPD;
                else st<=S_IDLE;
            end
            S_KT: begin
                case (ldph)
                2'd0: begin
                    raddr <= kseg*12 + ld;
                    if (start_phi) paddr <= ld[3:0];
                    ldph<=2'd1;
                end
                2'd1: ldph<=2'd2;
                default: begin
                    amp[ld]<=r_amp;
                    if (start_phi) ph[ld]<=r_phi;
                    ldph<=2'd0;
                    if (ld==11) begin ld<=0; start_phi<=0; kcnt<=0; st<=S_UPD; end
                    else ld<=ld+1;
                end
                endcase
            end
            S_KL: begin
                case (ldph)
                2'd0: begin raddr<=kseg*12+ld; ldph<=2'd1; end
                2'd1: ldph<=2'd2;
                default: begin
                    amp[ld]<=r_amp; ldph<=2'd0;
                    if (ld==11) begin ld<=0; st<=S_PLAY; end else ld<=ld+1;
                end
                endcase
            end
            S_UPD: begin
                raddr<=kseg*12+kb;
                st<=S_UPD_RD;
            end
            S_UPD_RD: begin
                st<=S_UPD_WR;
            end
            S_UPD_WR: begin
                ph[kb] <= ph[kb] + r_inc;
                amp[kb] <= amp[kb] + r_dap;
                if (kb==11) begin
                    kb<=0;
                    if (kcnt+1 >= ((kseg<200)?9'd48:9'd322)) begin
                        kcnt<=0;
                        if (kseg+1 < SEGS) begin kseg<=kseg+1; ld<=0; ldph<=0; st<=S_KL; end
                        else begin act<=0; st<=S_PLAY; end
                    end else begin kcnt<=kcnt+1; st<=S_PLAY; end
                end else kb<=kb+1;
            end
            S_PLAY: begin
                case (phs)
                3'd0: begin
                    sidx <= ph[sc[3:0]][31:22] + 10'd256;
                    mula <= act ? amp[sc[3:0]] : 24'sd0;
                    phs<=3'd1;
                end
                3'd1: phs<=3'd2;
                3'd2: begin mulb<=sine; phs<=3'd3; end
                3'd3: begin prod<=mula*mulb; phs<=3'd4; end
                default: begin
                    acc <= acc + prod;
                    phs<=3'd0;
                    if (sc==11) st<=S_VEL; else sc<=sc+1;
                end
                endcase
            end
            S_VEL: begin
                s16 <= ($signed(acc[39:23])>17'sd32767)?24'sd32767:
                       ($signed(acc[39:23])<-17'sd32768)?-24'sd32768:$signed(acc[39:23]);
                vgain <= act ? {2'b00,kvel,7'd0} : 16'sd0;
                st<=S_MIX;
            end
            S_MIX: begin
                mix <= (s16 * vgain) >>> 11;
                st<=S_OUT;
            end
            S_OUT: begin
                data <= (mix>32767)?16'sh7FFF:(mix<-32768)?16'sh8000:mix[15:0];
                active <= act;
                st<=S_IDLE;
            end
            endcase
        end
    end
endmodule
