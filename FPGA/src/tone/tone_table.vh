// 电子琴音色谐波表（加法合成），16 次谐波。
// 幅度参考 meettechniek.info 加法合成工具的预置波形，并向后扩展到 H16。
// 每个系数是第 n 次谐波的相对幅度，Q15 定点（32768 = 1.0），
// 已按各预置的幅度总和归一化，保证 16 个谐波叠加后不超过 16 位 PCM 满幅。
// 相位统一取正弦；网站预置里脉冲/小提琴个别谐波带相位差，对稳态听感影响很小。
//
// TONE_SEL 选择音色，改这一行即可换音色：
//   0 电子琴（默认，16 次谐波全开、基音约 0.30，比 11 次谐波更亮更饱满）
//   1 方波    奇次谐波 1/n，经典 8 位电子音
//   2 锯齿    全谐波 1/n，模拟合成器音色
//   3 脉冲    高次谐波丰富，明亮
//   4 管风琴  八度 + 五度，风琴音色
//   5 梯形    奇次谐波快速衰减，柔和的电子音
//   6 小提琴  网站预置，谐波多但电子感弱
localparam TONE_SEL = 0;

// 当前音色第 idx 次谐波的 Q15 幅度，idx = 0 对应基波 H1，idx = 15 对应 H16。
function [15:0] tone_coef;
    input [4:0] idx;
    begin
        case (TONE_SEL)
            3'd0: case (idx) // 电子琴（明亮）
                5'd0:  tone_coef = 16'd9810;
                5'd1:  tone_coef = 16'd4905;
                5'd2:  tone_coef = 16'd3924;
                5'd3:  tone_coef = 16'd2747;
                5'd4:  tone_coef = 16'd2355;
                5'd5:  tone_coef = 16'd1668;
                5'd6:  tone_coef = 16'd1472;
                5'd7:  tone_coef = 16'd1079;
                5'd8:  tone_coef = 16'd883;
                5'd9:  tone_coef = 16'd785;
                5'd10: tone_coef = 16'd687;
                5'd11: tone_coef = 16'd589;
                5'd12: tone_coef = 16'd540;
                5'd13: tone_coef = 16'd491;
                5'd14: tone_coef = 16'd441;
                5'd15: tone_coef = 16'd392;
                default: tone_coef = 16'd0;
            endcase
            3'd1: case (idx) // 方波
                5'd0:  tone_coef = 16'd16207;
                5'd1:  tone_coef = 16'd0;
                5'd2:  tone_coef = 16'd5402;
                5'd3:  tone_coef = 16'd0;
                5'd4:  tone_coef = 16'd3241;
                5'd5:  tone_coef = 16'd0;
                5'd6:  tone_coef = 16'd2315;
                5'd7:  tone_coef = 16'd0;
                5'd8:  tone_coef = 16'd1801;
                5'd9:  tone_coef = 16'd0;
                5'd10: tone_coef = 16'd1473;
                5'd11: tone_coef = 16'd0;
                5'd12: tone_coef = 16'd1247;
                5'd13: tone_coef = 16'd0;
                5'd14: tone_coef = 16'd1080;
                5'd15: tone_coef = 16'd0;
                default: tone_coef = 16'd0;
            endcase
            3'd2: case (idx) // 锯齿
                5'd0:  tone_coef = 16'd9692;
                5'd1:  tone_coef = 16'd4846;
                5'd2:  tone_coef = 16'd3231;
                5'd3:  tone_coef = 16'd2423;
                5'd4:  tone_coef = 16'd1938;
                5'd5:  tone_coef = 16'd1615;
                5'd6:  tone_coef = 16'd1385;
                5'd7:  tone_coef = 16'd1212;
                5'd8:  tone_coef = 16'd1077;
                5'd9:  tone_coef = 16'd969;
                5'd10: tone_coef = 16'd881;
                5'd11: tone_coef = 16'd808;
                5'd12: tone_coef = 16'd746;
                5'd13: tone_coef = 16'd692;
                5'd14: tone_coef = 16'd646;
                5'd15: tone_coef = 16'd606;
                default: tone_coef = 16'd0;
            endcase
            3'd3: case (idx) // 脉冲
                5'd0:  tone_coef = 16'd5958;
                5'd1:  tone_coef = 16'd5362;
                5'd2:  tone_coef = 16'd4766;
                5'd3:  tone_coef = 16'd4170;
                5'd4:  tone_coef = 16'd3575;
                5'd5:  tone_coef = 16'd2979;
                5'd6:  tone_coef = 16'd2383;
                5'd7:  tone_coef = 16'd1787;
                5'd8:  tone_coef = 16'd1192;
                5'd9:  tone_coef = 16'd596;
                5'd10: tone_coef = 16'd0;
                5'd11: tone_coef = 16'd0;
                5'd12: tone_coef = 16'd0;
                5'd13: tone_coef = 16'd0;
                5'd14: tone_coef = 16'd0;
                5'd15: tone_coef = 16'd0;
                default: tone_coef = 16'd0;
            endcase
            3'd4: case (idx) // 管风琴
                5'd0:  tone_coef = 16'd12506;
                5'd1:  tone_coef = 16'd6253;
                5'd2:  tone_coef = 16'd6253;
                5'd3:  tone_coef = 16'd3752;
                5'd4:  tone_coef = 16'd0;
                5'd5:  tone_coef = 16'd2501;
                5'd6:  tone_coef = 16'd0;
                5'd7:  tone_coef = 16'd1501;
                5'd8:  tone_coef = 16'd0;
                5'd9:  tone_coef = 16'd0;
                5'd10: tone_coef = 16'd0;
                5'd11: tone_coef = 16'd0;
                5'd12: tone_coef = 16'd0;
                5'd13: tone_coef = 16'd0;
                5'd14: tone_coef = 16'd0;
                5'd15: tone_coef = 16'd0;
                default: tone_coef = 16'd0;
            endcase
            3'd5: case (idx) // 梯形
                5'd0:  tone_coef = 16'd19106;
                5'd1:  tone_coef = 16'd0;
                5'd2:  tone_coef = 16'd6042;
                5'd3:  tone_coef = 16'd0;
                5'd4:  tone_coef = 16'd3232;
                5'd5:  tone_coef = 16'd0;
                5'd6:  tone_coef = 16'd1943;
                5'd7:  tone_coef = 16'd0;
                5'd8:  tone_coef = 16'd1154;
                5'd9:  tone_coef = 16'd0;
                5'd10: tone_coef = 16'd635;
                5'd11: tone_coef = 16'd0;
                5'd12: tone_coef = 16'd385;
                5'd13: tone_coef = 16'd0;
                5'd14: tone_coef = 16'd269;
                5'd15: tone_coef = 16'd0;
                default: tone_coef = 16'd0;
            endcase
            3'd6: case (idx) // 小提琴
                5'd0:  tone_coef = 16'd9533;
                5'd1:  tone_coef = 16'd9006;
                5'd2:  tone_coef = 16'd4072;
                5'd3:  tone_coef = 16'd4599;
                5'd4:  tone_coef = 16'd0;
                5'd5:  tone_coef = 16'd3497;
                5'd6:  tone_coef = 16'd383;
                5'd7:  tone_coef = 16'd814;
                5'd8:  tone_coef = 16'd0;
                5'd9:  tone_coef = 16'd862;
                5'd10: tone_coef = 16'd0;
                5'd11: tone_coef = 16'd0;
                5'd12: tone_coef = 16'd0;
                5'd13: tone_coef = 16'd0;
                5'd14: tone_coef = 16'd0;
                5'd15: tone_coef = 16'd0;
                default: tone_coef = 16'd0;
            endcase
            default: tone_coef = 16'd0;
        endcase
    end
endfunction
