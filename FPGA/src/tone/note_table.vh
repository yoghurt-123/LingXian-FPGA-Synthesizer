// 十二平均律音律表：A4 = 440 Hz，C4（中央 Do）= 261.625565 Hz。
// 步进值 = round(频率 × 2^32 / Fs)，Fs = 52500000 / 1088 ≈ 48253.676 Hz。
// 第 k 次谐波直接用 k × 基波步进，相位保持严格相干（相对误差约 k/2^32，可忽略）。
// 当前工程只发声 C4（Do），其余音名供后续扩展按键使用。
localparam [31:0] NOTE_STEP_C3  = 32'd11643395; // Do   130.813 Hz
localparam [31:0] NOTE_STEP_CS3 = 32'd12335747; // Do#  138.591 Hz
localparam [31:0] NOTE_STEP_D3  = 32'd13069269; // Re   146.832 Hz
localparam [31:0] NOTE_STEP_DS3 = 32'd13846408; // Re#  155.563 Hz
localparam [31:0] NOTE_STEP_E3  = 32'd14669759; // Mi   164.814 Hz
localparam [31:0] NOTE_STEP_F3  = 32'd15542068; // Fa   174.614 Hz
localparam [31:0] NOTE_STEP_FS3 = 32'd16466247; // Fa#  184.997 Hz
localparam [31:0] NOTE_STEP_G3  = 32'd17445381; // Sol  195.998 Hz
localparam [31:0] NOTE_STEP_GS3 = 32'd18482738; // Sol# 207.652 Hz
localparam [31:0] NOTE_STEP_A3  = 32'd19581779; // La   220.000 Hz
localparam [31:0] NOTE_STEP_AS3 = 32'd20746172; // La#  233.082 Hz
localparam [31:0] NOTE_STEP_B3  = 32'd21979803; // Si   246.942 Hz

localparam [31:0] NOTE_STEP_C4  = 32'd23286790; // Do   261.626 Hz
localparam [31:0] NOTE_STEP_CS4 = 32'd24671495; // Do#  277.183 Hz
localparam [31:0] NOTE_STEP_D4  = 32'd26138538; // Re   293.665 Hz
localparam [31:0] NOTE_STEP_DS4 = 32'd27692817; // Re#  311.127 Hz
localparam [31:0] NOTE_STEP_E4  = 32'd29339517; // Mi   329.628 Hz
localparam [31:0] NOTE_STEP_F4  = 32'd31084136; // Fa   349.228 Hz
localparam [31:0] NOTE_STEP_FS4 = 32'd32932495; // Fa#  369.994 Hz
localparam [31:0] NOTE_STEP_G4  = 32'd34890763; // Sol  391.995 Hz
localparam [31:0] NOTE_STEP_GS4 = 32'd36965475; // Sol# 415.305 Hz
localparam [31:0] NOTE_STEP_A4  = 32'd39163557; // La   440.000 Hz
localparam [31:0] NOTE_STEP_AS4 = 32'd41492343; // La#  466.164 Hz
localparam [31:0] NOTE_STEP_B4  = 32'd43959606; // Si   493.883 Hz

localparam [31:0] NOTE_STEP_C5  = 32'd46573581; // Do   523.251 Hz
localparam [31:0] NOTE_STEP_CS5 = 32'd49342990; // Do#  554.365 Hz
localparam [31:0] NOTE_STEP_D5  = 32'd52277077; // Re   587.330 Hz
localparam [31:0] NOTE_STEP_DS5 = 32'd55385633; // Re#  622.254 Hz
localparam [31:0] NOTE_STEP_E5  = 32'd58679035; // Mi   659.255 Hz
localparam [31:0] NOTE_STEP_F5  = 32'd62168272; // Fa   698.457 Hz
localparam [31:0] NOTE_STEP_FS5 = 32'd65864989; // Fa#  739.989 Hz
localparam [31:0] NOTE_STEP_G5  = 32'd69781526; // Sol  783.991 Hz
localparam [31:0] NOTE_STEP_GS5 = 32'd73930951; // Sol# 830.609 Hz
localparam [31:0] NOTE_STEP_A5  = 32'd78327114; // La   880.000 Hz
localparam [31:0] NOTE_STEP_AS5 = 32'd82984687; // La#  932.328 Hz
localparam [31:0] NOTE_STEP_B5  = 32'd87919213; // Si   987.767 Hz

localparam [31:0] NOTE_STEP_C6  = 32'd93147161; // Do  1046.502 Hz
localparam [31:0] NOTE_STEP_CS6 = 32'd98685980; // Do# 1108.731 Hz
localparam [31:0] NOTE_STEP_D6  = 32'd104554154; // Re  1174.659 Hz
localparam [31:0] NOTE_STEP_DS6 = 32'd110771267; // Re# 1244.508 Hz
localparam [31:0] NOTE_STEP_E6  = 32'd117358069; // Mi  1318.510 Hz
localparam [31:0] NOTE_STEP_F6  = 32'd124336543; // Fa  1396.913 Hz
localparam [31:0] NOTE_STEP_FS6 = 32'd131729979; // Fa# 1479.978 Hz
localparam [31:0] NOTE_STEP_G6  = 32'd139563051; // Sol 1567.982 Hz
localparam [31:0] NOTE_STEP_GS6 = 32'd147861902; // Sol#1661.219 Hz
localparam [31:0] NOTE_STEP_A6  = 32'd156654228; // La  1760.000 Hz
localparam [31:0] NOTE_STEP_AS6 = 32'd165969373; // La# 1864.655 Hz
localparam [31:0] NOTE_STEP_B6  = 32'd175838426; // Si  1975.533 Hz

localparam [31:0] NOTE_DO_STEP = NOTE_STEP_C4; // 兼容旧名称：当前发声的 Do
