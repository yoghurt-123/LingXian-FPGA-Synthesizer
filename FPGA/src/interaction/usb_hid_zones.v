// S1 独立HID字段解码：钢琴16 / 吉他6弦 / 和弦4 / 鼓9 + 品位、修饰与特殊键。
// 固定分区：钢琴 A-L + Z-M；吉他 QWERTY；和弦 UIOP；鼓小键盘1..9（NumLock usage）。
// 左Ctrl=吉他掌根闷音；右Ctrl=钢琴踏板延迟释放修饰（两者独立）。
// 纯组合解码；原子请求/确认与connected仍由现有快照模块负责，本模块不改变其握手。
module usb_hid_zones(
    input  [63:0] raw,
    output reg [15:0] piano_held,
    output reg [5:0]  guitar_held,
    output reg [3:0]  chord_held,
    output reg [8:0]  drum_held,
    output reg [12:0] fret_held,
    output reg f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,
    output reg lshift,lctrl,rctrl,space,esc,
    output reg home,end_k,up,down,left,right,pgup,pgdn
);
    integer i;
    always @* begin
        piano_held=0; guitar_held=0; chord_held=0; drum_held=0; fret_held=0;
        f1=0;f2=0;f3=0;f4=0;f5=0;f6=0;f7=0;f8=0;f9=0;f10=0;f11=0;f12=0;
        lshift=raw[1]; lctrl=raw[0]; rctrl=raw[5];
        space=0;esc=0;home=0;end_k=0;up=0;down=0;left=0;right=0;pgup=0;pgdn=0;
        for(i=2;i<8;i=i+1) begin
            case(raw[i*8 +: 8])
            // 吉他六弦：Q W E R T Y
            8'h14: guitar_held[0]=1;
            8'h1A: guitar_held[1]=1;
            8'h08: guitar_held[2]=1;
            8'h15: guitar_held[3]=1;
            8'h17: guitar_held[4]=1;
            8'h1C: guitar_held[5]=1;
            // 和弦：U I O P
            8'h18: chord_held[0]=1;
            8'h0C: chord_held[1]=1;
            8'h12: chord_held[2]=1;
            8'h13: chord_held[3]=1;
            // 钢琴白键：A S D F G H J K L -> C4..D5
            8'h04: piano_held[0]=1;
            8'h16: piano_held[1]=1;
            8'h07: piano_held[2]=1;
            8'h09: piano_held[3]=1;
            8'h0A: piano_held[4]=1;
            8'h0B: piano_held[5]=1;
            8'h0D: piano_held[6]=1;
            8'h0E: piano_held[7]=1;
            8'h0F: piano_held[8]=1;
            // 钢琴黑键：Z X C V B N M -> C#4..D#5
            8'h1D: piano_held[9]=1;
            8'h1B: piano_held[10]=1;
            8'h06: piano_held[11]=1;
            8'h19: piano_held[12]=1;
            8'h05: piano_held[13]=1;
            8'h11: piano_held[14]=1;
            8'h10: piano_held[15]=1;
            // 鼓：小键盘1..9
            8'h59: drum_held[0]=1;
            8'h5A: drum_held[1]=1;
            8'h5B: drum_held[2]=1;
            8'h5C: drum_held[3]=1;
            8'h5D: drum_held[4]=1;
            8'h5E: drum_held[5]=1;
            8'h5F: drum_held[6]=1;
            8'h60: drum_held[7]=1;
            8'h61: drum_held[8]=1;
            // 品位 0..9, -, =, Backspace
            8'h27: fret_held[0]=1;
            8'h1E: fret_held[1]=1;
            8'h1F: fret_held[2]=1;
            8'h20: fret_held[3]=1;
            8'h21: fret_held[4]=1;
            8'h22: fret_held[5]=1;
            8'h23: fret_held[6]=1;
            8'h24: fret_held[7]=1;
            8'h25: fret_held[8]=1;
            8'h26: fret_held[9]=1;
            8'h2D: fret_held[10]=1;
            8'h2E: fret_held[11]=1;
            8'h2A: fret_held[12]=1;
            // 功能与特殊键
            8'h3A: f1=1; 8'h3B: f2=1; 8'h3C: f3=1; 8'h3D: f4=1;
            8'h3E: f5=1; 8'h3F: f6=1; 8'h40: f7=1; 8'h41: f8=1;
            8'h42: f9=1; 8'h43: f10=1; 8'h44: f11=1; 8'h45: f12=1;
            8'h2C: space=1; 8'h29: esc=1;
            8'h4A: home=1; 8'h4D: end_k=1;
            8'h52: up=1; 8'h51: down=1; 8'h50: left=1; 8'h4F: right=1;
            8'h4B: pgup=1; 8'h4E: pgdn=1;
            default: ;
            endcase
        end
    end
endmodule
