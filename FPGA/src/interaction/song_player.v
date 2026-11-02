// 《小星星》单旋律：音符编号0..6对应Do Re Mi Fa Sol La Si。
// 默认每拍0.5秒（120拍/分钟），全曲48拍；仅调度触发，不存音频。
// 按一次开始，再按停止；停止后已有尾音自然结束，再按从头播放。
// stop 为高时立即停止调度（进入吉他模式时使用），释放后不再自动继续。
module song_player #(
    parameter integer BEAT_CLKS = 26250000
)(
    input clk, input rst_n, input toggle, input stop,
    output reg playing,
    output reg [6:0] note_pulse
);
    reg [5:0] note_index;
    reg [31:0] remaining;
    function [2:0] note_at;
        input [5:0] index;
        begin
            case (index)
                0,1,13,28,29,41: note_at=0;
                11,12,20,27,39,40: note_at=1;
                9,10,18,19,25,26,37,38: note_at=2;
                7,8,16,17,23,24,35,36: note_at=3;
                2,3,6,14,15,21,22,30,31,34: note_at=4;
                4,5,32,33: note_at=5;
                default: note_at=0;
            endcase
        end
    endfunction
    function [31:0] duration_at;
        input [5:0] index;
        begin
            // 每句最后一个音延长到两拍，其余音一拍。
            case (index)
                6,13,20,27,34,41: duration_at=BEAT_CLKS*2;
                default: duration_at=BEAT_CLKS;
            endcase
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            playing<=0; note_pulse<=0; note_index<=0; remaining<=0;
        end else begin
            note_pulse<=0; // 每次音符只发一个主时钟周期的触发脉冲。
            if (stop) begin
                playing<=0; remaining<=0;   // 立即停止调度（尾音由发声模块自然衰减）
            end else if (toggle) begin
                if (playing) begin
                    playing<=0; remaining<=0;
                end else begin
                    playing<=1; note_index<=0;
                    note_pulse<=7'b0000001;
                    remaining<=duration_at(0)-1;
                end
            end else if (playing) begin
                if (remaining!=0) remaining<=remaining-1'b1;
                else if (note_index==41) playing<=0;
                else begin
                    note_index<=note_index+1'b1;
                    note_pulse<=7'b0000001 << note_at(note_index+1'b1);
                    remaining<=duration_at(note_index+1'b1)-1;
                end
            end
        end
    end
endmodule