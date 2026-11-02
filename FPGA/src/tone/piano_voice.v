// 纯硬件电子琴音色：加法合成 16 次谐波 + 亮度包络 + ADSR 包络，无软核。
// 每个实例用 NOTE_SEL 选择一个音名（Do Re Mi Fa Sol La Si），顶层七个音各用一个
// 实例，互不干扰。全工程只保留一张正弦表，每个采样周期把 16 个谐波分时读出、
// 按谐波表加权相加。谐波幅度取自 88 键钢琴采样的 WAV（见 piano_table.vh），
// 高次谐波随时间衰减（亮度包络）参考 jiyinjiang 电子琴的 FM 指数衰减思路。
module piano_voice #(
    parameter NOTE_SEL = 0 // 0=Do 1=Re 2=Mi 3=Fa 4=Sol 5=La 6=Si
)(
    input clk, input rst_n, input sample_tick, input trigger,
    input rel_req,           // ★Space钢琴制音：外部释放请求（单拍；锁存后从当前包络值线性归零）
    input kill,              // ★Esc全局清理：输出已静音后的强制终止（电平）
    output active, output signed [15:0] data
);
    `include "note_table.vh"
    `include "piano_table.vh"

    // 从十二平均律音律表取本实例音名的基波步进，第 k 次谐波步进为 k 倍。
    localparam [31:0] BASE_STEP =
        (NOTE_SEL == 0) ? NOTE_STEP_C4 :
        (NOTE_SEL == 1) ? NOTE_STEP_D4 :
        (NOTE_SEL == 2) ? NOTE_STEP_E4 :
        (NOTE_SEL == 3) ? NOTE_STEP_F4 :
        (NOTE_SEL == 4) ? NOTE_STEP_G4 :
        (NOTE_SEL == 5) ? NOTE_STEP_A4 : NOTE_STEP_B4;

    localparam [2:0] NOTE_IDX = NOTE_SEL; // 传给钢琴谐波表用

    localparam NH = 16;           // 谐波个数 H1..H16
    localparam SCAN_END = NH + 3; // 分时扫描状态数：1..NH 累加，随后 3 拍混音流水

    // 相位累加器：起音时一起清零，保证每次按键的相位一致。
    reg [31:0] phase [0:NH-1];
    integer k;

    // ADSR 包络状态（状态编号与旧版一致，回归测试沿用）。
    localparam IDLE=3'd0, ATTACK=3'd1, DECAY=3'd2, SUSTAIN=3'd3, RELEASE=3'd4;
    reg [2:0] state;
    reg [15:0] envelope;
    reg pending;
    reg [12:0] sustain_count;

    // 亮度包络：Q15，起音最亮，随后高次谐波按指数衰减，模拟电子琴的亮度衰减。
    reg signed [15:0] bright;

    // 分时扫描流水线。
    reg [4:0] st;
    reg signed [17:0] acc_lo, acc_hi, mixed;

    // ★外部释放（Space钢琴制音）：rel_req锁存后每采样从当前包络值递减（步长=(env>>10)+1，约1024采样到零）；
    //   释放优先于同拍起音；重复请求不抬增益；不重置音龄/相位；无事件时与旧逻辑逐样本一致。
    reg ext_on;
    reg [15:0] ext_step;

    assign active = pending || (state != IDLE);

    // 与 ADSR 状态机启动条件一致：主时钟域捕获的触发，或本采样节拍上的触发；释放中不算起音。
    wire note_start = (pending || trigger) && !ext_on;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k=0;k<NH;k=k+1) phase[k] <= 32'd0;
        end else if (sample_tick) begin
            if (note_start) begin
                for (k=0;k<NH;k=k+1) phase[k] <= 32'd0;
            end else begin
                for (k=0;k<NH;k=k+1) phase[k] <= phase[k] + (BASE_STEP * (k+1));
            end
        end
    end

    // 分时扫描：每拍处理一个谐波，前两个谐波归低次谐波组，其余归高次谐波组。
    wire [4:0] st_next = (st == 5'd0 || st == SCAN_END) ? 5'd0 : st + 5'd1;
    wire [4:0] hidx = (st >= 5'd1 && st <= NH) ? (st - 5'd1) : 5'd0;
    wire [31:0] phase_sel = phase[hidx];
    // 纯时序流水：谐波序号、槽位号各寄存一拍；正弦表已改为同步读（地址当拍采样、数据下一拍输出，
    // 综合映射 BSRAM），因此直接用未寄存相位接表，读出与原“寄存相位+组合表”逐点一致。
    reg [4:0] hidx_r, st_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin hidx_r <= 5'd0; st_r <= 5'd0; end
        else begin hidx_r <= hidx; st_r <= st; end
    end
    wire signed [15:0] lut_data;
    wire signed [15:0] coef = piano_coef(NOTE_IDX, hidx_r);
    // 显式声明 32 位中间结果：否则赋值位宽会先把乘积截成 18 位再右移。
    wire signed [31:0] harm_product = lut_data * coef;
    wire signed [31:0] bright_product = acc_hi * bright;
    wire signed [31:0] env_product = mixed * $signed(envelope);
    wire signed [17:0] contribution = harm_product >>> 15;

    sine_lut u_sine(.clk(clk), .addr(phase_sel[31:24]), .data(lut_data));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= 5'd0; acc_lo <= 0; acc_hi <= 0; mixed <= 0;
        end else if (sample_tick) begin
            st <= 5'd1; acc_lo <= 0; acc_hi <= 0;
        end else begin
            st <= st_next;
            case (st_r)
                5'd1, 5'd2: acc_lo <= acc_lo + contribution;
                5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8, 5'd9, 5'd10,
                5'd11, 5'd12, 5'd13, 5'd14, 5'd15, 5'd16:
                    acc_hi <= acc_hi + contribution;
                5'd17: mixed <= acc_lo + (bright_product >>> 15);
                default: ;
            endcase
        end
    end

    // 亮度包络：每次起音回到最亮，之后每采样乘以 (1 - 2^-13)，
    // 时间常数约 8192 个采样（约 170ms），最低保持约 0.375，避免尾音发闷。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bright <= 16'sd32767;
        else if (sample_tick) begin
            if (note_start) bright <= 16'sd32767;
            else if (bright > 16'sd12288) bright <= bright - (bright >>> 13);
        end
    end

    // 每音约 300ms：起音约 2ms，衰减约 113ms，维持约 100ms，释音约 85ms。
    // 播放中再次按下可重新起音；从当前音量上升，避免强制清零跳变。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state<=IDLE; envelope<=0; pending<=0; sustain_count<=0; ext_on<=0; ext_step<=0; end
        else begin
            if (kill) begin
                // Esc全局清理：输出已为静音后的强制终止
                state<=IDLE; envelope<=0; pending<=0; ext_on<=0;
            end else if (rel_req) begin
                // 释放优先（同拍触发丢弃）；已在释放中不重置、不抬增益
                pending<=0;
                if (!ext_on) begin ext_on<=1'b1; ext_step<=(envelope>>10)+16'd1; end
            end else begin
                if (trigger && !ext_on) pending<=1;
                if (sample_tick) begin
                    if (ext_on) begin
                        if (envelope <= ext_step) begin envelope<=16'd0; state<=IDLE; ext_on<=0; end
                        else envelope<=envelope-ext_step;
                    end else if (pending || trigger) begin
                        pending<=0; state<=ATTACK; sustain_count<=0;
                        if (envelope<=16'd32427) envelope<=envelope+16'd340;
                        else envelope<=32767;
                    end else case (state)
                        IDLE: envelope<=0;
                        ATTACK: if (envelope>=16'd32427) begin envelope<=32767; state<=DECAY; end
                                else envelope<=envelope+16'd340;
                        DECAY: if (envelope<=16'd16387) begin envelope<=16384; sustain_count<=0; state<=SUSTAIN; end
                               else envelope<=envelope-16'd3;
                        SUSTAIN: if (sustain_count==13'd4824) state<=RELEASE;
                                 else sustain_count<=sustain_count+1'b1;
                        RELEASE: if (envelope<=16'd4) begin envelope<=0; state<=IDLE; end
                                 else envelope<=envelope-16'd4;
                        default: begin state<=IDLE; envelope<=0; end
                    endcase
                end
            end
        end
    end

    // 输出级：ADSR 为正数 Q15，和音色采样相乘后恢复为 16 位 PCM。
    reg signed [15:0] voice_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) voice_r <= 0;
        else if (sample_tick) voice_r <= env_product >>> 15;
    end
    assign data = voice_r;
endmodule
