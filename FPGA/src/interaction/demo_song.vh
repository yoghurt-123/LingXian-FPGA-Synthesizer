// 板上演示事件表（由 guitar_proto/scripts/gen_demo_song.ps1 生成；勿手改）
// 事件 66 个；时长≈7.46s；时间单位=RTL 采样（Fs=52500000/1088）
// 编码 {wr,mute,vel[3:0],note[3:0],slot[2:0],time[18:0]} = 32 位；vel 实际增益=(vel+1)/16
function [31:0] demo_ev;
    input [6:0] idx;
    begin
        case (idx)
            7'd0: demo_ev = 32'h18000000;
            7'd1: demo_ev = 32'h18480184;
            7'd2: demo_ev = 32'h14900308;
            7'd3: demo_ev = 32'h54005A7A;
            7'd4: demo_ev = 32'h54485BFE;
            7'd5: demo_ev = 32'h50905D82;
            7'd6: demo_ev = 32'h0C9087B7;
            7'd7: demo_ev = 32'h104888E4;
            7'd8: demo_ev = 32'h10008A12;
            7'd9: demo_ev = 32'h4C90E230;
            7'd10: demo_ev = 32'h5048E35E;
            7'd11: demo_ev = 32'h5000E48C;
            7'd12: demo_ev = 32'h14010F6D;
            7'd13: demo_ev = 32'h144910F1;
            7'd14: demo_ev = 32'h10911275;
            7'd15: demo_ev = 32'h0C913CAA;
            7'd16: demo_ev = 32'h10493DD8;
            7'd17: demo_ev = 32'h10013F05;
            7'd18: demo_ev = 32'h9A1969E7;
            7'd19: demo_ev = 32'h99216B6B;
            7'd20: demo_ev = 32'h95696CEF;
            7'd21: demo_ev = 32'h5619C461;
            7'd22: demo_ev = 32'h5521C5E5;
            7'd23: demo_ev = 32'h5169C769;
            7'd24: demo_ev = 32'h0D69F19E;
            7'd25: demo_ev = 32'h1121F2CB;
            7'd26: demo_ev = 32'h1219F3F9;
            7'd27: demo_ev = 32'h4D6A4C17;
            7'd28: demo_ev = 32'h51224D45;
            7'd29: demo_ev = 32'h521A4E73;
            7'd30: demo_ev = 32'h161A7954;
            7'd31: demo_ev = 32'h15227AD8;
            7'd32: demo_ev = 32'h116A7C5C;
            7'd33: demo_ev = 32'h0D6AA691;
            7'd34: demo_ev = 32'h1122A7BF;
            7'd35: demo_ev = 32'h121AA8EC;
            7'd36: demo_ev = 32'h98DAD3CE;
            7'd37: demo_ev = 32'h98A2D552;
            7'd38: demo_ev = 32'h966AD6D6;
            7'd39: demo_ev = 32'h54DB2E48;
            7'd40: demo_ev = 32'h54A32FCC;
            7'd41: demo_ev = 32'h526B3150;
            7'd42: demo_ev = 32'h0E6B5B85;
            7'd43: demo_ev = 32'h10A35CB2;
            7'd44: demo_ev = 32'h10DB5DE0;
            7'd45: demo_ev = 32'h4E6BB5FF;
            7'd46: demo_ev = 32'h50A3B72C;
            7'd47: demo_ev = 32'h50DBB85A;
            7'd48: demo_ev = 32'h14DBE33B;
            7'd49: demo_ev = 32'h14A3E4BF;
            7'd50: demo_ev = 32'h126BE643;
            7'd51: demo_ev = 32'h0E6C1078;
            7'd52: demo_ev = 32'h10A411A6;
            7'd53: demo_ev = 32'h10DC12D3;
            7'd54: demo_ev = 32'h18043DB5;
            7'd55: demo_ev = 32'h184C3F39;
            7'd56: demo_ev = 32'h149440BD;
            7'd57: demo_ev = 32'h5404982F;
            7'd58: demo_ev = 32'h544C99B3;
            7'd59: demo_ev = 32'h50949B37;
            7'd60: demo_ev = 32'h0C94C56C;
            7'd61: demo_ev = 32'h104CC699;
            7'd62: demo_ev = 32'h1004C7C7;
            7'd63: demo_ev = 32'h18057A5F;
            7'd64: demo_ev = 32'h184D7BE3;
            7'd65: demo_ev = 32'h14957D67;
            default: demo_ev = 32'd0;
        endcase
    end
endfunction
