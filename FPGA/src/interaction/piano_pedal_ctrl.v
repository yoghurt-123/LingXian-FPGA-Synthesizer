// 可选钢琴踏板/阻尼模式（E）：F7切换，上电关闭。
// 关闭：USB松键不触发外部释放（保持原自然衰减手感，PCM等价）。
// 开启：USB单键松键产生该键释放脉冲（复用声部既有外部释放，release_gain 1024→0/采样，
//       与自然尾音取最小）；右Ctrl按住时延迟释放，右Ctrl松开只释放“已松键”的音；
//       仍按住的音不释放；普通释放期间同音重按由触发路径正常重新起音，并清挂起。
// 只作用于USB手动钢琴来源；触摸来源不在usb_held内，不受影响。
// 左Ctrl专用于吉他掌根闷音，不再参与钢琴踏板，避免并奏时互相影响。
module piano_pedal_ctrl (
    input clk, input rst_n, input sample_tick,
    input f7_held,
    input [15:0] usb_held,
    input pedal_mod,           // 右Ctrl：钢琴踏板延迟释放修饰（与吉他左Ctrl隔离）
    input clear_req,           // Esc/Space/断连：清理挂起状态（不改变当前开关）
    output reg pedal_on,
    output reg [15:0] rel_pulse
);
    reg f7_d;
    reg [15:0] held_d;
    reg [15:0] pending;
    wire [15:0] rel_edge = held_d & ~usb_held;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f7_d <= 1'b0; pedal_on <= 1'b0; held_d <= 16'd0; pending <= 16'd0; rel_pulse <= 16'd0;
        end else begin
            f7_d <= f7_held;
            if (f7_held & ~f7_d) pedal_on <= ~pedal_on;
            if (sample_tick) begin
                held_d <= usb_held;
                rel_pulse <= 16'd0;
                if (clear_req) begin
                    pending <= 16'd0;
                end else if (!pedal_on) begin
                    pending <= 16'd0;              // 关闭：不产生外部释放
                end else if (pedal_mod) begin
                    pending <= (pending | rel_edge) & ~usb_held;   // 挂起已松键；重按即清除
                end else begin
                    rel_pulse <= (pending | rel_edge) & ~usb_held; // 立即释放已松键
                    pending <= 16'd0;
                end
            end
        end
    end
endmodule
