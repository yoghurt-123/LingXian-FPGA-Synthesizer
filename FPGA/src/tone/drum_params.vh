// Drum engine fixed-point parameters (derived from experiments/drum_model fits).
// Fs = 52500000/1088 = 48253.676 Hz. Phase 32b, amp Q24, decay code = round(2^24*(1-exp(-1/(Fs*tau)))).
// Noise bands: 1-pole HP + 1-pole LP, Q16 coefficients. A_next = A - ((A*code)>>24).
// Kick: pitch f0=45Hz -> tail 27Hz (delta *= RP each sample), mode tau=0.22s;
localparam [31:0] K_STEP0   = 32'd5607509;
localparam [31:0] K_STEPT   = 32'd3916356;
localparam [23:0] K_RP      = 24'd16774898;  // pitch delta multiplier
localparam [23:0] K_MODECODE= 24'd993;
localparam [23:0] K_CLICKCODE=24'd172946;
localparam [23:0] K_N1CODE  = 24'd1402;
localparam [15:0] K_CLICK_AHP=54827, K_CLICK_BLP=35532;
localparam [15:0] K_N1_AHP=64694, K_N1_BLP=2511;
localparam [23:0] K_MODAMP=24'd10066330, K_CLICKAMP=24'd15099494, K_N1AMP=24'd3690987;
// Snare: mode 180Hz tau=0.031s; bands 1-2k,2.5-4k,5-8k.
localparam [31:0] S_STEP    = 32'd16021455;
localparam [23:0] S_MODECODE=24'd11212;
localparam [15:0] S_N1_AHP=57986, S_N1_BLP=15026;
localparam [15:0] S_N2_AHP=49441, S_N2_BLP=26606;
localparam [15:0] S_N3_AHP=39693, S_N3_BLP=42411;
localparam [23:0] S_N1CODE=24'd7557, S_N2CODE=24'd7242, S_N3CODE=24'd8276;
localparam [23:0] S_MODEAMP=24'd4613734, S_N1AMP=24'd1000000, S_N2AMP=24'd550000, S_N3AMP=24'd320000;
// Closed hat: bands 1.5-4k,4-8k,8-16k.
localparam [15:0] H_N1_AHP=54827, H_N1_BLP=26606;
localparam [15:0] H_N2_AHP=43092, H_N2_BLP=42411;
localparam [15:0] H_N3_AHP=32099, H_N3_BLP=57376;
localparam [23:0] H_N1CODE=24'd6685, H_N2CODE=24'd6952, H_N3CODE=24'd10533;
localparam [23:0] H_N1AMP=24'd720000, H_N2AMP=24'd780000, H_N3AMP=24'd1000000;
// Multi-partial body (guitar-style additive): 2x tau0.10, 3x tau0.05
localparam [23:0] K_MOD2CODE=24'd3477; localparam [23:0] K_MOD2AMP=24'd4194304;
localparam [23:0] K_MOD3CODE=24'd6952; localparam [23:0] K_MOD3AMP=24'd2013265;
