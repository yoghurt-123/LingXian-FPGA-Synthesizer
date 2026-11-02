`ifndef SIX_DRUM_DEFS_VH
`define SIX_DRUM_DEFS_VH

// Frozen shared ROM layout (word offsets).
localparam [12:0] CR_BASE = 13'd0;
localparam [12:0] HO_BASE = 13'd2006;
localparam [12:0] TM_BASE = 13'd2470;
localparam [12:0] TH_BASE = 13'd2747;
localparam [12:0] TL_BASE = 13'd3034;
localparam [12:0] RI_BASE = 13'd3340;

localparam integer CR_C = 48;
localparam integer CR_K = 39;
localparam integer CR_N = 144939;
localparam integer CR_MODAL = 2005;
localparam integer HO_C = 20;
localparam integer HO_K = 18;
localparam integer HO_N = 28923;
localparam integer HO_MODAL = 423;
localparam integer RI_C = 28;
localparam integer RI_K = 23;
localparam integer RI_N = 144805;
localparam integer RI_MODAL = 725;

localparam integer MODE_TOTAL = 96;

function [15:0] ima_step;
    input [6:0] idx;
    begin
        case (idx)
        7'd0: ima_step=16'd7;       7'd1: ima_step=16'd8;
        7'd2: ima_step=16'd9;       7'd3: ima_step=16'd10;
        7'd4: ima_step=16'd11;      7'd5: ima_step=16'd12;
        7'd6: ima_step=16'd13;      7'd7: ima_step=16'd14;
        7'd8: ima_step=16'd16;      7'd9: ima_step=16'd17;
        7'd10: ima_step=16'd19;     7'd11: ima_step=16'd21;
        7'd12: ima_step=16'd23;     7'd13: ima_step=16'd25;
        7'd14: ima_step=16'd28;     7'd15: ima_step=16'd31;
        7'd16: ima_step=16'd34;     7'd17: ima_step=16'd37;
        7'd18: ima_step=16'd41;     7'd19: ima_step=16'd45;
        7'd20: ima_step=16'd50;     7'd21: ima_step=16'd55;
        7'd22: ima_step=16'd60;     7'd23: ima_step=16'd66;
        7'd24: ima_step=16'd73;     7'd25: ima_step=16'd80;
        7'd26: ima_step=16'd88;     7'd27: ima_step=16'd97;
        7'd28: ima_step=16'd107;    7'd29: ima_step=16'd118;
        7'd30: ima_step=16'd130;    7'd31: ima_step=16'd143;
        7'd32: ima_step=16'd157;    7'd33: ima_step=16'd173;
        7'd34: ima_step=16'd190;    7'd35: ima_step=16'd209;
        7'd36: ima_step=16'd230;    7'd37: ima_step=16'd253;
        7'd38: ima_step=16'd279;    7'd39: ima_step=16'd307;
        7'd40: ima_step=16'd337;    7'd41: ima_step=16'd371;
        7'd42: ima_step=16'd408;    7'd43: ima_step=16'd449;
        7'd44: ima_step=16'd494;    7'd45: ima_step=16'd544;
        7'd46: ima_step=16'd598;    7'd47: ima_step=16'd658;
        7'd48: ima_step=16'd724;    7'd49: ima_step=16'd796;
        7'd50: ima_step=16'd876;    7'd51: ima_step=16'd963;
        7'd52: ima_step=16'd1060;   7'd53: ima_step=16'd1166;
        7'd54: ima_step=16'd1282;   7'd55: ima_step=16'd1411;
        7'd56: ima_step=16'd1552;   7'd57: ima_step=16'd1707;
        7'd58: ima_step=16'd1878;   7'd59: ima_step=16'd2066;
        7'd60: ima_step=16'd2272;   7'd61: ima_step=16'd2499;
        7'd62: ima_step=16'd2749;   7'd63: ima_step=16'd3024;
        7'd64: ima_step=16'd3327;   7'd65: ima_step=16'd3660;
        7'd66: ima_step=16'd4026;   7'd67: ima_step=16'd4428;
        7'd68: ima_step=16'd4871;   7'd69: ima_step=16'd5358;
        7'd70: ima_step=16'd5894;   7'd71: ima_step=16'd6484;
        7'd72: ima_step=16'd7132;   7'd73: ima_step=16'd7845;
        7'd74: ima_step=16'd8630;   7'd75: ima_step=16'd9493;
        7'd76: ima_step=16'd10442;  7'd77: ima_step=16'd11487;
        7'd78: ima_step=16'd12635;  7'd79: ima_step=16'd13899;
        7'd80: ima_step=16'd15289;  7'd81: ima_step=16'd16818;
        7'd82: ima_step=16'd18500;  7'd83: ima_step=16'd20350;
        7'd84: ima_step=16'd22385;  7'd85: ima_step=16'd24623;
        7'd86: ima_step=16'd27086;  7'd87: ima_step=16'd29794;
        7'd88: ima_step=16'd32767;
        default: ima_step=16'd7;
        endcase
    end
endfunction

function signed [4:0] ima_index_delta;
    input [2:0] code;
    begin
        case (code)
        3'd0: ima_index_delta=-5'sd1;
        3'd1: ima_index_delta=-5'sd1;
        3'd2: ima_index_delta=-5'sd1;
        3'd3: ima_index_delta=-5'sd1;
        3'd4: ima_index_delta=5'sd2;
        3'd5: ima_index_delta=5'sd4;
        3'd6: ima_index_delta=5'sd6;
        default: ima_index_delta=5'sd8;
        endcase
    end
endfunction

function signed [15:0] sat16;
    input signed [31:0] v;
    begin
        if (v > 32'sd32767) sat16 = 16'sd32767;
        else if (v < -32'sd32768) sat16 = -16'sd32768;
        else sat16 = v[15:0];
    end
endfunction

`endif
