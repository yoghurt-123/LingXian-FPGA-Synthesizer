// 低存储钢琴音：十二分音独立包络，加微弱短敲击，无录音ROM和软核。
// 每个采样分50拍计算，共用一个正弦表及一组乘法运算通路。
// NOTE_SEL选择音名：0=Do（KEY1原参数），1=Re（本次新增）。
// ★2026-10-18 Stage1：幅度12×32改为块RAM（1读1写、同步读延迟1拍，与原"异步读+寄存"逐拍一致）；
//   起音不整数组清零，改用fresh首扫描（各分音首次计算时有效旧幅度=0，按原公式写回）；
//   kill/reset只清状态与事务，不依赖RAM物理内容；amp_wr_r新幅度旁路保留，q2不读同址RAM。
module piano_modal_voice #(
 parameter NOTE_SEL=0 // 0=Do 1=Re
)(
 input clk,input rst_n,input sample_tick,input trigger,
 input src_usb,          // 1=USB trigger, 0=TTP trigger (top gives touch priority on same cycle)
 input [3:0] vel,        // ★USB手动力度码（0..15）；触摸/歌曲等非USB路径由顶层送15
 input [1:0] octave,     // ★USB钢琴八度（0=低 1=原 2=高）；非USB路径由顶层送1（原八度）
 input rel_req,          // ★Space钢琴制音：外部释放请求（单拍，内部锁存后按采样递减）
 input rel_usb,          // USB pedal release: only when this voice is USB-owned
 input kill,             // ★Esc全局清理：输出已静音后的强制终止（电平）
 output active,output reg signed [15:0] data,
 output [3:0] vel_out    // ★当前活动音符锁存的力度（供顶层输出级缩放；声部内部保持原满幅结构）
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
 // ★幅度存储RAM化：地址0..11有效，12..15留作写拍哑地址（避免跨口同址读）
 (* syn_ramstyle = "block_ram" *) reg [31:0] amplitude[0:15];
 reg [31:0] amp_rd_r;             // RAM读出寄存（同步读，1拍延迟）
 reg [31:0] amp_wr_r;             // q1写回的新幅度旁路（供q2输出乘积）
 reg [31:0] amp_new_r;            // q1寄存候选幅度，q2再写RAM（切断RAM读出->加法->写回长路径）
 reg [3:0] amp_wr_addr_r;
 reg amp_we_r;
 reg fresh;                       // 首扫描标志：有效旧幅度强制为0
 reg [16:0] age;
 reg pending,playing,busy;
 reg pending_usb;                  // source of the pending trigger: 1=USB
 reg usb_owner;                    // source of the currently sounding note: 1=USB
 reg [5:0] scan;
 reg signed [19:0] sum;
 wire [3:0] idx=(scan<48)?scan[5:2]:4'd0;
 // ★正弦表改为同步读（BSRAM：地址当拍采样、数据下一拍输出）。相位在一组 4 拍内不变，
 //   直接用相位高 8 位作地址时，q=2 读到的正是"q=0 更新后的相位"对应的数据，音色与旧组合表逐点一致。
 wire signed [15:0] sine_value;
 // ★幅度读改写流水：amp_rd_r 提前一拍寄存"下一拍(idx_n)的幅度"（该幅度组内不变），
 //   q0 衰减乘、q1 写回算式都改用它；amp_wr_r 在 q1 与写口同拍保存新值，q2 输出乘积用它。
 //   RAM写拍（amp_we）读端口用哑地址15，避免同址跨口读写；该拍读出的数据本就不被使用（下拍被覆盖）。
 wire [5:0] scan_n = scan + 6'd1;
 wire [3:0] idx_n = (scan_n < 6'd48) ? scan_n[5:2] : 4'd0;
 wire amp_we = busy && !sample_tick && !kill && (scan < 6'd48) && (scan[1:0] == 2'd1);
 // q2写RAM时读口也用哑地址，避免同址跨口读写冲突。
 wire [3:0] amp_raddr = (amp_we || amp_we_r) ? 4'd15 : idx_n;
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
 // ★幅度旧值（首扫描为0）与新值（原公式）：q0读取、q1写回都用它，不依赖RAM残留内容
 wire [31:0] amp_old = fresh ? 32'd0 : amp_rd_r;
 wire [31:0] level12 = {16'd0, partial_level(NOTE_SEL,idx)} << 12;
 wire [31:0] amp_atk = (amp_old + rise_step > level12) ? level12 : (amp_old + rise_step);
 wire [31:0] amp_dec = amp_old - (product >>> 24);
 wire [31:0] amp_new = (age < attack_limit) ? amp_atk : amp_dec;
 // 原公式不变，只在q1寄存、q2写回：RAM读出->fresh选择->加法/比较->写口拆成两级。
 always @(posedge clk) if(amp_we) begin
  amp_new_r <= amp_new;
  amp_wr_addr_r <= idx;
 end
 always @(posedge clk) amp_we_r <= amp_we;
 always @(posedge clk) if(amp_we_r && !kill) amplitude[amp_wr_addr_r] <= amp_new_r;
 always @(posedge clk) amp_rd_r <= amplitude[amp_raddr];
 // 最后1024个采样平滑归零，约21ms，避免硬截断尾音。
 wire [16:0] remaining=NOTE_SAMPLES-age;
 wire signed [15:0] release_gain=(remaining<1024)?$signed({1'b0,remaining[14:0]}):16'sd1024;
 // ★外部释放（Space钢琴制音）：rel_req 锁存后每采样递减，约1024采样（21.2ms）到零后清声部；
 //   有效释放增益 = min(自然末尾release_gain, 外部释放gain)，复用 scan==48 的输出乘法阶段，
 //   不新增宽乘法器；重复请求不重置增益、不动音龄/相位；无事件时与原PCM逐样本一致。
 reg [10:0] ext_gain;     // 1024=满幅；释放中从1024递减
 reg ext_active;
 // USB踏板释放只在声部当前归属USB时生效；TTP触发会覆盖owner，USB松键不会杀触摸音。
 wire rel_usb_own = rel_usb && (pending || playing) && (pending ? pending_usb : usb_owner);
 wire rel_all = rel_req || rel_usb_own;
 wire [10:0] ext_eff = ext_active ? ext_gain : 11'd1024;
 wire [15:0] rel_eff = (release_gain < {5'b0,ext_eff}) ? release_gain : {5'b0,ext_eff};
 // ★力度（顶层输出级缩放版）：声部内部结构与原版逐位一致；仅锁存每次起音的力度并输出，
 //   顶层按 (vel+1)/16 缩放该声部PCM（满力度=恒等）。pending_vel为等待中请求的力度（最后一次请求覆盖）。
 reg [3:0] pending_vel;
 reg [3:0] vel_lat;
 assign vel_out = vel_lat;
 // ★八度：pending_octave随最后一次触发请求覆盖（与力度一起），octave_lat在真正起音时锁存；
 //   相位累加始终使用原步进（不新增移位器/乘法器），另加1位扩展位构成33位相位；
 //   正弦地址按锁存音区从33位相位中取位段（低=÷2、原=×1、高=×2），保证原八度逐位等价。
 reg [1:0] pending_octave;
 reg [1:0] octave_lat;
 reg phase_c[0:11];               // 33位相位最高位（仅低八度地址使用）
 wire [1:0] oct_start = trigger ? octave : pending_octave;
 wire [32:0] phase_add = {1'b0, phase[idx]} + partial_step(NOTE_SEL, idx);   // q0累加（33位含进位）
 // 低八度：{扩展位,相位[31:25]}（等效频率÷2）；高八度：相位[30:23]（×2）；原八度：相位[31:24]。
 wire [7:0] sine_addr = (octave_lat==2'd0) ? {phase_c[idx], phase[idx][31:25]} :
                        (octave_lat==2'd2) ? phase[idx][30:23] : phase[idx][31:24];
 sine_lut u_sine(.clk(clk),.addr(sine_addr),.data(sine_value));
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
    operand_a=$signed(amp_old);
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
   age<=0;pending<=0;playing<=0;busy<=0;scan<=0;sum<=0;data<=0;amp_wr_r<=32'd0;pending_vel<=4'd15;pending_usb<=1'b0;usb_owner<=1'b0;vel_lat<=4'd15;
    pending_octave<=2'd1;octave_lat<=2'd1;fresh<=1'b1;
    for(k=0;k<12;k=k+1)begin phase[k]<=0;phase_c[k]<=1'b0;end
 end else begin
   if(trigger && !ext_active && !kill)begin pending<=1;pending_vel<=vel;pending_octave<=octave;pending_usb<=src_usb;end   // 力度/八度随最后一次请求（含同拍）更新
   if(kill)begin
    pending<=0;playing<=0;busy<=0;data<=0;fresh<=1'b1;
   end else if(sample_tick)begin
    if(rel_all||ext_active)begin
     pending<=0;                                    // 释放优先：同拍触发丢弃
     if(ext_active && ext_gain<=11'd2)begin playing<=0;busy<=0;data<=0;end   // 释放完成：清声部
     else if(playing)begin
      if(age==NOTE_SAMPLES-1)begin playing<=0;busy<=0;data<=0;end
      else begin age<=age+1'b1;busy<=1;scan<=0;sum<=0;end
     end else begin busy<=0;data<=0;end
     end else if(pending||trigger)begin
      pending<=0;playing<=1;age<=0;busy<=1;scan<=0;sum<=0;fresh<=1'b1;   // 起音：首扫描旧幅度按0
      vel_lat<= trigger ? vel : pending_vel;         // 起音锁存力度：同拍trigger用当拍元数据，等待请求用已锁存值
      usb_owner<= trigger ? src_usb : pending_usb;   // 起音锁存来源：后触发覆盖
      octave_lat<= oct_start;                        // 起音锁存音区（同拍trigger用当拍元数据）
      for(k=0;k<12;k=k+1)begin
       phase[k]<=partial_phase(NOTE_SEL,k)-partial_step(NOTE_SEL,k);phase_c[k]<=1'b0;  // 原步进，原八度逐位等价
      end
    end else if(playing)begin
     if(age==NOTE_SAMPLES-1)begin playing<=0;busy<=0;data<=0;end
     else begin age<=age+1'b1;busy<=1;scan<=0;sum<=0;end
    end else data<=0;
   end else if(busy)begin
    scan<=scan+1'b1;
    if(scan<48)case(scan[1:0])
     0:begin phase[idx]<=phase_add[31:0];phase_c[idx]<=phase_c[idx]^phase_add[32];end   // 原步进累加+扩展进位
     1:begin amp_wr_r<=amp_new; end                                                    // 幅度已由独立RAM写口按原公式写回
     3:sum<=sum+(product>>>15);
     default:;
    endcase
     else if(scan==49)begin
      data<=product>>>10;busy<=0;   // 声部内部保持原结构；力度由顶层输出级缩放
     end
     if(scan==6'd46) fresh<=1'b0;    // 首扫描12个分音全部写回后撤去fresh
    end
   end
 end
 // 外部释放计数：rel_req启动（已在释放中不重置、不抬增益）；每采样递减；到零由主状态机清声部
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ext_gain<=11'd1024;ext_active<=1'b0;end
  else if(kill)begin ext_gain<=11'd1024;ext_active<=1'b0;end
  else if(rel_all && !ext_active)ext_active<=1'b1;
  else if(sample_tick && ext_active)begin
   if(ext_gain<=11'd2)begin ext_gain<=11'd1024;ext_active<=1'b0;end
   else ext_gain<=ext_gain-1'b1;
  end
 end
endmodule
