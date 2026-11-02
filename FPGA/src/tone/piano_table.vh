// 钢琴音色谐波表：从 88 键钢琴采样的 WAV 中提取 Do Re Mi Fa Sol La Si 七个音，
// 每个音独立分析 16 次谐波幅度（Q15，32768 = 1.0），各自归一化，保证：
//   1) 七个音叠加都不会超过 16 位 PCM 满幅；
//   2) 七个音响度基本一致。
// 分析窗口为起音后 40~180ms（汉宁窗），保留钢琴起音明亮、随后衰减的频谱特征。
// NOTE_SEL: 0=Do 1=Re 2=Mi 3=Fa 4=Sol 5=La 6=Si；idx=0 对应 H1，idx=15 对应 H16。
function [15:0] piano_coef;
    input [2:0] note;
    input [4:0] idx;
    begin
        case (note)
            3'd0: case (idx) // Do
                5'd0: piano_coef = 16'd6715;
                5'd1: piano_coef = 16'd11982;
                5'd2: piano_coef = 16'd4075;
                5'd3: piano_coef = 16'd3433;
                5'd4: piano_coef = 16'd4339;
                5'd5: piano_coef = 16'd1012;
                5'd6: piano_coef = 16'd1092;
                5'd7: piano_coef = 16'd16;
                5'd8: piano_coef = 16'd63;
                5'd9: piano_coef = 16'd5;
                5'd10: piano_coef = 16'd24;
                5'd11: piano_coef = 16'd4;
                5'd12: piano_coef = 16'd5;
                5'd13: piano_coef = 16'd2;
                5'd14: piano_coef = 16'd0;
                5'd15: piano_coef = 16'd0;
                default: piano_coef = 16'd0;
            endcase
            3'd1: case (idx) // Re
                5'd0: piano_coef = 16'd12630;
                5'd1: piano_coef = 16'd16310;
                5'd2: piano_coef = 16'd2256;
                5'd3: piano_coef = 16'd658;
                5'd4: piano_coef = 16'd630;
                5'd5: piano_coef = 16'd191;
                5'd6: piano_coef = 16'd54;
                5'd7: piano_coef = 16'd17;
                5'd8: piano_coef = 16'd16;
                5'd9: piano_coef = 16'd1;
                5'd10: piano_coef = 16'd1;
                5'd11: piano_coef = 16'd1;
                5'd12: piano_coef = 16'd1;
                5'd13: piano_coef = 16'd0;
                5'd14: piano_coef = 16'd0;
                5'd15: piano_coef = 16'd0;
                default: piano_coef = 16'd0;
            endcase
            3'd2: case (idx) // Mi
                5'd0: piano_coef = 16'd10310;
                5'd1: piano_coef = 16'd10319;
                5'd2: piano_coef = 16'd5459;
                5'd3: piano_coef = 16'd4874;
                5'd4: piano_coef = 16'd1021;
                5'd5: piano_coef = 16'd721;
                5'd6: piano_coef = 16'd20;
                5'd7: piano_coef = 16'd19;
                5'd8: piano_coef = 16'd17;
                5'd9: piano_coef = 16'd5;
                5'd10: piano_coef = 16'd1;
                5'd11: piano_coef = 16'd0;
                5'd12: piano_coef = 16'd1;
                5'd13: piano_coef = 16'd0;
                5'd14: piano_coef = 16'd0;
                5'd15: piano_coef = 16'd0;
                default: piano_coef = 16'd0;
            endcase
            3'd3: case (idx) // Fa
                5'd0: piano_coef = 16'd26979;
                5'd1: piano_coef = 16'd2636;
                5'd2: piano_coef = 16'd1598;
                5'd3: piano_coef = 16'd1064;
                5'd4: piano_coef = 16'd423;
                5'd5: piano_coef = 16'd45;
                5'd6: piano_coef = 16'd13;
                5'd7: piano_coef = 16'd4;
                5'd8: piano_coef = 16'd3;
                5'd9: piano_coef = 16'd1;
                5'd10: piano_coef = 16'd0;
                5'd11: piano_coef = 16'd1;
                5'd12: piano_coef = 16'd0;
                5'd13: piano_coef = 16'd0;
                5'd14: piano_coef = 16'd1;
                5'd15: piano_coef = 16'd0;
                default: piano_coef = 16'd0;
            endcase
            3'd4: case (idx) // Sol
                5'd0: piano_coef = 16'd24262;
                5'd1: piano_coef = 16'd2018;
                5'd2: piano_coef = 16'd2861;
                5'd3: piano_coef = 16'd3233;
                5'd4: piano_coef = 16'd281;
                5'd5: piano_coef = 16'd90;
                5'd6: piano_coef = 16'd13;
                5'd7: piano_coef = 16'd5;
                5'd8: piano_coef = 16'd2;
                5'd9: piano_coef = 16'd1;
                5'd10: piano_coef = 16'd0;
                5'd11: piano_coef = 16'd0;
                5'd12: piano_coef = 16'd0;
                5'd13: piano_coef = 16'd0;
                5'd14: piano_coef = 16'd0;
                5'd15: piano_coef = 16'd0;
                default: piano_coef = 16'd0;
            endcase
            3'd5: case (idx) // La
                5'd0: piano_coef = 16'd10346;
                5'd1: piano_coef = 16'd2727;
                5'd2: piano_coef = 16'd14688;
                5'd3: piano_coef = 16'd4127;
                5'd4: piano_coef = 16'd754;
                5'd5: piano_coef = 16'd48;
                5'd6: piano_coef = 16'd55;
                5'd7: piano_coef = 16'd17;
                5'd8: piano_coef = 16'd2;
                5'd9: piano_coef = 16'd1;
                5'd10: piano_coef = 16'd0;
                5'd11: piano_coef = 16'd1;
                5'd12: piano_coef = 16'd0;
                5'd13: piano_coef = 16'd0;
                5'd14: piano_coef = 16'd1;
                5'd15: piano_coef = 16'd0;
                default: piano_coef = 16'd0;
            endcase
            3'd6: case (idx) // Si
                5'd0: piano_coef = 16'd15009;
                5'd1: piano_coef = 16'd10350;
                5'd2: piano_coef = 16'd2899;
                5'd3: piano_coef = 16'd4363;
                5'd4: piano_coef = 16'd41;
                5'd5: piano_coef = 16'd82;
                5'd6: piano_coef = 16'd8;
                5'd7: piano_coef = 16'd11;
                5'd8: piano_coef = 16'd2;
                5'd9: piano_coef = 16'd1;
                5'd10: piano_coef = 16'd0;
                5'd11: piano_coef = 16'd0;
                5'd12: piano_coef = 16'd1;
                5'd13: piano_coef = 16'd0;
                5'd14: piano_coef = 16'd0;
                5'd15: piano_coef = 16'd0;
                default: piano_coef = 16'd0;
            endcase
            default: piano_coef = 16'd0;
        endcase
    end
endfunction
