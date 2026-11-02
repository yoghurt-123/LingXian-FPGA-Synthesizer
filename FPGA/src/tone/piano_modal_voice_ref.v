// 【仿真专用·不参与综合】稳定版(2026-10-16 17:20:28位流)的piano_modal_voice，原样复制仅改模块名。
// 用途：力度轮验证满力度(vel=15)输出与稳定版逐样本一致（TB中与新版声部同触发并逐拍比对）。
// 低存储钢琴音：十二分音独立包络，加微弱短敲击，无录音ROM和软核。
// 每个采样分50拍计算，共用一个正弦表及一组乘法运算通路。
// NOTE_SEL选择音名：0=Do（KEY1原参数），1=Re（本次新增）。
module piano_modal_voice_ref #(
 parameter NOTE_SEL=0 // 0=Do 1=Re
)(
 input clk,input rst_n,input sample_tick,input trigger,
 input rel_req,          // ★Space钢琴制音：外部释放请求（单拍，内部锁存后按采样递减）
 input kill,             // ★Esc全局清理：输出已静音后的强制终止（电平）
 output active,output reg signed [15:0] data
);
 `include "modal_do_params.vh"
 localparam NOTE_SAMPLES=78654, SPLIT_SAMPLES=12063;
 // ===== KEY1听感调整区：只改这里，频率及KEY8不受影响 =====
 // 16889个采样约0.35秒；减小此值，尾音更早开始加速衰减。
 localparam TAIL_ACCEL_START=16889;
 // 6为当前值；5衰减更快、尾音更轻；7衰减更慢、尾音更长。
 localparam TAIL_ACCEL_SHIFT=6;
 // 高次分音起音加速：1为起音时间减半，0恢复原版；建议只取0或1。
 // 只影响H3~H12起音速度，不提高峰值，也不改变音高。
 localparam HIGH_ATTACK_SHIFT=1;
 // =====================================================
 reg [31:0] phase[0:11];
 reg [31:0] amplitude[0:11]; // PCM幅度乘4096，保留衰减小数
 reg [16:0] age;
 reg pending,playing,busy;
 reg [5:0] scan;
 reg signed [19:0] sum;
 wire [3:0] idx=(scan<48)?scan[5:2]:4'd0;
 // ★正弦表改为同步读（BSRAM：地址当拍采样、数据下一拍输出）。相位在一组 4 拍内不变，
 //   直接用相位高 8 位作地址时，q=2 读到的正是"q=0 更新后的相位"对应的数据，音色与旧组合表逐点一致。
 wire signed [15:0] sine_value;
 sine_lut u_sine(.clk(clk),.addr(phase[idx][31:24]),.data(sine_value));
 // ★幅度读改写流水：amp_rd_r 提前一拍寄存"下一拍(idx_n)的幅度"（该幅度组内不变），
 //   q0 衰减乘、q1 写回算式都改用它，读出值与原直接读逐位一致；
 //   amp_wr_r 在 q1 与写口同拍保存新值，q2 输出乘积用它替代原"写后读出的新值"，逐位一致。
 wire [5:0] scan_n = scan + 6'd1;
 wire [3:0] idx_n = (scan_n < 6'd48) ? scan_n[5:2] : 4'd0;
 reg [31:0] amp_rd_r, amp_wr_r;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) amp_rd_r<=32'd0;
  else amp_rd_r<=amplitude[idx_n];
 end
 reg signed [31:0] operand_a;
 reg signed [15:0] operand_b;
 reg signed [47:0] product;
 // 随音龄增加附加衰减率，而非固定线性减去音量。
 wire [16:0] tail_age=(age>TAIL_ACCEL_START)?age-TAIL_ACCEL_START:17'd0;
 wire [16:0] extra_decay=tail_age >> TAIL_ACCEL_SHIFT;
 wire [17:0] decay_total={2'b0,(age<SPLIT_SAMPLES?partial_fast(NOTE_SEL,idx):partial_slow(NOTE_SEL,idx))}+extra_decay;
 // 保证乘法系数为正，防止误调参数后变为负数而放大包络。
 wire [15:0] decay_code=(decay_total>32767)?16'd32767:decay_total[15:0];
 wire [15:0] attack_raw=(idx>=2)?(partial_attack(NOTE_SEL,idx)>>HIGH_ATTACK_SHIFT):partial_attack(NOTE_SEL,idx);
 wire [15:0] attack_limit=(attack_raw==0)?16'd1:attack_raw;
 wire [31:0] rise_step=(idx>=2)?(partial_rise(NOTE_SEL,idx)<<HIGH_ATTACK_SHIFT):partial_rise(NOTE_SEL,idx);
 // 最后1024个采样平滑归零，约21ms，避免硬截断尾音。
 wire [16:0] remaining=NOTE_SAMPLES-age;
 wire signed [15:0] release_gain=(remaining<1024)?$signed({1'b0,remaining[14:0]}):16'sd1024;
 // ★外部释放（Space钢琴制音）：rel_req 锁存后每采样递减，约1024采样（21.2ms）到零后清声部；
 //   有效释放增益 = min(自然末尾release_gain, 外部释放gain)，复用 scan==48 的输出乘法阶段，
 //   不新增宽乘法器；重复请求不重置增益、不动音龄/相位；无事件时与原PCM逐样本一致。
 reg [10:0] ext_gain;     // 1024=满幅；释放中从1024递减
 reg ext_active;
 wire [10:0] ext_eff = ext_active ? ext_gain : 11'd1024;
 wire [15:0] rel_eff = (release_gain < {5'b0,ext_eff}) ? release_gain : {5'b0,ext_eff};
 reg [15:0] noise_lfsr;
 reg signed [8:0] noise_previous;
 wire signed [8:0] noise_now=$signed({noise_lfsr[7],noise_lfsr[7:0]});
 wire signed [9:0] noise_difference=noise_now-noise_previous;
 reg signed [15:0] strike;
 integer k;
 assign active=pending||playing;
 // 用差分噪声模拟轻微敲击，不读取录音；约5.3ms内分四档消失。
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin noise_lfsr<=16'hace1;noise_previous<=0;strike<=0;end
  else if(sample_tick)begin
   noise_lfsr<={noise_lfsr[14:0],noise_lfsr[15]^noise_lfsr[13]^noise_lfsr[12]^noise_lfsr[10]};
   noise_previous<=noise_now;
   if(playing && age<256)strike<=noise_difference >>> (age[7:6]+1);
   else strike<=0;
  end
 end
 always @* begin
  operand_a=0;operand_b=0;
  if(scan<48)begin
   if(scan[1:0]==0)begin
    operand_a=$signed(amp_rd_r);
    operand_b=$signed(decay_code);
   end else if(scan[1:0]==2)begin
    operand_a={{16{sine_value[15]}},sine_value};
    operand_b=$signed({1'b0,amp_wr_r[26:12]});
   end
  end else if(scan==48)begin operand_a=sum+strike;operand_b=rel_eff;end
 end
 always @(posedge clk) product<=operand_a*operand_b;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   age<=0;pending<=0;playing<=0;busy<=0;scan<=0;sum<=0;data<=0;amp_wr_r<=32'd0;
   for(k=0;k<12;k=k+1)begin phase[k]<=0;amplitude[k]<=0;end
 end else begin
   if(trigger && !ext_active && !kill)pending<=1;   // 释放/清理期间拒绝新触发
   if(kill)begin
    pending<=0;playing<=0;busy<=0;data<=0;
   end else if(sample_tick)begin
    if(rel_req||ext_active)begin
     pending<=0;                                    // 释放优先：同拍触发丢弃
     if(ext_active && ext_gain<=11'd2)begin playing<=0;busy<=0;data<=0;end   // 释放完成：清声部
     else if(playing)begin
      if(age==NOTE_SAMPLES-1)begin playing<=0;busy<=0;data<=0;end
      else begin age<=age+1'b1;busy<=1;scan<=0;sum<=0;end
     end else begin busy<=0;data<=0;end
    end else if(pending||trigger)begin
     pending<=0;playing<=1;age<=0;busy<=1;scan<=0;sum<=0;
     for(k=0;k<12;k=k+1)begin
      phase[k]<=partial_phase(NOTE_SEL,k)-partial_step(NOTE_SEL,k);amplitude[k]<=0;
     end
    end else if(playing)begin
     if(age==NOTE_SAMPLES-1)begin playing<=0;busy<=0;data<=0;end
     else begin age<=age+1'b1;busy<=1;scan<=0;sum<=0;end
    end else data<=0;
   end else if(busy)begin
    scan<=scan+1'b1;
    if(scan<48)case(scan[1:0])
     0:phase[idx]<=phase[idx]+partial_step(NOTE_SEL,idx);
     1:begin
      if(age<attack_limit)begin
       if(amp_rd_r+rise_step>({16'd0,partial_level(NOTE_SEL,idx)}<<12))begin
        amplitude[idx]<=({16'd0,partial_level(NOTE_SEL,idx)}<<12);
        amp_wr_r<=({16'd0,partial_level(NOTE_SEL,idx)}<<12);
       end else begin
        amplitude[idx]<=amp_rd_r+rise_step;
        amp_wr_r<=amp_rd_r+rise_step;
       end
      end else begin
       amplitude[idx]<=amp_rd_r-(product>>24);
       amp_wr_r<=amp_rd_r-(product>>24);
      end
     end
     3:sum<=sum+(product>>>15);
     default:;
    endcase
     else if(scan==49)begin
      data<=product>>>10;busy<=0;
     end
    end
   end
 end
 // 外部释放计数：rel_req启动（已在释放中不重置、不抬增益）；每采样递减；到零由主状态机清声部
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ext_gain<=11'd1024;ext_active<=1'b0;end
  else if(kill)begin ext_gain<=11'd1024;ext_active<=1'b0;end
  else if(rel_req && !ext_active)ext_active<=1'b1;
  else if(sample_tick && ext_active)begin
   if(ext_gain<=11'd2)begin ext_gain<=11'd1024;ext_active<=1'b0;end
   else ext_gain<=ext_gain-1'b1;
  end
 end
endmodule

