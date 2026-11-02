// Six shared-ROM drum voices: crash/hat/ride modal + hat/ride noise + 3 toms.
// C/N/M (kick/snare/closed hat) remain in the existing drum_synth3 path.
module six_drum_synth(
    input clk, input rst_n, input sample_tick,
    input [5:0] trig,
    input [3:0] vel,
    input cancel,
    output signed [19:0] pcm20,
    output signed [16:0] hat_pcm17,
    output signed [21:0] pcm22,
    output signed [21:0] hat22,
    output active
);
    wire signed [15:0] m_cr,m_ho,m_ri;
    wire [2:0] m_valid,m_active;
    wire signed [15:0] n_h,n_r;
    wire [1:0] n_valid,n_active;
    wire signed [15:0] t0,t1,t2;
    wire [2:0] t_valid,t_active;

    wire [8:0] state_addr;
    wire state_we;
    wire [31:0] state_wdata,state_rdata;
    wire [12:0] m_addr,n_addr,t_addr,rom_addr;
    wire m_req,n_req,t_req;
    wire v0,v1,v2;
    wire [31:0] rom_data;
    wire [9:0] sine_addr;
    wire signed [15:0] sine_data;

    wire [2:0] modal_trig = {trig[2], trig[1], trig[0]};
    wire [1:0] noise_trig = {trig[2], trig[1]};
    wire [2:0] tom_trig   = {trig[5], trig[4], trig[3]};

    six_drum_rom urom(.clk(clk), .addr(rom_addr), .data(rom_data));
    six_rom_arbiter uarb(
        .clk(clk), .rst_n(rst_n),
        .req0(m_req), .addr0(m_addr),
        .req1(n_req), .addr1(n_addr),
        .req2(t_req), .addr2(t_addr),
        .rom_addr(rom_addr),
        .valid0(v0), .valid1(v1), .valid2(v2));

    six_state_ram ustate(.clk(clk), .we(state_we),
                         .raddr(state_addr), .waddr(state_addr),
                         .wdata(state_wdata), .rdata(state_rdata));
    sine_rom usin(.clk(clk), .addr(sine_addr), .data(sine_data));

    six_modal_engine um(
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick),
        .trig(modal_trig), .vel(vel), .cancel(cancel), .ce(1'b1),
        .pcm_cr(m_cr), .pcm_ho(m_ho), .pcm_ri(m_ri),
        .out_valid(m_valid), .active(m_active),
        .state_addr(state_addr), .state_we(state_we),
        .state_wdata(state_wdata), .state_rdata(state_rdata),
        .rom_req(m_req), .rom_addr(m_addr), .rom_data(rom_data),
        .rom_valid(v0), .sine_addr(sine_addr), .sine_data(sine_data));

    six_noise_engine un(
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick),
        .trig(noise_trig), .cancel(cancel), .rom_valid(v1),
        .pcm_hat(n_h), .pcm_ride(n_r), .out_valid(n_valid),
        .active_o(n_active), .rom_req(n_req), .rom_addr(n_addr),
        .rom_data(rom_data));

    six_tom_engine ut(
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick),
        .trig(tom_trig), .vel(vel), .cancel(cancel),
        .pcm0(t0), .pcm1(t1), .pcm2(t2), .out_valid(t_valid),
        .active_o(t_active), .rom_req(t_req), .rom_addr(t_addr),
        .rom_data(rom_data), .rom_valid(v2));

    wire signed [16:0] hat17 = {{1{m_ho[15]}}, m_ho} + {{1{n_h[15]}}, n_h};

    // Eight signed 16-bit components fit in 20 bits without saturation.
    wire signed [19:0] mix20 =
        {{4{m_cr[15]}}, m_cr} + {{3{hat17[16]}}, hat17} + {{4{m_ri[15]}}, m_ri} +
        {{4{n_r[15]}}, n_r} +
        {{4{t0[15]}}, t0} + {{4{t1[15]}}, t1} + {{4{t2[15]}}, t2};

    assign pcm20 = mix20;
    assign hat_pcm17 = hat17;

    // Fixed post-voice gains: crash x2, open-hat x2, ride x2, toms x1.5.
    // Every operand is explicitly widened to signed 22-bit before shift/add.
    wire signed [21:0] crx  = {{6{m_cr[15]}}, m_cr};
    wire signed [21:0] hax  = {{5{hat17[16]}}, hat17};
    wire signed [21:0] rix  = {{6{m_ri[15]}}, m_ri} + {{6{n_r[15]}}, n_r};
    wire signed [21:0] t0x  = {{6{t0[15]}}, t0};
    wire signed [21:0] t1x  = {{6{t1[15]}}, t1};
    wire signed [21:0] t2x  = {{6{t2[15]}}, t2};
    wire signed [21:0] crg  = crx + (crx >>> 1) + (crx >>> 2);
    wire signed [21:0] hag  = hax + hax;
    wire signed [21:0] rig  = rix + rix;
    wire signed [21:0] t0g  = t0x + (t0x >>> 1);
    wire signed [21:0] t1g  = t1x + (t1x >>> 1);
    wire signed [21:0] t2g  = t2x + (t2x >>> 1);
    assign pcm22 = crg + hag + rig + t0g + t1g + t2g;
    assign hat22 = hag;
    assign active = |m_active | |n_active | |t_active;
endmodule

