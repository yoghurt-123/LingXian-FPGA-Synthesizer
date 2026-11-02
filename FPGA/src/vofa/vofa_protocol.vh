// Include inside a module. Functions are combinational hardware, not C calls.
// VOFA+ JustFloat: one IEEE754 float, little endian, then 00 00 80 7F.
// Convert signed PCM to its exact floating-point numeric value (-32768..32767).
function [31:0] vofa_pcm_to_float;
    input signed [15:0] pcm;
    reg [15:0] magnitude;
    reg [7:0] exponent;
    reg [31:0] aligned;
    integer bit_pos;
    integer leading;
    begin
        magnitude = pcm[15] ? (~pcm + 16'd1) : pcm;
        leading = 0;
        for (bit_pos=0; bit_pos<16; bit_pos=bit_pos+1)
            if (magnitude[bit_pos]) leading = bit_pos;
        exponent = 127 + leading;
        aligned = {16'd0, magnitude} << (23-leading);
        if (magnitude == 0) vofa_pcm_to_float = 32'd0;
        else vofa_pcm_to_float = {pcm[15], exponent, aligned[22:0]};
    end
endfunction

function [63:0] vofa_make_frame;
    input signed [15:0] pcm;
    begin
        // Shift/send low byte first. The upper word is the JustFloat trailer.
        vofa_make_frame = {32'h7f800000, vofa_pcm_to_float(pcm)};
    end
endfunction
