// One shared modal datapath for four piano voices.
// Each voice keeps independent phase, envelope, age, velocity, octave, source,
// release and noise state.  The group scans one voice per 64-cycle slot.
module piano_modal_shared_core #(
 parameter N0=0, parameter N1=1, parameter N2=2, parameter N3=3
)(
 input clk, input rst_n, input sample_tick, input scan_go,
 input [1:0] scan_voice,
 input [3:0] trig, input [3:0] src_usb, input [3:0] src_ble,
 input [15:0] vel, input [7:0] octave,
 input rel_req, input [3:0] rel_usb, input [3:0] rel_ble, input kill,
 output [63:0] data, output [3:0] active, output [15:0] vel_out,
 output [3:0] mem_raddr, output [3:0] mem_waddr, output mem_we,
 output [31:0] mem_wdata, input [31:0] mem_rdata,
 output [1:0] mem_voice_o,
 output [7:0] sine_addr_o, input signed [15:0] sine_value_i
);
 `include "modal_do_params.vh"
 localparam NOTE_SAMPLES=78654, SPLIT_SAMPLES=12063;
 localparam TAIL_ACCEL_START=16889;
 localparam TAIL_ACCEL_SHIFT=6;
 localparam HIGH_ATTACK_SHIFT=1;

 (* syn_ramstyle = "registers" *) reg [31:0] phase[0:3][0:11];
 (* syn_ramstyle = "registers" *) reg phase_c[0:3][0:11];
 reg [16:0] age[0:3];
 reg pending[0:3], playing[0:3], scan_pending[0:3];
 reg pending_usb[0:3], usb_owner[0:3];
 reg pending_ble[0:3], ble_owner[0:3];
 reg [10:0] ext_gain[0:3];
 reg ext_active[0:3];
 reg [3:0] pending_vel[0:3], vel_lat[0:3];
 reg [1:0] pending_octave[0:3], octave_lat[0:3];
 reg [15:0] noise_lfsr[0:3];
 reg signed [8:0] noise_previous[0:3];
 reg signed [15:0] strike[0:3];
 reg signed [15:0] data_r[0:3];
 reg fresh[0:3];

 reg busy;
 reg [5:0] scan;
 reg [1:0] scan_v;
 reg signed [19:0] sum;
 reg signed [47:0] product;
 reg [31:0] amp_wr_r;

 reg [31:0] amp_new_r;
 reg [3:0] amp_wr_addr_r;
 reg amp_we_r;


 wire [3:0] idx = (scan < 6'd48) ? scan[5:2] : 4'd0;
 wire [5:0] scan_n = scan + 6'd1;
 wire [3:0] idx_n = (scan_n < 6'd48) ? scan_n[5:2] : 4'd0;
 wire amp_we = busy && !sample_tick && !kill && (scan < 6'd48) && (scan[1:0] == 2'd1);
 wire [3:0] amp_raddr = (amp_we || amp_we_r) ? 4'd15 : idx_n;

 wire [31:0] step = (scan_v==2'd0) ? partial_step(N0,idx) :
                    (scan_v==2'd1) ? partial_step(N1,idx) :
                    (scan_v==2'd2) ? partial_step(N2,idx) : partial_step(N3,idx);
 wire [15:0] fast = (scan_v==2'd0) ? partial_fast(N0,idx) :
                    (scan_v==2'd1) ? partial_fast(N1,idx) :
                    (scan_v==2'd2) ? partial_fast(N2,idx) : partial_fast(N3,idx);
 wire [15:0] slow = (scan_v==2'd0) ? partial_slow(N0,idx) :
                    (scan_v==2'd1) ? partial_slow(N1,idx) :
                    (scan_v==2'd2) ? partial_slow(N2,idx) : partial_slow(N3,idx);
 wire [15:0] attack_raw0 = (idx>=2) ? (partial_attack(N0,idx)>>HIGH_ATTACK_SHIFT) : partial_attack(N0,idx);
 wire [15:0] attack_raw1 = (idx>=2) ? (partial_attack(N1,idx)>>HIGH_ATTACK_SHIFT) : partial_attack(N1,idx);
 wire [15:0] attack_raw2 = (idx>=2) ? (partial_attack(N2,idx)>>HIGH_ATTACK_SHIFT) : partial_attack(N2,idx);
 wire [15:0] attack_raw3 = (idx>=2) ? (partial_attack(N3,idx)>>HIGH_ATTACK_SHIFT) : partial_attack(N3,idx);
 wire [15:0] attack_raw = (scan_v==2'd0) ? attack_raw0 :
                         (scan_v==2'd1) ? attack_raw1 :
                         (scan_v==2'd2) ? attack_raw2 : attack_raw3;
 wire [15:0] attack_limit = (attack_raw==0) ? 16'd1 : attack_raw;
 wire [31:0] rise0 = (idx>=2) ? (partial_rise(N0,idx)<<HIGH_ATTACK_SHIFT) : partial_rise(N0,idx);
 wire [31:0] rise1 = (idx>=2) ? (partial_rise(N1,idx)<<HIGH_ATTACK_SHIFT) : partial_rise(N1,idx);
 wire [31:0] rise2 = (idx>=2) ? (partial_rise(N2,idx)<<HIGH_ATTACK_SHIFT) : partial_rise(N2,idx);
 wire [31:0] rise3 = (idx>=2) ? (partial_rise(N3,idx)<<HIGH_ATTACK_SHIFT) : partial_rise(N3,idx);
 wire [31:0] rise_step = (scan_v==2'd0) ? rise0 :
                         (scan_v==2'd1) ? rise1 :
                         (scan_v==2'd2) ? rise2 : rise3;
 wire [15:0] level = (scan_v==2'd0) ? partial_level(N0,idx) :
                     (scan_v==2'd1) ? partial_level(N1,idx) :
                     (scan_v==2'd2) ? partial_level(N2,idx) : partial_level(N3,idx);
 wire [31:0] phase_word = phase[scan_v][idx];
 wire phase_carry = phase_c[scan_v][idx];
 wire [16:0] age_sel = age[scan_v];
 wire [16:0] tail_age = (age_sel > TAIL_ACCEL_START) ? age_sel - TAIL_ACCEL_START : 17'd0;
 wire [16:0] extra_decay = tail_age >> TAIL_ACCEL_SHIFT;
 wire [17:0] decay_total = {2'b0,(age_sel < SPLIT_SAMPLES) ? fast : slow} + extra_decay;
 wire [15:0] decay_code = (decay_total > 32767) ? 16'd32767 : decay_total[15:0];
 wire [31:0] amp_old = fresh[scan_v] ? 32'd0 : mem_rdata;
 wire [31:0] level12 = {16'd0, level} << 12;
 wire [31:0] amp_atk = (amp_old + rise_step > level12) ? level12 : (amp_old + rise_step);
 wire [31:0] amp_dec = amp_old - (product >>> 24);
 wire [31:0] amp_new = (age_sel < attack_limit) ? amp_atk : amp_dec;
 wire [16:0] remaining = NOTE_SAMPLES - age_sel;
 wire signed [15:0] release_gain = (remaining < 1024) ? $signed({1'b0, remaining[14:0]}) : 16'sd1024;
 wire [10:0] ext_eff = ext_active[scan_v] ? ext_gain[scan_v] : 11'd1024;
 wire [15:0] rel_eff = (release_gain < {5'b0, ext_eff}) ? release_gain : {5'b0, ext_eff};
 wire [32:0] phase_add = {1'b0, phase_word} + step;
 wire [7:0] sine_addr = (octave_lat[scan_v] == 2'd0) ? {phase_carry, phase_word[31:25]} :
                        (octave_lat[scan_v] == 2'd2) ? phase_word[30:23] : phase_word[31:24];

 reg signed [31:0] operand_a;
 reg signed [15:0] operand_b;
 always @(*) begin
  operand_a = 0;
  operand_b = 0;
  if(scan < 48) begin
   if(scan[1:0] == 0) begin
    operand_a = $signed(amp_old);
    operand_b = $signed(decay_code);
   end else if(scan[1:0] == 2) begin
    operand_a = {{16{sine_value_i[15]}}, sine_value_i};
    operand_b = $signed({1'b0, amp_wr_r[26:12]});
   end
  end else if(scan == 48) begin
   operand_a = sum + strike[scan_v];
   operand_b = rel_eff;
  end
 end
 always @(posedge clk) product <= operand_a * operand_b;

 always @(posedge clk) if(amp_we) begin
  amp_new_r <= amp_new;
  amp_wr_addr_r <= idx;
 end
 always @(posedge clk) amp_we_r <= amp_we;

 // Phase/envelope state machines and the shared scan datapath.
 integer vv, kk;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   busy <= 0; scan <= 0; scan_v <= 0; sum <= 0;
   amp_wr_r <= 0;
   for(vv=0; vv<4; vv=vv+1) begin
    age[vv] <= 0; pending[vv] <= 0; playing[vv] <= 0; scan_pending[vv] <= 0;
    pending_usb[vv] <= 0; usb_owner[vv] <= 0;
    pending_ble[vv] <= 0; ble_owner[vv] <= 0;
    pending_vel[vv] <= 4'd15; vel_lat[vv] <= 4'd15;
    pending_octave[vv] <= 2'd1; octave_lat[vv] <= 2'd1;
    data_r[vv] <= 0; fresh[vv] <= 1;
    for(kk=0; kk<12; kk=kk+1) begin
     phase[vv][kk] <= 0;
     phase_c[vv][kk] <= 0;
    end
   end
  end else begin
   // Trigger is sampled every clock; a later trigger overwrites the pending metadata.
   for(vv=0; vv<4; vv=vv+1) begin
    if(trig[vv] && !ext_active[vv] && !kill) begin
     pending[vv] <= 1;
     case(vv)
      0: begin pending_vel[0] <= vel[3:0]; pending_octave[0] <= octave[1:0]; end
      1: begin pending_vel[1] <= vel[7:4]; pending_octave[1] <= octave[3:2]; end
      2: begin pending_vel[2] <= vel[11:8]; pending_octave[2] <= octave[5:4]; end
      default: begin pending_vel[3] <= vel[15:12]; pending_octave[3] <= octave[7:6]; end
     endcase
     pending_usb[vv] <= src_usb[vv];
     pending_ble[vv] <= src_ble[vv];
    end
   end

   if(kill) begin
    busy <= 0; scan <= 0; sum <= 0;
    for(vv=0; vv<4; vv=vv+1) begin
     pending[vv] <= 0; playing[vv] <= 0; scan_pending[vv] <= 0; data_r[vv] <= 0; fresh[vv] <= 1;
    end
   end else if(sample_tick) begin
    for(vv=0; vv<4; vv=vv+1) begin
      if(rel_req || (rel_usb[vv] && (pending[vv] || playing[vv]) &&
         (pending[vv] ? pending_usb[vv] : usb_owner[vv])) ||
         (rel_ble[vv] && (pending[vv] || playing[vv]) &&
         (pending[vv] ? pending_ble[vv] : ble_owner[vv])) || ext_active[vv]) begin
      pending[vv] <= 0;
      if(ext_active[vv] && ext_gain[vv] <= 11'd2) begin
       playing[vv] <= 0; scan_pending[vv] <= 0; data_r[vv] <= 0;
       if(scan_v == vv) busy <= 0;
      end else if(playing[vv]) begin
       if(age[vv] == NOTE_SAMPLES-1) begin
        playing[vv] <= 0; scan_pending[vv] <= 0; data_r[vv] <= 0;
        if(scan_v == vv) busy <= 0;
       end else begin
        age[vv] <= age[vv] + 1'b1;
        scan_pending[vv] <= 1;
       end
      end else begin
       scan_pending[vv] <= 0; data_r[vv] <= 0;
      end
     end else if(pending[vv] || trig[vv]) begin
      pending[vv] <= 0; playing[vv] <= 1; age[vv] <= 0; scan_pending[vv] <= 1; fresh[vv] <= 1;
      case(vv)
       0: begin
        vel_lat[0] <= trig[0] ? vel[3:0] : pending_vel[0];
         usb_owner[0] <= trig[0] ? src_usb[0] : pending_usb[0];
         ble_owner[0] <= trig[0] ? src_ble[0] : pending_ble[0];
        octave_lat[0] <= trig[0] ? octave[1:0] : pending_octave[0];
        for(kk=0; kk<12; kk=kk+1) begin
         phase[0][kk] <= partial_phase(N0,kk) - partial_step(N0,kk);
         phase_c[0][kk] <= 0;
        end
       end
       1: begin
        vel_lat[1] <= trig[1] ? vel[7:4] : pending_vel[1];
         usb_owner[1] <= trig[1] ? src_usb[1] : pending_usb[1];
         ble_owner[1] <= trig[1] ? src_ble[1] : pending_ble[1];
        octave_lat[1] <= trig[1] ? octave[3:2] : pending_octave[1];
        for(kk=0; kk<12; kk=kk+1) begin
         phase[1][kk] <= partial_phase(N1,kk) - partial_step(N1,kk);
         phase_c[1][kk] <= 0;
        end
       end
       2: begin
        vel_lat[2] <= trig[2] ? vel[11:8] : pending_vel[2];
         usb_owner[2] <= trig[2] ? src_usb[2] : pending_usb[2];
         ble_owner[2] <= trig[2] ? src_ble[2] : pending_ble[2];
        octave_lat[2] <= trig[2] ? octave[5:4] : pending_octave[2];
        for(kk=0; kk<12; kk=kk+1) begin
         phase[2][kk] <= partial_phase(N2,kk) - partial_step(N2,kk);
         phase_c[2][kk] <= 0;
        end
       end
       default: begin
        vel_lat[3] <= trig[3] ? vel[15:12] : pending_vel[3];
         usb_owner[3] <= trig[3] ? src_usb[3] : pending_usb[3];
         ble_owner[3] <= trig[3] ? src_ble[3] : pending_ble[3];
        octave_lat[3] <= trig[3] ? octave[7:6] : pending_octave[3];
        for(kk=0; kk<12; kk=kk+1) begin
         phase[3][kk] <= partial_phase(N3,kk) - partial_step(N3,kk);
         phase_c[3][kk] <= 0;
        end
       end
      endcase
     end else if(playing[vv]) begin
      if(age[vv] == NOTE_SAMPLES-1) begin
       playing[vv] <= 0; scan_pending[vv] <= 0; data_r[vv] <= 0;
       if(scan_v == vv) busy <= 0;
      end else begin
       age[vv] <= age[vv] + 1'b1;
       scan_pending[vv] <= 1;
      end
     end else begin
      scan_pending[vv] <= 0; data_r[vv] <= 0;
     end
    end
   end else if(scan_go && scan_pending[scan_voice]) begin
    scan_pending[scan_voice] <= 0;
    scan_v <= scan_voice;
    busy <= 1; scan <= 0; sum <= 0;

   end else if(busy) begin
    scan <= scan + 1'b1;
    if(scan < 48) case(scan[1:0])
     0: begin
      phase[scan_v][idx] <= phase_add[31:0];
      phase_c[scan_v][idx] <= phase_carry ^ phase_add[32];
     end
     1: begin amp_wr_r <= amp_new; end
     3: sum <= sum + (product >>> 15);
     default:;
    endcase
    else if(scan == 49) begin
     data_r[scan_v] <= product >>> 10;
     busy <= 0;
    end
    if(scan == 46) fresh[scan_v] <= 0;
   end
  end
 end

 // External release counters, one per voice, updated every sample.
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   for(vv=0; vv<4; vv=vv+1) begin ext_gain[vv] <= 11'd1024; ext_active[vv] <= 0; end
  end else begin
   for(vv=0; vv<4; vv=vv+1) begin
    if(kill) begin ext_gain[vv] <= 11'd1024; ext_active[vv] <= 0; end
     else if((rel_req || (rel_usb[vv] && (pending[vv] || playing[vv]) &&
              (pending[vv] ? pending_usb[vv] : usb_owner[vv])) ||
              (rel_ble[vv] && (pending[vv] || playing[vv]) &&
              (pending[vv] ? pending_ble[vv] : ble_owner[vv]))) && !ext_active[vv]) ext_active[vv] <= 1;
    else if(sample_tick && ext_active[vv]) begin
     if(ext_gain[vv] <= 11'd2) begin ext_gain[vv] <= 11'd1024; ext_active[vv] <= 0; end
     else ext_gain[vv] <= ext_gain[vv] - 1'b1;
    end
   end
  end
 end

 // Noise/strike state, one per voice.
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   for(vv=0; vv<4; vv=vv+1) begin noise_lfsr[vv] <= 16'hace1; noise_previous[vv] <= 0; strike[vv] <= 0; end
  end else if(sample_tick) begin
   for(vv=0; vv<4; vv=vv+1) begin
    noise_lfsr[vv] <= {noise_lfsr[vv][14:0], noise_lfsr[vv][15]^noise_lfsr[vv][13]^noise_lfsr[vv][12]^noise_lfsr[vv][10]};
    noise_previous[vv] <= $signed({noise_lfsr[vv][7], noise_lfsr[vv][7:0]});
    if(playing[vv] && age[vv] < 256)
     strike[vv] <= ($signed({noise_lfsr[vv][7], noise_lfsr[vv][7:0]}) - noise_previous[vv]) >>> (age[vv][7:6] + 1);
    else strike[vv] <= 0;
   end
  end
 end

 assign mem_raddr = amp_raddr;
 assign mem_waddr = amp_wr_addr_r;
 assign mem_we = amp_we_r && !kill;
 assign mem_wdata = amp_new_r;
 assign mem_voice_o = scan_v;
 assign sine_addr_o = sine_addr;
 assign active = {pending[3]||playing[3], pending[2]||playing[2], pending[1]||playing[1], pending[0]||playing[0]};
 assign vel_out = {vel_lat[3], vel_lat[2], vel_lat[1], vel_lat[0]};
 assign data = {data_r[3], data_r[2], data_r[1], data_r[0]};
endmodule





