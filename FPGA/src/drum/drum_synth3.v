// 可综合裁剪的三音鼓引擎：CFG=1 仅底鼓；CFG=2 底鼓+军鼓+闭镲。
// 底鼓保留 14 频带/256 段认可参数；军鼓、闭镲固定声部：重击复位自身，互不抢占。
// 相位/包络/变音更新逐声部分时，共用 1 组加法器、移位器和比较器；乘积仍共用 1 个乘法器。
module drum_synth3 #(parameter CFG = 2)(
    input clk, input rst_n, input sample_tick,
    input [8:0] trig, input [3:0] vel, input cancel,
    output reg signed [15:0] data, output reg active, output reg ack,
    output reg signed [15:0] kick_pcm, output reg signed [15:0] hat_pcm
);
    localparam SEGS = 256, NSEG = 328;
    localparam S_IDLE=4'd0, S_LAT=4'd1, S_TRIG=4'd2, S_KT=4'd3, S_KL=4'd4,
               S_LV=4'd5, S_UPDK=4'd6, S_UPDV=4'd7, S_PLAY=4'd8, S_VEL=4'd9, S_OUT=4'd10;

    reg [3:0] st;
    reg [8:0] work;
    reg [3:0] vel_lat;
    reg vcancel;
    reg [14:0] lfsr;

    // 底鼓
    reg kick_act;
    reg [8:0] kcnt, kseg;
    reg [31:0] kph [0:13];
    reg signed [31:0] kamp [0:13];
    reg [4:0] kvel_r;
    reg [3:0] kb;
    reg [1:0] kup_ph;

    // 两个固定通用声部（0=军鼓 1=闭镲）
    reg hat_act;
    reg [4:0] vvel_hat;
    reg [31:0] vp [0:3];
    reg signed [31:0] vinc [0:3], vamp [0:3];
    reg [3:0] vdec [0:3];
    reg signed [31:0] vnoise;
    reg [3:0] vndec;
    reg [3:0] us;

    reg signed [39:0] acc [0:1];
    reg [9:0] sidx;
    reg [4:0] sc;
    reg [2:0] src; reg [3:0] prt;
    reg [2:0] phs;
    reg signed [23:0] mula;
    reg signed [15:0] mulb;
    reg signed [39:0] prod;
    reg signed [31:0] mix;
    reg signed [15:0] kick_q, hat_q;
    reg [1:0] vsel;
    reg [1:0] vphs;
    reg signed [15:0] vgain;
    reg signed [23:0] acc24;

    reg [4:0] ld;
    reg [1:0] ldph;
    reg [3:0] nvsnd;
    reg kick_ld_phi;

    reg [11:0] kaddr;
    wire signed [31:0] k_amp, k_dap, k_inc;
    reg [3:0] kpaddr;
    wire [31:0] k_phi;
    reg [8:0] saddr;
    wire [31:0] sdata;
    wire signed [15:0] sine;
    kick_rom u_krom(.clk(clk), .addr(kaddr), .amp(k_amp), .dap(k_dap), .inc(k_inc));
    kick_phi_rom u_kphi(.clk(clk), .addr(kpaddr), .data(k_phi));
    snd_rom u_srom(.clk(clk), .addr(saddr), .data(sdata));
    sine_rom u_sin(.clk(clk), .addr(sidx), .data(sine));

    wire [4:0] vv_sel = vvel_hat;
    wire [8:0] clear_w = 9'd1 << nvsnd;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st<=S_IDLE; work<=0; vel_lat<=8; vcancel<=0; lfsr<=15'h7FFF;
            kick_act<=0; kcnt<=0; kseg<=0; kvel_r<=0; kb<=0;
            hat_act<=0; kup_ph<=0; us<=0; acc[0]<=0; acc[1]<=0;
            data<=0; active<=0; ack<=0; mix<=0; sc<=0; src<=0; prt<=0; phs<=0;
        kick_q<=0; hat_q<=0; kick_pcm<=0; hat_pcm<=0;
            mula<=0; mulb<=0; prod<=0; vsel<=0; vphs<=0; vgain<=0; acc24<=0;
            ld<=0; ldph<=0; nvsnd<=0; kick_ld_phi<=0;
            kaddr<=0; kpaddr<=0; saddr<=0; sidx<=0;
            for (i=0;i<14;i=i+1) begin kph[i]<=0; kamp[i]<=0; end
            for (i=0;i<4;i=i+1) begin vp[i]<=0; vinc[i]<=0; vamp[i]<=0; vdec[i]<=0; end
            vvel_hat<=0; vnoise<=0; vndec<=0;
        end else begin
            ack<=0;
            case (st)
            S_IDLE: if (sample_tick) begin
                work<=trig; vel_lat<=(vel>15)?4'd15:vel; vcancel<=cancel; ack<=1;
                acc[0]<=0; acc[1]<=0; mix<=0; st<=S_LAT;
            end
            S_LAT: begin
                if (vcancel) begin kick_act<=0; hat_act<=0; active<=0; data<=0; work<=0; st<=S_IDLE; end
                else st<=(work!=0)?S_TRIG:S_UPDK;
            end
            S_TRIG: begin
                if (work[0]) begin
                    work[0]<=0; kick_act<=1; kcnt<=0; kseg<=0; kvel_r<={1'b0,vel_lat}+1;
                    ld<=0; ldph<=0; kick_ld_phi<=1; st<=S_KT;
                end else if (CFG >= 2 && work[1]) begin
                    work[1]<=0; sidx<=10'd0; st<=S_TRIG;
                end else if (CFG >= 2 && work[2]) begin
                    work[2]<=0; nvsnd<=2;
                    hat_act<=1; vvel_hat<={1'b0,vel_lat}+1;
                    vp[0]<=0; vp[1]<=0; vp[2]<=0; vp[3]<=0;
                    ld<=0; ldph<=0; st<=S_LV;
                end else begin work<=0; st<=S_UPDK; end
            end
            S_KT: begin
                case (ldph)
                2'd0: begin kaddr<=kseg*14+ld; if(kick_ld_phi) kpaddr<=ld[3:0]; ldph<=1; end
                2'd1: ldph<=2;
                default: begin
                    kamp[ld]<=k_amp;
                    if (kick_ld_phi) kph[ld]<=k_phi;
                    ldph<=0;
                    if (ld==13) begin ld<=0; kick_ld_phi<=0; kcnt<=0; st<=(work!=0)?S_TRIG:S_UPDK; end
                    else ld<=ld+1;
                end
                endcase
            end
            S_LV: begin
                case (ldph)
                2'd0: begin
                    saddr <= nvsnd*32 + ((ld<8) ? ({3'd0,(ld>>1)}*3'd4 + ({2'd0,ld[0]} ? 9'd3 : 9'd0)) : 9'd20);
                    ldph<=1;
                end
                2'd1: ldph<=2;
                default: begin
                    ldph<=0;
                    if (ld<8) begin
                        if (ld[0]==0) vinc[ld[2:1]] <= $signed(sdata);
                        else begin
                            vamp[ld[2:1]] <= $signed({{8{sdata[23]}},sdata[23:0]});
                            vdec[ld[2:1]] <= sdata[27:24];
                        end
                    end else begin
                        vnoise <= $signed({{8{sdata[23]}},sdata[23:0]});
                        vndec <= sdata[27:24];
                    end
                    if (ld==8) st<=S_TRIG; else ld<=ld+1;
                end
                endcase
            end
            S_UPDK: begin
                if (kick_act) begin
                    case (kup_ph)
                    2'd0: begin kaddr<=kseg*14+kb; kup_ph<=2'd1; end
                    2'd1: kup_ph<=2'd2;
                    default: begin
                        kph[kb] <= kph[kb] + k_inc;
                        kamp[kb] <= kamp[kb] + k_dap;
                        kup_ph<=2'd0;
                        if (kb==13) begin
                            kb<=0;
                            if (kcnt+1>=NSEG) begin
                                kcnt<=0;
                                if (kseg+1<SEGS) begin kseg<=kseg+1; ld<=0; ldph<=0; st<=S_KL; end
                                else begin kick_act<=0; st<=S_UPDV; end
                            end else begin kcnt<=kcnt+1; st<=S_UPDV; end
                        end else kb<=kb+1;
                    end
                    endcase
                end else begin kb<=0; kup_ph<=0; st<=S_UPDV; end
            end
            S_UPDV: begin
                if (hat_act) begin
                    vp[us] <= vp[us] + vinc[us];
                    vamp[us] <= ((vamp[us] - (vamp[us] >>> vdec[us])) < 0) ? 0 : (vamp[us] - (vamp[us] >>> vdec[us]));
                    if (us==3) begin
                        vnoise <= ((vnoise - (vnoise >>> vndec)) < 0) ? 0 : (vnoise - (vnoise >>> vndec));
                        if (vamp[0]==0 && vamp[1]==0 && vamp[2]==0 && vamp[3]==0 && vnoise==0) hat_act<=0;
                        us<=0;
                        lfsr <= {lfsr[13:0], lfsr[14]^lfsr[13]};
                        sc<=0; src<=0; prt<=0; phs<=0; vsel<=0; vphs<=0; st<=S_PLAY;
                    end else us<=us+1;
                end else begin
                    us<=0; lfsr <= {lfsr[13:0], lfsr[14]^lfsr[13]};
                    sc<=0; src<=0; prt<=0; phs<=0; vsel<=0; vphs<=0; st<=S_PLAY;
                end
            end
            S_KL: begin
                case (ldph)
                2'd0: begin kaddr<=kseg*14+ld; ldph<=1; end
                2'd1: ldph<=2;
                default: begin
                    kamp[ld]<=k_amp; ldph<=0;
                    if (ld==13) begin ld<=0; st<=S_UPDV; end
                    else ld<=ld+1;
                end
                endcase
            end
            S_PLAY: begin
                case (phs)
                2'd0: begin
                    if (src==0) begin
                        sidx <= kph[prt[3:0]][31:22] + 10'd256;
                        mula <= kick_act ? kamp[prt[3:0]] : 24'sd0;
                    end else if (prt<4) begin
                        sidx <= vp[prt[1:0]][31:22];
                        mula <= hat_act ? vamp[prt[1:0]] : 24'sd0;
                    end else begin
                        mula <= hat_act ? vnoise : 24'sd0;
                    end
                    phs<=1;
                end
                3'd1: begin
                    if (src==0) phs<=3'd2;
                    else begin
                        mulb <= (prt==4) ? (lfsr[2] ? 16'sd32767 : -16'sd32767) : sine;
                        phs<=3'd2;
                    end
                end
                3'd2: begin
                    if (src==0) begin mulb<=sine; phs<=3'd3; end
                    else begin prod<=mula*mulb; phs<=3'd3; end
                end
                3'd3: begin
                    if (src==0) begin prod<=mula*mulb; phs<=3'd4; end
                    else begin
                        acc[1]<=acc[1]+prod; phs<=3'd0;
                        if (sc==4) st<=S_VEL;
                        else begin sc<=sc+1; prt<=prt+1; end
                    end
                end
                default: begin
                    acc[0]<=acc[0]+prod; phs<=3'd0;
                    if (sc==13) begin src<=1; prt<=0; sc<=0; sidx<=10'd0; end
                    else begin sc<=sc+1; prt<=prt+1; end
                end
                endcase
            end
            S_VEL: begin
                case (vphs)
                2'd0: begin
                    if (vsel==0) begin
                        acc24 <= ($signed(acc[0][39:23])>17'sd32767)?24'sd32767:
                                 ($signed(acc[0][39:23])<-17'sd32768)?-24'sd32768:$signed(acc[0][39:23]);
                        vgain <= kick_act ? {2'b00,kvel_r,7'd0} : 16'sd0;
                    end else begin
                        acc24 <= ($signed(acc[1][39:23])>17'sd32767)?24'sd32767:
                                 ($signed(acc[1][39:23])<-17'sd32768)?-24'sd32768:$signed(acc[1][39:23]);
                        vgain <= hat_act ? {2'b00,vv_sel,7'd0} : 16'sd0;
                    end
                    vphs<=1;
                end
                2'd1: begin mula<=acc24; mulb<=vgain; vphs<=2; end
                2'd2: begin prod<=mula*mulb; vphs<=3; end
                default: begin
                    mix <= mix + (prod>>>11);
                    if (vsel==0) kick_q <= (prod>>>11);
                    else hat_q <= (prod>>>11);
                    vphs<=0;
                    if (vsel==1) st<=S_OUT; else vsel<=vsel+1;
                end
                endcase
            end
            S_OUT: begin
                data <= (mix>32767)?16'sh7FFF:(mix<-32768)?16'sh8000:mix[15:0];
                kick_pcm <= kick_q;
                hat_pcm <= hat_q;
                active <= kick_act | hat_act;
                st<=S_IDLE;
            end
            endcase
        end
    end
endmodule
