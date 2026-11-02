// S1 剩余：独立字段的原子快照传输（USB域解码 -> 请求/确认 -> 音频域输出）。
// 字段位序集中在此定义：connected | piano16 | guitar6 | chord4 | drum9 | fret13 |
//                   f1..f12 | lshift,lctrl,rctrl,space,esc | home,end,up,down,left,right,pgup,pgdn
// typ!=1（鼠标/手柄/无设备）或 ready=0 时清空 latest，禁止非键盘报告进入音频域。
module usb_zones_snapshot(
    input usb_clk, input audio_clk, input rst_n,
    input ready, input [1:0] typ, input report, input [63:0] raw,
    output reg [15:0] piano, output reg [5:0] guitar, output reg [3:0] chord, output reg [8:0] drum,
    output reg [12:0] fret, output reg [11:0] f, output reg [7:0] nav,
    output reg lshift, lctrl, rctrl, space, esc, connected
);
    wire [15:0] wp; wire [5:0] wg; wire [3:0] wc; wire [8:0] wd; wire [12:0] wf;
    wire wf1,wf2,wf3,wf4,wf5,wf6,wf7,wf8,wf9,wf10,wf11,wf12;
    wire wls,wlc,wrc,wsp,wesc,whome,wend,wup,wdn,wl,wr,wpu,wpdn;
    usb_hid_zones u_dec(.raw(raw), .piano_held(wp), .guitar_held(wg), .chord_held(wc),
        .drum_held(wd), .fret_held(wf), .f1(wf1),.f2(wf2),.f3(wf3),.f4(wf4),.f5(wf5),.f6(wf6),
        .f7(wf7),.f8(wf8),.f9(wf9),.f10(wf10),.f11(wf11),.f12(wf12),.lshift(wls),.lctrl(wlc),
        .rctrl(wrc),.space(wsp),.esc(wesc),.home(whome),.end_k(wend),.up(wup),.down(wdn),
        .left(wl),.right(wr),.pgup(wpu),.pgdn(wpdn));
    wire [11:0] wf12v = {wf12,wf11,wf10,wf9,wf8,wf7,wf6,wf5,wf4,wf3,wf2,wf1};
    wire [7:0] wnav = {wpu,wpdn,wr,wl,wdn,wup,wend,whome};
    wire [73:0] packed = {1'b1, wp, wg, wc, wd, wf, wf12v, wls, wlc, wrc, wsp, wesc, wnav};
    wire invalid = ((raw[23:16]==8'h01)||(raw[23:16]==8'h02)||(raw[23:16]==8'h03)) ||
                   ((raw[31:24]==8'h01)||(raw[31:24]==8'h02)||(raw[31:24]==8'h03)) ||
                   ((raw[39:32]==8'h01)||(raw[39:32]==8'h02)||(raw[39:32]==8'h03)) ||
                   ((raw[47:40]==8'h01)||(raw[47:40]==8'h02)||(raw[47:40]==8'h03)) ||
                   ((raw[55:48]==8'h01)||(raw[55:48]==8'h02)||(raw[55:48]==8'h03)) ||
                   ((raw[63:56]==8'h01)||(raw[63:56]==8'h02)||(raw[63:56]==8'h03));
    reg [73:0] latest, payload;
    reg request, ack; reg [1:0] ack_sync, request_sync;
    always @(posedge usb_clk or negedge rst_n) begin
        if(!rst_n) begin latest<=0; payload<=0; request<=0; ack_sync<=0; end
        else begin
            ack_sync <= {ack_sync[0], ack};
            if(!ready || typ!=1) latest <= 0;
            else if(report && !invalid) latest <= packed;
            if(request==ack_sync[1] && payload!=latest) begin payload<=latest; request<=~request; end
        end
    end
    always @(posedge audio_clk or negedge rst_n) begin
        if(!rst_n) begin
            request_sync<=0; ack<=0;
            {connected,piano,guitar,chord,drum,fret,f,lshift,lctrl,rctrl,space,esc,nav}<=0;
        end else begin
            request_sync <= {request_sync[0], request};
            if(request_sync[1]!=ack) begin
                {connected,piano,guitar,chord,drum,fret,f,lshift,lctrl,rctrl,space,esc,nav}<=payload;
                ack<=request_sync[1];
            end
        end
    end
endmodule
