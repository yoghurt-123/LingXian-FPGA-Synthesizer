// 从录音拟合的分音参数；不保存录音采样。
// note=0：Do，来源 tone (40).wav，常量与改前完全一致，不得改动。
// note=1：Re，来源 tone (42).wav / D4.wav，由实测拟合（level 已全局归一化到与 Do 同响度）。
// 时间常数=1/衰减率，前 250ms（SPLIT_SAMPLES）与后段分别拟合。
function [31:0] partial_step;
input [3:0] note;
input [3:0] idx;
begin case(note)
3'd0: case(idx) // Do
4'd0: partial_step=32'd23287185;
4'd1: partial_step=32'd46618874;
4'd2: partial_step=32'd69995067;
4'd3: partial_step=32'd93438017;
4'd4: partial_step=32'd116969974;
4'd5: partial_step=32'd140635443;
4'd6: partial_step=32'd164078392;
4'd7: partial_step=32'd187365577;
4'd8: partial_step=32'd210363486;
4'd9: partial_step=32'd233272387;
4'd10: partial_step=32'd257227133;
4'd11: partial_step=32'd280314050;
default: partial_step=32'd0;
endcase
3'd1: case(idx) // Re
4'd0: partial_step=32'd26193284;
4'd1: partial_step=32'd52356565;
4'd2: partial_step=32'd78637820;
4'd3: partial_step=32'd104989139;
4'd4: partial_step=32'd131522723;
4'd5: partial_step=32'd158190420;
4'd6: partial_step=32'd184997312;
4'd7: partial_step=32'd211948277;
4'd8: partial_step=32'd239368390;
4'd9: partial_step=32'd266923805;
4'd10: partial_step=32'd294778828;
4'd11: partial_step=32'd322652410;
default: partial_step=32'd0;
endcase
3'd2: case(idx) // Mi
4'd0: partial_step=32'd29411734;
4'd1: partial_step=32'd58796456;
4'd2: partial_step=32'd88269527;
4'd3: partial_step=32'd117892824;
4'd4: partial_step=32'd147763711;
4'd5: partial_step=32'd177623363;
4'd6: partial_step=32'd207782415;
4'd7: partial_step=32'd238248643;
4'd8: partial_step=32'd269011763;
4'd9: partial_step=32'd300292611;
4'd10: partial_step=32'd331653039;
4'd11: partial_step=32'd363526821;
default: partial_step=32'd0;
endcase
3'd3: case(idx) // Fa
4'd0: partial_step=32'd31130772;
4'd1: partial_step=32'd62289402;
4'd2: partial_step=32'd93646121;
4'd3: partial_step=32'd125068449;
4'd4: partial_step=32'd156530591;
4'd5: partial_step=32'd188433825;
4'd6: partial_step=32'd220591775;
4'd7: partial_step=32'd252942434;
4'd8: partial_step=32'd285459119;
4'd9: partial_step=32'd318061432;
4'd10: partial_step=32'd350864446;
4'd11: partial_step=32'd383377602;
default: partial_step=32'd0;
endcase
3'd4: case(idx) // Sol
4'd0: partial_step=32'd34984290;
4'd1: partial_step=32'd70053325;
4'd2: partial_step=32'd105131592;
4'd3: partial_step=32'd140588520;
4'd4: partial_step=32'd176205949;
4'd5: partial_step=32'd212139367;
4'd6: partial_step=32'd248490626;
4'd7: partial_step=32'd284738254;
4'd8: partial_step=32'd320111240;
4'd9: partial_step=32'd357434151;
4'd10: partial_step=32'd390363331;
4'd11: partial_step=32'd427757281;
default: partial_step=32'd0;
endcase
3'd5: case(idx) // La
4'd0: partial_step=32'd39272124;
4'd1: partial_step=32'd78614954;
4'd2: partial_step=32'd118063539;
4'd3: partial_step=32'd157830840;
4'd4: partial_step=32'd197951646;
4'd5: partial_step=32'd238193513;
4'd6: partial_step=32'd278430552;
4'd7: partial_step=32'd318287348;
4'd8: partial_step=32'd358705454;
4'd9: partial_step=32'd399575733;
4'd10: partial_step=32'd436907864;
4'd11: partial_step=32'd478210891;
default: partial_step=32'd0;
endcase
3'd6: case(idx) // Si
4'd0: partial_step=32'd44023973;
4'd1: partial_step=32'd88265403;
4'd2: partial_step=32'd132567854;
4'd3: partial_step=32'd177362225;
4'd4: partial_step=32'd222402778;
4'd5: partial_step=32'd267639361;
4'd6: partial_step=32'd312843517;
4'd7: partial_step=32'd357555027;
4'd8: partial_step=32'd400067166;
4'd9: partial_step=32'd445330568;
4'd10: partial_step=32'd491103530;
4'd11: partial_step=32'd537315607;
default: partial_step=32'd0;
endcase
4'd7: case(idx) // C5
4'd0: partial_step=32'd46633852;
4'd1: partial_step=32'd93434103;
4'd2: partial_step=32'd140620496;
4'd3: partial_step=32'd188003210;
4'd4: partial_step=32'd235730471;
4'd5: partial_step=32'd283576421;
4'd6: partial_step=32'd328698063;
4'd7: partial_step=32'd376031343;
4'd8: partial_step=32'd423960795;
4'd9: partial_step=32'd472134398;
4'd10: partial_step=32'd520662458;
4'd11: partial_step=32'd570509189;
default: partial_step=32'd0;
endcase
4'd8: case(idx) // D5
4'd0: partial_step=32'd52315362;
4'd1: partial_step=32'd104891146;
4'd2: partial_step=32'd157791886;
4'd3: partial_step=32'd211099780;
4'd4: partial_step=32'd264238155;
4'd5: partial_step=32'd315989205;
4'd6: partial_step=32'd369211352;
4'd7: partial_step=32'd422668242;
4'd8: partial_step=32'd476867611;
4'd9: partial_step=32'd531106160;
4'd10: partial_step=32'd586246554;
4'd11: partial_step=32'd641797901;
default: partial_step=32'd0;
endcase
4'd9: case(idx) // Cs4
4'd0: partial_step=32'd24698039;
4'd1: partial_step=32'd49436096;
4'd2: partial_step=32'd74200752;
4'd3: partial_step=32'd99067528;
4'd4: partial_step=32'd124040640;
4'd5: partial_step=32'd149195380;
4'd6: partial_step=32'd174428863;
4'd7: partial_step=32'd199887231;
4'd8: partial_step=32'd225502787;
4'd9: partial_step=32'd251456807;
4'd10: partial_step=32'd277431847;
4'd11: partial_step=32'd303982440;
default: partial_step=32'd0;
endcase
4'd10: case(idx) // Ds4
4'd0: partial_step=32'd27729222;
4'd1: partial_step=32'd55518942;
4'd2: partial_step=32'd83376217;
4'd3: partial_step=32'd111379235;
4'd4: partial_step=32'd139445859;
4'd5: partial_step=32'd167743027;
4'd6: partial_step=32'd196223879;
4'd7: partial_step=32'd224948144;
4'd8: partial_step=32'd254046514;
4'd9: partial_step=32'd283489183;
4'd10: partial_step=32'd313068024;
4'd11: partial_step=32'd343251032;
default: partial_step=32'd0;
endcase
4'd11: case(idx) // Fs4
4'd0: partial_step=32'd32988172;
4'd1: partial_step=32'd65988041;
4'd2: partial_step=32'd99118066;
4'd3: partial_step=32'd132496623;
4'd4: partial_step=32'd165939326;
4'd5: partial_step=32'd199760060;
4'd6: partial_step=32'd233827456;
4'd7: partial_step=32'd267992086;
4'd8: partial_step=32'd302246643;
4'd9: partial_step=32'd332756140;
4'd10: partial_step=32'd371083622;
4'd11: partial_step=32'd406575320;
default: partial_step=32'd0;
endcase
4'd12: case(idx) // Gs4
4'd0: partial_step=32'd37045479;
4'd1: partial_step=32'd74177479;
4'd2: partial_step=32'd111393461;
4'd3: partial_step=32'd148904408;
4'd4: partial_step=32'd186814347;
4'd5: partial_step=32'd224710861;
4'd6: partial_step=32'd262679737;
4'd7: partial_step=32'd300770872;
4'd8: partial_step=32'd335544716;
4'd9: partial_step=32'd373565855;
4'd10: partial_step=32'd412177230;
4'd11: partial_step=32'd451142350;
default: partial_step=32'd0;
endcase
4'd13: case(idx) // As4
4'd0: partial_step=32'd41638337;
4'd1: partial_step=32'd83278413;
4'd2: partial_step=32'd125188936;
4'd3: partial_step=32'd167353678;
4'd4: partial_step=32'd210041067;
4'd5: partial_step=32'd253163282;
4'd6: partial_step=32'd296204988;
4'd7: partial_step=32'd337618034;
4'd8: partial_step=32'd378773362;
4'd9: partial_step=32'd424459405;
4'd10: partial_step=32'd465792490;
4'd11: partial_step=32'd514520515;
default: partial_step=32'd0;
endcase
4'd14: case(idx) // Cs5
4'd0: partial_step=32'd49396078;
4'd1: partial_step=32'd99103614;
4'd2: partial_step=32'd148721933;
4'd3: partial_step=32'd199648193;
4'd4: partial_step=32'd250199672;
4'd5: partial_step=32'd301523845;
4'd6: partial_step=32'd351901802;
4'd7: partial_step=32'd398884380;
4'd8: partial_step=32'd449866270;
4'd9: partial_step=32'd502682193;
4'd10: partial_step=32'd553047929;
4'd11: partial_step=32'd607163808;
default: partial_step=32'd0;
endcase
4'd15: case(idx) // Ds5
4'd0: partial_step=32'd55531485;
4'd1: partial_step=32'd111290426;
4'd2: partial_step=32'd167059165;
4'd3: partial_step=32'd222281664;
4'd4: partial_step=32'd277879200;
4'd5: partial_step=32'd334772759;
4'd6: partial_step=32'd391568756;
4'd7: partial_step=32'd448582131;
4'd8: partial_step=32'd505842507;
4'd9: partial_step=32'd563913000;
4'd10: partial_step=32'd622412628;
4'd11: partial_step=32'd678022473;
default: partial_step=32'd0;
endcase
default: partial_step=32'd0;
endcase end
endfunction
function [31:0] partial_phase;
input [3:0] note;
input [3:0] idx;
begin case(note)
3'd0: case(idx) // Do
4'd0: partial_phase=32'd3122937951;
4'd1: partial_phase=32'd1567091309;
4'd2: partial_phase=32'd155113713;
4'd3: partial_phase=32'd1025828429;
4'd4: partial_phase=32'd3898706418;
4'd5: partial_phase=32'd2019770709;
4'd6: partial_phase=32'd3864272367;
4'd7: partial_phase=32'd2762197343;
4'd8: partial_phase=32'd2428483506;
4'd9: partial_phase=32'd621931678;
4'd10: partial_phase=32'd686398270;
4'd11: partial_phase=32'd3656498622;
default: partial_phase=32'd0;
endcase
3'd1: case(idx) // Re
4'd0: partial_phase=32'd1622771087;
4'd1: partial_phase=32'd539799917;
4'd2: partial_phase=32'd1211462132;
4'd3: partial_phase=32'd2585520691;
4'd4: partial_phase=32'd786490337;
4'd5: partial_phase=32'd464915942;
4'd6: partial_phase=32'd1877848242;
4'd7: partial_phase=32'd3648290762;
4'd8: partial_phase=32'd2162438203;
4'd9: partial_phase=32'd2740554357;
4'd10: partial_phase=32'd2931773189;
4'd11: partial_phase=32'd3945565257;
default: partial_phase=32'd0;
endcase
3'd2: case(idx) // Mi
4'd0: partial_phase=32'd1394695074;
4'd1: partial_phase=32'd3127297217;
4'd2: partial_phase=32'd4107034410;
4'd3: partial_phase=32'd1792092030;
4'd4: partial_phase=32'd3480259162;
4'd5: partial_phase=32'd2789401118;
4'd6: partial_phase=32'd1125053078;
4'd7: partial_phase=32'd108336024;
4'd8: partial_phase=32'd2857103606;
4'd9: partial_phase=32'd3916938846;
4'd10: partial_phase=32'd1589532460;
4'd11: partial_phase=32'd1525903009;
default: partial_phase=32'd0;
endcase
3'd3: case(idx) // Fa
4'd0: partial_phase=32'd1126277091;
4'd1: partial_phase=32'd1627909593;
4'd2: partial_phase=32'd2565135727;
4'd3: partial_phase=32'd3490566068;
4'd4: partial_phase=32'd1612296596;
4'd5: partial_phase=32'd1958221536;
4'd6: partial_phase=32'd1984294235;
4'd7: partial_phase=32'd2508215720;
4'd8: partial_phase=32'd1488464611;
4'd9: partial_phase=32'd3521301609;
4'd10: partial_phase=32'd1654159308;
4'd11: partial_phase=32'd36843548;
default: partial_phase=32'd0;
endcase
3'd4: case(idx) // Sol
4'd0: partial_phase=32'd156344617;
4'd1: partial_phase=32'd1103390675;
4'd2: partial_phase=32'd3045774632;
4'd3: partial_phase=32'd978002227;
4'd4: partial_phase=32'd1310120638;
4'd5: partial_phase=32'd2066948902;
4'd6: partial_phase=32'd2078985869;
4'd7: partial_phase=32'd315164140;
4'd8: partial_phase=32'd1491270419;
4'd9: partial_phase=32'd4208683226;
4'd10: partial_phase=32'd1439040899;
4'd11: partial_phase=32'd478412151;
default: partial_phase=32'd0;
endcase
3'd5: case(idx) // La
4'd0: partial_phase=32'd488642715;
4'd1: partial_phase=32'd1077964734;
4'd2: partial_phase=32'd3367577875;
4'd3: partial_phase=32'd192091401;
4'd4: partial_phase=32'd2924314994;
4'd5: partial_phase=32'd4015987279;
4'd6: partial_phase=32'd293607948;
4'd7: partial_phase=32'd1050983109;
4'd8: partial_phase=32'd2508772259;
4'd9: partial_phase=32'd3520722869;
4'd10: partial_phase=32'd2830411503;
4'd11: partial_phase=32'd2202542187;
default: partial_phase=32'd0;
endcase
3'd6: case(idx) // Si
4'd0: partial_phase=32'd264588756;
4'd1: partial_phase=32'd406654768;
4'd2: partial_phase=32'd1278622709;
4'd3: partial_phase=32'd1388200312;
4'd4: partial_phase=32'd936460678;
4'd5: partial_phase=32'd2013736761;
4'd6: partial_phase=32'd701994204;
4'd7: partial_phase=32'd248797853;
4'd8: partial_phase=32'd2574789349;
4'd9: partial_phase=32'd3784807563;
4'd10: partial_phase=32'd1640745907;
4'd11: partial_phase=32'd811400483;
default: partial_phase=32'd0;
endcase
4'd7: case(idx) // C5
4'd0: partial_phase=32'd2005313426;
4'd1: partial_phase=32'd3537163444;
4'd2: partial_phase=32'd1346025334;
4'd3: partial_phase=32'd1738694285;
4'd4: partial_phase=32'd1700715289;
4'd5: partial_phase=32'd2999579784;
4'd6: partial_phase=32'd3075432050;
4'd7: partial_phase=32'd1063324669;
4'd8: partial_phase=32'd3468556254;
4'd9: partial_phase=32'd3648704723;
4'd10: partial_phase=32'd1880307998;
4'd11: partial_phase=32'd1531654943;
default: partial_phase=32'd0;
endcase
4'd8: case(idx) // D5
4'd0: partial_phase=32'd3665425832;
4'd1: partial_phase=32'd126830071;
4'd2: partial_phase=32'd1171305694;
4'd3: partial_phase=32'd2432219569;
4'd4: partial_phase=32'd4070547542;
4'd5: partial_phase=32'd2896257075;
4'd6: partial_phase=32'd58721563;
4'd7: partial_phase=32'd1456894764;
4'd8: partial_phase=32'd1286971897;
4'd9: partial_phase=32'd258871728;
4'd10: partial_phase=32'd746915498;
4'd11: partial_phase=32'd3227534360;
default: partial_phase=32'd0;
endcase
4'd9: case(idx) // Cs4
4'd0: partial_phase=32'd2171914184;
4'd1: partial_phase=32'd711021435;
4'd2: partial_phase=32'd1623727055;
4'd3: partial_phase=32'd3788053312;
4'd4: partial_phase=32'd1465784581;
4'd5: partial_phase=32'd3473571849;
4'd6: partial_phase=32'd2061649646;
4'd7: partial_phase=32'd3104389391;
4'd8: partial_phase=32'd1397175982;
4'd9: partial_phase=32'd799793840;
4'd10: partial_phase=32'd274028098;
4'd11: partial_phase=32'd1186251078;
default: partial_phase=32'd0;
endcase
4'd10: case(idx) // Ds4
4'd0: partial_phase=32'd1821827243;
4'd1: partial_phase=32'd4240354788;
4'd2: partial_phase=32'd4185175145;
4'd3: partial_phase=32'd1280051124;
4'd4: partial_phase=32'd310793359;
4'd5: partial_phase=32'd2379283780;
4'd6: partial_phase=32'd281970515;
4'd7: partial_phase=32'd473183291;
4'd8: partial_phase=32'd72690918;
4'd9: partial_phase=32'd2356245625;
4'd10: partial_phase=32'd2601729044;
4'd11: partial_phase=32'd1806063157;
default: partial_phase=32'd0;
endcase
4'd11: case(idx) // Fs4
4'd0: partial_phase=32'd979758526;
4'd1: partial_phase=32'd3631112730;
4'd2: partial_phase=32'd3280174613;
4'd3: partial_phase=32'd1214171277;
4'd4: partial_phase=32'd2917844739;
4'd5: partial_phase=32'd2193208036;
4'd6: partial_phase=32'd3576308640;
4'd7: partial_phase=32'd2809844853;
4'd8: partial_phase=32'd4050292178;
4'd9: partial_phase=32'd1845580922;
4'd10: partial_phase=32'd15198076;
4'd11: partial_phase=32'd2324057947;
default: partial_phase=32'd0;
endcase
4'd12: case(idx) // Gs4
4'd0: partial_phase=32'd611324214;
4'd1: partial_phase=32'd2226209263;
4'd2: partial_phase=32'd1102995304;
4'd3: partial_phase=32'd449119152;
4'd4: partial_phase=32'd3369574965;
4'd5: partial_phase=32'd1861675523;
4'd6: partial_phase=32'd1112221108;
4'd7: partial_phase=32'd3683640533;
4'd8: partial_phase=32'd638657568;
4'd9: partial_phase=32'd1924771057;
4'd10: partial_phase=32'd2377565470;
4'd11: partial_phase=32'd212375095;
default: partial_phase=32'd0;
endcase
4'd13: case(idx) // As4
4'd0: partial_phase=32'd128083611;
4'd1: partial_phase=32'd396503506;
4'd2: partial_phase=32'd1637085129;
4'd3: partial_phase=32'd2070581757;
4'd4: partial_phase=32'd3779833151;
4'd5: partial_phase=32'd3142936176;
4'd6: partial_phase=32'd629483353;
4'd7: partial_phase=32'd2523215561;
4'd8: partial_phase=32'd3177862452;
4'd9: partial_phase=32'd1792094540;
4'd10: partial_phase=32'd156158486;
4'd11: partial_phase=32'd740862309;
default: partial_phase=32'd0;
endcase
4'd14: case(idx) // Cs5
4'd0: partial_phase=32'd12201301;
4'd1: partial_phase=32'd1428981140;
4'd2: partial_phase=32'd2979604008;
4'd3: partial_phase=32'd60892405;
4'd4: partial_phase=32'd2713415428;
4'd5: partial_phase=32'd1653891202;
4'd6: partial_phase=32'd2319401809;
4'd7: partial_phase=32'd2785074128;
4'd8: partial_phase=32'd1645441425;
4'd9: partial_phase=32'd284582239;
4'd10: partial_phase=32'd1923072700;
4'd11: partial_phase=32'd2929030431;
default: partial_phase=32'd0;
endcase
4'd15: case(idx) // Ds5
4'd0: partial_phase=32'd2849500601;
4'd1: partial_phase=32'd3665232167;
4'd2: partial_phase=32'd2066494237;
4'd3: partial_phase=32'd1835521913;
4'd4: partial_phase=32'd1943825629;
4'd5: partial_phase=32'd517027620;
4'd6: partial_phase=32'd1754774070;
4'd7: partial_phase=32'd1254795082;
4'd8: partial_phase=32'd12275345;
4'd9: partial_phase=32'd3328941844;
4'd10: partial_phase=32'd234141274;
4'd11: partial_phase=32'd2514088624;
default: partial_phase=32'd0;
endcase
default: partial_phase=32'd0;
endcase end
endfunction
function [15:0] partial_level;
input [3:0] note;
input [3:0] idx;
begin case(note)
3'd0: case(idx) // Do
4'd0: partial_level=16'd7939;
4'd1: partial_level=16'd8617;
4'd2: partial_level=16'd2570;
4'd3: partial_level=16'd2149;
4'd4: partial_level=16'd3252;
4'd5: partial_level=16'd783;
4'd6: partial_level=16'd1779;
4'd7: partial_level=16'd357;
4'd8: partial_level=16'd385;
4'd9: partial_level=16'd75;
4'd10: partial_level=16'd77;
4'd11: partial_level=16'd17;
default: partial_level=16'd0;
endcase
3'd1: case(idx) // Re
4'd0: partial_level=16'd8791;
4'd1: partial_level=16'd10671;
4'd2: partial_level=16'd2293;
4'd3: partial_level=16'd1856;
4'd4: partial_level=16'd1212;
4'd5: partial_level=16'd750;
4'd6: partial_level=16'd798;
4'd7: partial_level=16'd435;
4'd8: partial_level=16'd338;
4'd9: partial_level=16'd289;
4'd10: partial_level=16'd203;
4'd11: partial_level=16'd364;
default: partial_level=16'd0;
endcase
3'd2: case(idx) // Mi
4'd0: partial_level=16'd8826;
4'd1: partial_level=16'd7693;
4'd2: partial_level=16'd4295;
4'd3: partial_level=16'd2878;
4'd4: partial_level=16'd885;
4'd5: partial_level=16'd716;
4'd6: partial_level=16'd751;
4'd7: partial_level=16'd783;
4'd8: partial_level=16'd390;
4'd9: partial_level=16'd260;
4'd10: partial_level=16'd244;
4'd11: partial_level=16'd278;
default: partial_level=16'd0;
endcase
3'd3: case(idx) // Fa
4'd0: partial_level=16'd15464;
4'd1: partial_level=16'd3873;
4'd2: partial_level=16'd1932;
4'd3: partial_level=16'd1694;
4'd4: partial_level=16'd1157;
4'd5: partial_level=16'd1063;
4'd6: partial_level=16'd642;
4'd7: partial_level=16'd898;
4'd8: partial_level=16'd438;
4'd9: partial_level=16'd256;
4'd10: partial_level=16'd239;
4'd11: partial_level=16'd344;
default: partial_level=16'd0;
endcase
3'd4: case(idx) // Sol
4'd0: partial_level=16'd15493;
4'd1: partial_level=16'd2665;
4'd2: partial_level=16'd2182;
4'd3: partial_level=16'd2720;
4'd4: partial_level=16'd1011;
4'd5: partial_level=16'd1765;
4'd6: partial_level=16'd902;
4'd7: partial_level=16'd420;
4'd8: partial_level=16'd314;
4'd9: partial_level=16'd227;
4'd10: partial_level=16'd192;
4'd11: partial_level=16'd109;
default: partial_level=16'd0;
endcase
3'd5: case(idx) // La
4'd0: partial_level=16'd9169;
4'd1: partial_level=16'd3652;
4'd2: partial_level=16'd7668;
4'd3: partial_level=16'd2073;
4'd4: partial_level=16'd1877;
4'd5: partial_level=16'd1739;
4'd6: partial_level=16'd798;
4'd7: partial_level=16'd534;
4'd8: partial_level=16'd139;
4'd9: partial_level=16'd136;
4'd10: partial_level=16'd121;
4'd11: partial_level=16'd93;
default: partial_level=16'd0;
endcase
3'd6: case(idx) // Si
4'd0: partial_level=16'd11373;
4'd1: partial_level=16'd3851;
4'd2: partial_level=16'd5721;
4'd3: partial_level=16'd2290;
4'd4: partial_level=16'd1199;
4'd5: partial_level=16'd2146;
4'd6: partial_level=16'd311;
4'd7: partial_level=16'd542;
4'd8: partial_level=16'd186;
4'd9: partial_level=16'd111;
4'd10: partial_level=16'd100;
4'd11: partial_level=16'd170;
default: partial_level=16'd0;
endcase
4'd7: case(idx) // C5
4'd0: partial_level=16'd12220;
4'd1: partial_level=16'd5445;
4'd2: partial_level=16'd2897;
4'd3: partial_level=16'd3093;
4'd4: partial_level=16'd1254;
4'd5: partial_level=16'd1937;
4'd6: partial_level=16'd297;
4'd7: partial_level=16'd260;
4'd8: partial_level=16'd166;
4'd9: partial_level=16'd164;
4'd10: partial_level=16'd138;
4'd11: partial_level=16'd127;
default: partial_level=16'd0;
endcase
4'd8: case(idx) // D5
4'd0: partial_level=16'd19658;
4'd1: partial_level=16'd2437;
4'd2: partial_level=16'd2375;
4'd3: partial_level=16'd1354;
4'd4: partial_level=16'd542;
4'd5: partial_level=16'd420;
4'd6: partial_level=16'd342;
4'd7: partial_level=16'd277;
4'd8: partial_level=16'd241;
4'd9: partial_level=16'd182;
4'd10: partial_level=16'd87;
4'd11: partial_level=16'd85;
default: partial_level=16'd0;
endcase
4'd9: case(idx) // Cs4
4'd0: partial_level=16'd8598;
4'd1: partial_level=16'd8822;
4'd2: partial_level=16'd1928;
4'd3: partial_level=16'd3012;
4'd4: partial_level=16'd1113;
4'd5: partial_level=16'd1151;
4'd6: partial_level=16'd1674;
4'd7: partial_level=16'd526;
4'd8: partial_level=16'd376;
4'd9: partial_level=16'd323;
4'd10: partial_level=16'd260;
4'd11: partial_level=16'd218;
default: partial_level=16'd0;
endcase
4'd10: case(idx) // Ds4
4'd0: partial_level=16'd8265;
4'd1: partial_level=16'd10165;
4'd2: partial_level=16'd2176;
4'd3: partial_level=16'd1230;
4'd4: partial_level=16'd2579;
4'd5: partial_level=16'd1147;
4'd6: partial_level=16'd874;
4'd7: partial_level=16'd326;
4'd8: partial_level=16'd576;
4'd9: partial_level=16'd228;
4'd10: partial_level=16'd197;
4'd11: partial_level=16'd237;
default: partial_level=16'd0;
endcase
4'd11: case(idx) // Fs4
4'd0: partial_level=16'd12612;
4'd1: partial_level=16'd5459;
4'd2: partial_level=16'd4269;
4'd3: partial_level=16'd1249;
4'd4: partial_level=16'd1325;
4'd5: partial_level=16'd765;
4'd6: partial_level=16'd802;
4'd7: partial_level=16'd646;
4'd8: partial_level=16'd321;
4'd9: partial_level=16'd166;
4'd10: partial_level=16'd205;
4'd11: partial_level=16'd179;
default: partial_level=16'd0;
endcase
4'd12: case(idx) // Gs4
4'd0: partial_level=16'd15607;
4'd1: partial_level=16'd3878;
4'd2: partial_level=16'd3134;
4'd3: partial_level=16'd2467;
4'd4: partial_level=16'd620;
4'd5: partial_level=16'd585;
4'd6: partial_level=16'd755;
4'd7: partial_level=16'd281;
4'd8: partial_level=16'd202;
4'd9: partial_level=16'd163;
4'd10: partial_level=16'd150;
4'd11: partial_level=16'd159;
default: partial_level=16'd0;
endcase
4'd13: case(idx) // As4
4'd0: partial_level=16'd9115;
4'd1: partial_level=16'd4558;
4'd2: partial_level=16'd6929;
4'd3: partial_level=16'd2255;
4'd4: partial_level=16'd2574;
4'd5: partial_level=16'd1090;
4'd6: partial_level=16'd472;
4'd7: partial_level=16'd351;
4'd8: partial_level=16'd211;
4'd9: partial_level=16'd160;
4'd10: partial_level=16'd173;
4'd11: partial_level=16'd111;
default: partial_level=16'd0;
endcase
4'd14: case(idx) // Cs5
4'd0: partial_level=16'd20186;
4'd1: partial_level=16'd2840;
4'd2: partial_level=16'd1427;
4'd3: partial_level=16'd756;
4'd4: partial_level=16'd1133;
4'd5: partial_level=16'd690;
4'd6: partial_level=16'd276;
4'd7: partial_level=16'd199;
4'd8: partial_level=16'd108;
4'd9: partial_level=16'd96;
4'd10: partial_level=16'd164;
4'd11: partial_level=16'd124;
default: partial_level=16'd0;
endcase
4'd15: case(idx) // Ds5
4'd0: partial_level=16'd21885;
4'd1: partial_level=16'd1991;
4'd2: partial_level=16'd1195;
4'd3: partial_level=16'd1087;
4'd4: partial_level=16'd477;
4'd5: partial_level=16'd382;
4'd6: partial_level=16'd217;
4'd7: partial_level=16'd190;
4'd8: partial_level=16'd165;
4'd9: partial_level=16'd156;
4'd10: partial_level=16'd145;
4'd11: partial_level=16'd110;
default: partial_level=16'd0;
endcase
default: partial_level=16'd0;
endcase end
endfunction
function [15:0] partial_attack;
input [3:0] note;
input [3:0] idx;
begin case(note)
3'd0: case(idx) // Do
4'd0: partial_attack=16'd724;
4'd1: partial_attack=16'd1930;
4'd2: partial_attack=16'd1930;
4'd3: partial_attack=16'd2413;
4'd4: partial_attack=16'd1930;
4'd5: partial_attack=16'd724;
4'd6: partial_attack=16'd724;
4'd7: partial_attack=16'd724;
4'd8: partial_attack=16'd1930;
4'd9: partial_attack=16'd1930;
4'd10: partial_attack=16'd724;
4'd11: partial_attack=16'd724;
default: partial_attack=16'd0;
endcase
3'd1: case(idx) // Re
4'd0: partial_attack=16'd660;
4'd1: partial_attack=16'd1760;
4'd2: partial_attack=16'd220;
4'd3: partial_attack=16'd110;
4'd4: partial_attack=16'd220;
4'd5: partial_attack=16'd1540;
4'd6: partial_attack=16'd110;
4'd7: partial_attack=16'd1540;
4'd8: partial_attack=16'd2420;
4'd9: partial_attack=16'd2420;
4'd10: partial_attack=16'd1980;
4'd11: partial_attack=16'd1540;
default: partial_attack=16'd0;
endcase
3'd2: case(idx) // Mi
4'd0: partial_attack=16'd220;
4'd1: partial_attack=16'd2200;
4'd2: partial_attack=16'd880;
4'd3: partial_attack=16'd880;
4'd4: partial_attack=16'd1100;
4'd5: partial_attack=16'd4620;
4'd6: partial_attack=16'd660;
4'd7: partial_attack=16'd660;
4'd8: partial_attack=16'd220;
4'd9: partial_attack=16'd220;
4'd10: partial_attack=16'd220;
4'd11: partial_attack=16'd220;
default: partial_attack=16'd0;
endcase
3'd3: case(idx) // Fa
4'd0: partial_attack=16'd1320;
4'd1: partial_attack=16'd1100;
4'd2: partial_attack=16'd110;
4'd3: partial_attack=16'd1100;
4'd4: partial_attack=16'd660;
4'd5: partial_attack=16'd660;
4'd6: partial_attack=16'd660;
4'd7: partial_attack=16'd220;
4'd8: partial_attack=16'd2420;
4'd9: partial_attack=16'd1100;
4'd10: partial_attack=16'd220;
4'd11: partial_attack=16'd2420;
default: partial_attack=16'd0;
endcase
3'd4: case(idx) // Sol
4'd0: partial_attack=16'd220;
4'd1: partial_attack=16'd110;
4'd2: partial_attack=16'd660;
4'd3: partial_attack=16'd1980;
4'd4: partial_attack=16'd4620;
4'd5: partial_attack=16'd110;
4'd6: partial_attack=16'd220;
4'd7: partial_attack=16'd440;
4'd8: partial_attack=16'd110;
4'd9: partial_attack=16'd2860;
4'd10: partial_attack=16'd110;
4'd11: partial_attack=16'd440;
default: partial_attack=16'd0;
endcase
3'd5: case(idx) // La
4'd0: partial_attack=16'd220;
4'd1: partial_attack=16'd1320;
4'd2: partial_attack=16'd1320;
4'd3: partial_attack=16'd1320;
4'd4: partial_attack=16'd1980;
4'd5: partial_attack=16'd1100;
4'd6: partial_attack=16'd440;
4'd7: partial_attack=16'd1320;
4'd8: partial_attack=16'd2640;
4'd9: partial_attack=16'd3300;
4'd10: partial_attack=16'd4620;
4'd11: partial_attack=16'd3300;
default: partial_attack=16'd0;
endcase
3'd6: case(idx) // Si
4'd0: partial_attack=16'd660;
4'd1: partial_attack=16'd1320;
4'd2: partial_attack=16'd440;
4'd3: partial_attack=16'd2200;
4'd4: partial_attack=16'd440;
4'd5: partial_attack=16'd110;
4'd6: partial_attack=16'd110;
4'd7: partial_attack=16'd1100;
4'd8: partial_attack=16'd220;
4'd9: partial_attack=16'd220;
4'd10: partial_attack=16'd440;
4'd11: partial_attack=16'd880;
default: partial_attack=16'd0;
endcase
4'd7: case(idx) // C5
4'd0: partial_attack=16'd2420;
4'd1: partial_attack=16'd1320;
4'd2: partial_attack=16'd880;
4'd3: partial_attack=16'd880;
4'd4: partial_attack=16'd110;
4'd5: partial_attack=16'd220;
4'd6: partial_attack=16'd1100;
4'd7: partial_attack=16'd220;
4'd8: partial_attack=16'd2860;
4'd9: partial_attack=16'd3300;
4'd10: partial_attack=16'd2860;
4'd11: partial_attack=16'd3300;
default: partial_attack=16'd0;
endcase
4'd8: case(idx) // D5
4'd0: partial_attack=16'd440;
4'd1: partial_attack=16'd1320;
4'd2: partial_attack=16'd220;
4'd3: partial_attack=16'd220;
4'd4: partial_attack=16'd880;
4'd5: partial_attack=16'd3960;
4'd6: partial_attack=16'd880;
4'd7: partial_attack=16'd880;
4'd8: partial_attack=16'd880;
4'd9: partial_attack=16'd660;
4'd10: partial_attack=16'd440;
4'd11: partial_attack=16'd440;
default: partial_attack=16'd0;
endcase
4'd9: case(idx) // Cs4
4'd0: partial_attack=16'd2200;
4'd1: partial_attack=16'd440;
4'd2: partial_attack=16'd1320;
4'd3: partial_attack=16'd3080;
4'd4: partial_attack=16'd660;
4'd5: partial_attack=16'd1540;
4'd6: partial_attack=16'd220;
4'd7: partial_attack=16'd110;
4'd8: partial_attack=16'd880;
4'd9: partial_attack=16'd1320;
4'd10: partial_attack=16'd220;
4'd11: partial_attack=16'd1320;
default: partial_attack=16'd0;
endcase
4'd10: case(idx) // Ds4
4'd0: partial_attack=16'd220;
4'd1: partial_attack=16'd440;
4'd2: partial_attack=16'd2420;
4'd3: partial_attack=16'd880;
4'd4: partial_attack=16'd880;
4'd5: partial_attack=16'd880;
4'd6: partial_attack=16'd880;
4'd7: partial_attack=16'd1760;
4'd8: partial_attack=16'd1760;
4'd9: partial_attack=16'd1760;
4'd10: partial_attack=16'd220;
4'd11: partial_attack=16'd220;
default: partial_attack=16'd0;
endcase
4'd11: case(idx) // Fs4
4'd0: partial_attack=16'd1100;
4'd1: partial_attack=16'd1540;
4'd2: partial_attack=16'd1980;
4'd3: partial_attack=16'd110;
4'd4: partial_attack=16'd1100;
4'd5: partial_attack=16'd6600;
4'd6: partial_attack=16'd110;
4'd7: partial_attack=16'd660;
4'd8: partial_attack=16'd660;
4'd9: partial_attack=16'd660;
4'd10: partial_attack=16'd1100;
4'd11: partial_attack=16'd1100;
default: partial_attack=16'd0;
endcase
4'd12: case(idx) // Gs4
4'd0: partial_attack=16'd2200;
4'd1: partial_attack=16'd1100;
4'd2: partial_attack=16'd880;
4'd3: partial_attack=16'd2200;
4'd4: partial_attack=16'd440;
4'd5: partial_attack=16'd440;
4'd6: partial_attack=16'd660;
4'd7: partial_attack=16'd1100;
4'd8: partial_attack=16'd2200;
4'd9: partial_attack=16'd1320;
4'd10: partial_attack=16'd1100;
4'd11: partial_attack=16'd1100;
default: partial_attack=16'd0;
endcase
4'd13: case(idx) // As4
4'd0: partial_attack=16'd220;
4'd1: partial_attack=16'd880;
4'd2: partial_attack=16'd220;
4'd3: partial_attack=16'd440;
4'd4: partial_attack=16'd440;
4'd5: partial_attack=16'd440;
4'd6: partial_attack=16'd660;
4'd7: partial_attack=16'd660;
4'd8: partial_attack=16'd2420;
4'd9: partial_attack=16'd440;
4'd10: partial_attack=16'd1100;
4'd11: partial_attack=16'd660;
default: partial_attack=16'd0;
endcase
4'd14: case(idx) // Cs5
4'd0: partial_attack=16'd880;
4'd1: partial_attack=16'd660;
4'd2: partial_attack=16'd4400;
4'd3: partial_attack=16'd660;
4'd4: partial_attack=16'd880;
4'd5: partial_attack=16'd1100;
4'd6: partial_attack=16'd220;
4'd7: partial_attack=16'd440;
4'd8: partial_attack=16'd110;
4'd9: partial_attack=16'd110;
4'd10: partial_attack=16'd440;
4'd11: partial_attack=16'd440;
default: partial_attack=16'd0;
endcase
4'd15: case(idx) // Ds5
4'd0: partial_attack=16'd440;
4'd1: partial_attack=16'd1320;
4'd2: partial_attack=16'd880;
4'd3: partial_attack=16'd110;
4'd4: partial_attack=16'd880;
4'd5: partial_attack=16'd1320;
4'd6: partial_attack=16'd880;
4'd7: partial_attack=16'd440;
4'd8: partial_attack=16'd880;
4'd9: partial_attack=16'd440;
4'd10: partial_attack=16'd880;
4'd11: partial_attack=16'd880;
default: partial_attack=16'd0;
endcase
default: partial_attack=16'd0;
endcase end
endfunction
function [31:0] partial_rise;
input [3:0] note;
input [3:0] idx;
begin case(note)
3'd0: case(idx) // Do
4'd0: partial_rise=32'd44915;
4'd1: partial_rise=32'd18288;
4'd2: partial_rise=32'd5455;
4'd3: partial_rise=32'd3648;
4'd4: partial_rise=32'd6902;
4'd5: partial_rise=32'd4430;
4'd6: partial_rise=32'd10065;
4'd7: partial_rise=32'd2020;
4'd8: partial_rise=32'd818;
4'd9: partial_rise=32'd160;
4'd10: partial_rise=32'd436;
4'd11: partial_rise=32'd97;
default: partial_rise=32'd0;
endcase
3'd1: case(idx) // Re
4'd0: partial_rise=32'd54557;
4'd1: partial_rise=32'd24834;
4'd2: partial_rise=32'd42692;
4'd3: partial_rise=32'd69111;
4'd4: partial_rise=32'd22565;
4'd5: partial_rise=32'd1995;
4'd6: partial_rise=32'd29715;
4'd7: partial_rise=32'd1157;
4'd8: partial_rise=32'd572;
4'd9: partial_rise=32'd489;
4'd10: partial_rise=32'd420;
4'd11: partial_rise=32'd968;
default: partial_rise=32'd0;
endcase
3'd2: case(idx) // Mi
4'd0: partial_rise=32'd164324;
4'd1: partial_rise=32'd14323;
4'd2: partial_rise=32'd19991;
4'd3: partial_rise=32'd13396;
4'd4: partial_rise=32'd3295;
4'd5: partial_rise=32'd635;
4'd6: partial_rise=32'd4661;
4'd7: partial_rise=32'd4859;
4'd8: partial_rise=32'd7261;
4'd9: partial_rise=32'd4841;
4'd10: partial_rise=32'd4543;
4'd11: partial_rise=32'd5176;
default: partial_rise=32'd0;
endcase
3'd3: case(idx) // Fa
4'd0: partial_rise=32'd47985;
4'd1: partial_rise=32'd14422;
4'd2: partial_rise=32'd71941;
4'd3: partial_rise=32'd6308;
4'd4: partial_rise=32'd7180;
4'd5: partial_rise=32'd6597;
4'd6: partial_rise=32'd3984;
4'd7: partial_rise=32'd16718;
4'd8: partial_rise=32'd741;
4'd9: partial_rise=32'd953;
4'd10: partial_rise=32'd4450;
4'd11: partial_rise=32'd582;
default: partial_rise=32'd0;
endcase
3'd4: case(idx) // Sol
4'd0: partial_rise=32'd288451;
4'd1: partial_rise=32'd99235;
4'd2: partial_rise=32'd13542;
4'd3: partial_rise=32'd5627;
4'd4: partial_rise=32'd896;
4'd5: partial_rise=32'd65722;
4'd6: partial_rise=32'd16794;
4'd7: partial_rise=32'd3910;
4'd8: partial_rise=32'd11692;
4'd9: partial_rise=32'd325;
4'd10: partial_rise=32'd7149;
4'd11: partial_rise=32'd1015;
default: partial_rise=32'd0;
endcase
3'd5: case(idx) // La
4'd0: partial_rise=32'd170710;
4'd1: partial_rise=32'd11332;
4'd2: partial_rise=32'd23794;
4'd3: partial_rise=32'd6433;
4'd4: partial_rise=32'd3883;
4'd5: partial_rise=32'd6475;
4'd6: partial_rise=32'd7429;
4'd7: partial_rise=32'd1657;
4'd8: partial_rise=32'd216;
4'd9: partial_rise=32'd169;
4'd10: partial_rise=32'd107;
4'd11: partial_rise=32'd115;
default: partial_rise=32'd0;
endcase
3'd6: case(idx) // Si
4'd0: partial_rise=32'd70582;
4'd1: partial_rise=32'd11950;
4'd2: partial_rise=32'd53257;
4'd3: partial_rise=32'd4264;
4'd4: partial_rise=32'd11162;
4'd5: partial_rise=32'd79909;
4'd6: partial_rise=32'd11581;
4'd7: partial_rise=32'd2018;
4'd8: partial_rise=32'd3462;
4'd9: partial_rise=32'd2067;
4'd10: partial_rise=32'd931;
4'd11: partial_rise=32'd791;
default: partial_rise=32'd0;
endcase
4'd7: case(idx) // C5
4'd0: partial_rise=32'd20683;
4'd1: partial_rise=32'd16896;
4'd2: partial_rise=32'd13484;
4'd3: partial_rise=32'd14397;
4'd4: partial_rise=32'd46694;
4'd5: partial_rise=32'd36063;
4'd6: partial_rise=32'd1106;
4'd7: partial_rise=32'd4841;
4'd8: partial_rise=32'd238;
4'd9: partial_rise=32'd204;
4'd10: partial_rise=32'd198;
4'd11: partial_rise=32'd158;
default: partial_rise=32'd0;
endcase
4'd8: case(idx) // D5
4'd0: partial_rise=32'd182998;
4'd1: partial_rise=32'd7562;
4'd2: partial_rise=32'd44218;
4'd3: partial_rise=32'd25209;
4'd4: partial_rise=32'd2523;
4'd5: partial_rise=32'd434;
4'd6: partial_rise=32'd1592;
4'd7: partial_rise=32'd1289;
4'd8: partial_rise=32'd1122;
4'd9: partial_rise=32'd1130;
4'd10: partial_rise=32'd810;
4'd11: partial_rise=32'd791;
default: partial_rise=32'd0;
endcase
4'd9: case(idx) // Cs4
4'd0: partial_rise=32'd16008;
4'd1: partial_rise=32'd82125;
4'd2: partial_rise=32'd5983;
4'd3: partial_rise=32'd4006;
4'd4: partial_rise=32'd6907;
4'd5: partial_rise=32'd3061;
4'd6: partial_rise=32'd31167;
4'd7: partial_rise=32'd19586;
4'd8: partial_rise=32'd1750;
4'd9: partial_rise=32'd1002;
4'd10: partial_rise=32'd4841;
4'd11: partial_rise=32'd676;
default: partial_rise=32'd0;
endcase
4'd10: case(idx) // Ds4
4'd0: partial_rise=32'd153879;
4'd1: partial_rise=32'd94627;
4'd2: partial_rise=32'd3683;
4'd3: partial_rise=32'd5725;
4'd4: partial_rise=32'd12004;
4'd5: partial_rise=32'd5339;
4'd6: partial_rise=32'd4068;
4'd7: partial_rise=32'd759;
4'd8: partial_rise=32'd1341;
4'd9: partial_rise=32'd531;
4'd10: partial_rise=32'd3668;
4'd11: partial_rise=32'd4413;
default: partial_rise=32'd0;
endcase
4'd11: case(idx) // Fs4
4'd0: partial_rise=32'd46963;
4'd1: partial_rise=32'd14520;
4'd2: partial_rise=32'd8831;
4'd3: partial_rise=32'd46508;
4'd4: partial_rise=32'd4934;
4'd5: partial_rise=32'd475;
4'd6: partial_rise=32'd29864;
4'd7: partial_rise=32'd4009;
4'd8: partial_rise=32'd1992;
4'd9: partial_rise=32'd1030;
4'd10: partial_rise=32'd763;
4'd11: partial_rise=32'd667;
default: partial_rise=32'd0;
endcase
4'd12: case(idx) // Gs4
4'd0: partial_rise=32'd29057;
4'd1: partial_rise=32'd14440;
4'd2: partial_rise=32'd14587;
4'd3: partial_rise=32'd4593;
4'd4: partial_rise=32'd5772;
4'd5: partial_rise=32'd5446;
4'd6: partial_rise=32'd4686;
4'd7: partial_rise=32'd1046;
4'd8: partial_rise=32'd376;
4'd9: partial_rise=32'd506;
4'd10: partial_rise=32'd559;
4'd11: partial_rise=32'd592;
default: partial_rise=32'd0;
endcase
4'd13: case(idx) // As4
4'd0: partial_rise=32'd169705;
4'd1: partial_rise=32'd21215;
4'd2: partial_rise=32'd129005;
4'd3: partial_rise=32'd20992;
4'd4: partial_rise=32'd23962;
4'd5: partial_rise=32'd10147;
4'd6: partial_rise=32'd2929;
4'd7: partial_rise=32'd2178;
4'd8: partial_rise=32'd357;
4'd9: partial_rise=32'd1489;
4'd10: partial_rise=32'd644;
4'd11: partial_rise=32'd689;
default: partial_rise=32'd0;
endcase
4'd14: case(idx) // Cs5
4'd0: partial_rise=32'd93957;
4'd1: partial_rise=32'd17625;
4'd2: partial_rise=32'd1328;
4'd3: partial_rise=32'd4692;
4'd4: partial_rise=32'd5274;
4'd5: partial_rise=32'd2569;
4'd6: partial_rise=32'd5139;
4'd7: partial_rise=32'd1853;
4'd8: partial_rise=32'd4022;
4'd9: partial_rise=32'd3575;
4'd10: partial_rise=32'd1527;
4'd11: partial_rise=32'd1154;
default: partial_rise=32'd0;
endcase
4'd15: case(idx) // Ds5
4'd0: partial_rise=32'd203729;
4'd1: partial_rise=32'd6178;
4'd2: partial_rise=32'd5562;
4'd3: partial_rise=32'd40476;
4'd4: partial_rise=32'd2220;
4'd5: partial_rise=32'd1185;
4'd6: partial_rise=32'd1010;
4'd7: partial_rise=32'd1769;
4'd8: partial_rise=32'd768;
4'd9: partial_rise=32'd1452;
4'd10: partial_rise=32'd675;
4'd11: partial_rise=32'd512;
default: partial_rise=32'd0;
endcase
default: partial_rise=32'd0;
endcase end
endfunction
function [15:0] partial_fast;
input [3:0] note;
input [3:0] idx;
begin case(note)
3'd0: case(idx) // Do
4'd0: partial_fast=16'd923;
4'd1: partial_fast=16'd769;
4'd2: partial_fast=16'd913;
4'd3: partial_fast=16'd985;
4'd4: partial_fast=16'd1435;
4'd5: partial_fast=16'd991;
4'd6: partial_fast=16'd860;
4'd7: partial_fast=16'd1777;
4'd8: partial_fast=16'd2460;
4'd9: partial_fast=16'd1419;
4'd10: partial_fast=16'd3812;
4'd11: partial_fast=16'd2914;
default: partial_fast=16'd0;
endcase
3'd1: case(idx) // Re
4'd0: partial_fast=16'd811;
4'd1: partial_fast=16'd880;
4'd2: partial_fast=16'd281;
4'd3: partial_fast=16'd1278;
4'd4: partial_fast=16'd1027;
4'd5: partial_fast=16'd1031;
4'd6: partial_fast=16'd1055;
4'd7: partial_fast=16'd918;
4'd8: partial_fast=16'd1422;
4'd9: partial_fast=16'd2158;
4'd10: partial_fast=16'd816;
4'd11: partial_fast=16'd1449;
default: partial_fast=16'd0;
endcase
3'd2: case(idx) // Mi
4'd0: partial_fast=16'd1297;
4'd1: partial_fast=16'd810;
4'd2: partial_fast=16'd1505;
4'd3: partial_fast=16'd2004;
4'd4: partial_fast=16'd1300;
4'd5: partial_fast=16'd2422;
4'd6: partial_fast=16'd1344;
4'd7: partial_fast=16'd2237;
4'd8: partial_fast=16'd1673;
4'd9: partial_fast=16'd1153;
4'd10: partial_fast=16'd1445;
4'd11: partial_fast=16'd1888;
default: partial_fast=16'd0;
endcase
3'd3: case(idx) // Fa
4'd0: partial_fast=16'd656;
4'd1: partial_fast=16'd1114;
4'd2: partial_fast=16'd237;
4'd3: partial_fast=16'd515;
4'd4: partial_fast=16'd1236;
4'd5: partial_fast=16'd1343;
4'd6: partial_fast=16'd1552;
4'd7: partial_fast=16'd1253;
4'd8: partial_fast=16'd816;
4'd9: partial_fast=16'd1118;
4'd10: partial_fast=16'd1516;
4'd11: partial_fast=16'd1522;
default: partial_fast=16'd0;
endcase
3'd4: case(idx) // Sol
4'd0: partial_fast=16'd653;
4'd1: partial_fast=16'd922;
4'd2: partial_fast=16'd1665;
4'd3: partial_fast=16'd922;
4'd4: partial_fast=16'd1278;
4'd5: partial_fast=16'd630;
4'd6: partial_fast=16'd1737;
4'd7: partial_fast=16'd978;
4'd8: partial_fast=16'd1240;
4'd9: partial_fast=16'd793;
4'd10: partial_fast=16'd947;
4'd11: partial_fast=16'd172;
default: partial_fast=16'd0;
endcase
3'd5: case(idx) // La
4'd0: partial_fast=16'd554;
4'd1: partial_fast=16'd150;
4'd2: partial_fast=16'd1461;
4'd3: partial_fast=16'd1372;
4'd4: partial_fast=16'd1304;
4'd5: partial_fast=16'd2307;
4'd6: partial_fast=16'd1237;
4'd7: partial_fast=16'd1903;
4'd8: partial_fast=16'd499;
4'd9: partial_fast=16'd354;
4'd10: partial_fast=16'd3530;
4'd11: partial_fast=16'd316;
default: partial_fast=16'd0;
endcase
3'd6: case(idx) // Si
4'd0: partial_fast=16'd1412;
4'd1: partial_fast=16'd795;
4'd2: partial_fast=16'd2442;
4'd3: partial_fast=16'd2512;
4'd4: partial_fast=16'd4241;
4'd5: partial_fast=16'd755;
4'd6: partial_fast=16'd1791;
4'd7: partial_fast=16'd3399;
4'd8: partial_fast=16'd2285;
4'd9: partial_fast=16'd2373;
4'd10: partial_fast=16'd1256;
4'd11: partial_fast=16'd1237;
default: partial_fast=16'd0;
endcase
4'd7: case(idx) // C5
4'd0: partial_fast=16'd176;
4'd1: partial_fast=16'd1858;
4'd2: partial_fast=16'd180;
4'd3: partial_fast=16'd2470;
4'd4: partial_fast=16'd1734;
4'd5: partial_fast=16'd1022;
4'd6: partial_fast=16'd1224;
4'd7: partial_fast=16'd536;
4'd8: partial_fast=16'd285;
4'd9: partial_fast=16'd200;
4'd10: partial_fast=16'd150;
4'd11: partial_fast=16'd150;
default: partial_fast=16'd0;
endcase
4'd8: case(idx) // D5
4'd0: partial_fast=16'd1063;
4'd1: partial_fast=16'd1934;
4'd2: partial_fast=16'd1296;
4'd3: partial_fast=16'd806;
4'd4: partial_fast=16'd1218;
4'd5: partial_fast=16'd2193;
4'd6: partial_fast=16'd1201;
4'd7: partial_fast=16'd1053;
4'd8: partial_fast=16'd1128;
4'd9: partial_fast=16'd1019;
4'd10: partial_fast=16'd1298;
4'd11: partial_fast=16'd1282;
default: partial_fast=16'd0;
endcase
4'd9: case(idx) // Cs4
4'd0: partial_fast=16'd461;
4'd1: partial_fast=16'd552;
4'd2: partial_fast=16'd911;
4'd3: partial_fast=16'd1243;
4'd4: partial_fast=16'd1229;
4'd5: partial_fast=16'd1247;
4'd6: partial_fast=16'd1421;
4'd7: partial_fast=16'd1982;
4'd8: partial_fast=16'd757;
4'd9: partial_fast=16'd1407;
4'd10: partial_fast=16'd774;
4'd11: partial_fast=16'd861;
default: partial_fast=16'd0;
endcase
4'd10: case(idx) // Ds4
4'd0: partial_fast=16'd1068;
4'd1: partial_fast=16'd1127;
4'd2: partial_fast=16'd1160;
4'd3: partial_fast=16'd1047;
4'd4: partial_fast=16'd1013;
4'd5: partial_fast=16'd1653;
4'd6: partial_fast=16'd2023;
4'd7: partial_fast=16'd895;
4'd8: partial_fast=16'd2255;
4'd9: partial_fast=16'd1164;
4'd10: partial_fast=16'd1255;
4'd11: partial_fast=16'd1632;
default: partial_fast=16'd0;
endcase
4'd11: case(idx) // Fs4
4'd0: partial_fast=16'd682;
4'd1: partial_fast=16'd1218;
4'd2: partial_fast=16'd1233;
4'd3: partial_fast=16'd682;
4'd4: partial_fast=16'd975;
4'd5: partial_fast=16'd662;
4'd6: partial_fast=16'd1662;
4'd7: partial_fast=16'd1231;
4'd8: partial_fast=16'd990;
4'd9: partial_fast=16'd316;
4'd10: partial_fast=16'd941;
4'd11: partial_fast=16'd1260;
default: partial_fast=16'd0;
endcase
4'd12: case(idx) // Gs4
4'd0: partial_fast=16'd1294;
4'd1: partial_fast=16'd926;
4'd2: partial_fast=16'd1745;
4'd3: partial_fast=16'd1836;
4'd4: partial_fast=16'd432;
4'd5: partial_fast=16'd1431;
4'd6: partial_fast=16'd2713;
4'd7: partial_fast=16'd933;
4'd8: partial_fast=16'd1303;
4'd9: partial_fast=16'd875;
4'd10: partial_fast=16'd1038;
4'd11: partial_fast=16'd1158;
default: partial_fast=16'd0;
endcase
4'd13: case(idx) // As4
4'd0: partial_fast=16'd929;
4'd1: partial_fast=16'd1271;
4'd2: partial_fast=16'd1871;
4'd3: partial_fast=16'd2635;
4'd4: partial_fast=16'd3196;
4'd5: partial_fast=16'd3480;
4'd6: partial_fast=16'd1002;
4'd7: partial_fast=16'd1127;
4'd8: partial_fast=16'd1875;
4'd9: partial_fast=16'd1982;
4'd10: partial_fast=16'd2035;
4'd11: partial_fast=16'd1273;
default: partial_fast=16'd0;
endcase
4'd14: case(idx) // Cs5
4'd0: partial_fast=16'd1487;
4'd1: partial_fast=16'd1709;
4'd2: partial_fast=16'd605;
4'd3: partial_fast=16'd1505;
4'd4: partial_fast=16'd1579;
4'd5: partial_fast=16'd2045;
4'd6: partial_fast=16'd3634;
4'd7: partial_fast=16'd1492;
4'd8: partial_fast=16'd1823;
4'd9: partial_fast=16'd1664;
4'd10: partial_fast=16'd1535;
4'd11: partial_fast=16'd1514;
default: partial_fast=16'd0;
endcase
4'd15: case(idx) // Ds5
4'd0: partial_fast=16'd1930;
4'd1: partial_fast=16'd2149;
4'd2: partial_fast=16'd1837;
4'd3: partial_fast=16'd2583;
4'd4: partial_fast=16'd2295;
4'd5: partial_fast=16'd3098;
4'd6: partial_fast=16'd1923;
4'd7: partial_fast=16'd1867;
4'd8: partial_fast=16'd1921;
4'd9: partial_fast=16'd1927;
4'd10: partial_fast=16'd2029;
4'd11: partial_fast=16'd2022;
default: partial_fast=16'd0;
endcase
default: partial_fast=16'd0;
endcase end
endfunction
function [15:0] partial_slow;
input [3:0] note;
input [3:0] idx;
begin case(note)
3'd0: case(idx) // Do
4'd0: partial_slow=16'd493;
4'd1: partial_slow=16'd941;
4'd2: partial_slow=16'd1116;
4'd3: partial_slow=16'd540;
4'd4: partial_slow=16'd261;
4'd5: partial_slow=16'd463;
4'd6: partial_slow=16'd697;
4'd7: partial_slow=16'd87;
4'd8: partial_slow=16'd87;
4'd9: partial_slow=16'd245;
4'd10: partial_slow=16'd87;
4'd11: partial_slow=16'd87;
default: partial_slow=16'd0;
endcase
3'd1: case(idx) // Re
4'd0: partial_slow=16'd631;
4'd1: partial_slow=16'd1038;
4'd2: partial_slow=16'd583;
4'd3: partial_slow=16'd788;
4'd4: partial_slow=16'd709;
4'd5: partial_slow=16'd734;
4'd6: partial_slow=16'd403;
4'd7: partial_slow=16'd457;
4'd8: partial_slow=16'd858;
4'd9: partial_slow=16'd876;
4'd10: partial_slow=16'd722;
4'd11: partial_slow=16'd631;
default: partial_slow=16'd0;
endcase
3'd2: case(idx) // Mi
4'd0: partial_slow=16'd480;
4'd1: partial_slow=16'd817;
4'd2: partial_slow=16'd330;
4'd3: partial_slow=16'd172;
4'd4: partial_slow=16'd60;
4'd5: partial_slow=16'd446;
4'd6: partial_slow=16'd518;
4'd7: partial_slow=16'd513;
4'd8: partial_slow=16'd452;
4'd9: partial_slow=16'd543;
4'd10: partial_slow=16'd641;
4'd11: partial_slow=16'd664;
default: partial_slow=16'd0;
endcase
3'd3: case(idx) // Fa
4'd0: partial_slow=16'd657;
4'd1: partial_slow=16'd871;
4'd2: partial_slow=16'd831;
4'd3: partial_slow=16'd835;
4'd4: partial_slow=16'd1159;
4'd5: partial_slow=16'd719;
4'd6: partial_slow=16'd656;
4'd7: partial_slow=16'd1013;
4'd8: partial_slow=16'd701;
4'd9: partial_slow=16'd664;
4'd10: partial_slow=16'd710;
4'd11: partial_slow=16'd668;
default: partial_slow=16'd0;
endcase
3'd4: case(idx) // Sol
4'd0: partial_slow=16'd629;
4'd1: partial_slow=16'd597;
4'd2: partial_slow=16'd598;
4'd3: partial_slow=16'd897;
4'd4: partial_slow=16'd986;
4'd5: partial_slow=16'd928;
4'd6: partial_slow=16'd875;
4'd7: partial_slow=16'd351;
4'd8: partial_slow=16'd779;
4'd9: partial_slow=16'd732;
4'd10: partial_slow=16'd644;
4'd11: partial_slow=16'd703;
default: partial_slow=16'd0;
endcase
3'd5: case(idx) // La
4'd0: partial_slow=16'd622;
4'd1: partial_slow=16'd680;
4'd2: partial_slow=16'd332;
4'd3: partial_slow=16'd209;
4'd4: partial_slow=16'd562;
4'd5: partial_slow=16'd544;
4'd6: partial_slow=16'd850;
4'd7: partial_slow=16'd760;
4'd8: partial_slow=16'd571;
4'd9: partial_slow=16'd479;
4'd10: partial_slow=16'd528;
4'd11: partial_slow=16'd484;
default: partial_slow=16'd0;
endcase
3'd6: case(idx) // Si
4'd0: partial_slow=16'd60;
4'd1: partial_slow=16'd1100;
4'd2: partial_slow=16'd526;
4'd3: partial_slow=16'd866;
4'd4: partial_slow=16'd900;
4'd5: partial_slow=16'd833;
4'd6: partial_slow=16'd528;
4'd7: partial_slow=16'd524;
4'd8: partial_slow=16'd446;
4'd9: partial_slow=16'd418;
4'd10: partial_slow=16'd314;
4'd11: partial_slow=16'd293;
default: partial_slow=16'd0;
endcase
4'd7: case(idx) // C5
4'd0: partial_slow=16'd1109;
4'd1: partial_slow=16'd371;
4'd2: partial_slow=16'd475;
4'd3: partial_slow=16'd599;
4'd4: partial_slow=16'd564;
4'd5: partial_slow=16'd1042;
4'd6: partial_slow=16'd856;
4'd7: partial_slow=16'd825;
4'd8: partial_slow=16'd971;
4'd9: partial_slow=16'd838;
4'd10: partial_slow=16'd940;
4'd11: partial_slow=16'd838;
default: partial_slow=16'd0;
endcase
4'd8: case(idx) // D5
4'd0: partial_slow=16'd1441;
4'd1: partial_slow=16'd841;
4'd2: partial_slow=16'd474;
4'd3: partial_slow=16'd684;
4'd4: partial_slow=16'd343;
4'd5: partial_slow=16'd1063;
4'd6: partial_slow=16'd1188;
4'd7: partial_slow=16'd1214;
4'd8: partial_slow=16'd1206;
4'd9: partial_slow=16'd1096;
4'd10: partial_slow=16'd1480;
4'd11: partial_slow=16'd1004;
default: partial_slow=16'd0;
endcase
4'd9: case(idx) // Cs4
4'd0: partial_slow=16'd926;
4'd1: partial_slow=16'd1195;
4'd2: partial_slow=16'd457;
4'd3: partial_slow=16'd448;
4'd4: partial_slow=16'd596;
4'd5: partial_slow=16'd545;
4'd6: partial_slow=16'd475;
4'd7: partial_slow=16'd643;
4'd8: partial_slow=16'd724;
4'd9: partial_slow=16'd591;
4'd10: partial_slow=16'd814;
4'd11: partial_slow=16'd783;
default: partial_slow=16'd0;
endcase
4'd10: case(idx) // Ds4
4'd0: partial_slow=16'd685;
4'd1: partial_slow=16'd1005;
4'd2: partial_slow=16'd500;
4'd3: partial_slow=16'd440;
4'd4: partial_slow=16'd519;
4'd5: partial_slow=16'd233;
4'd6: partial_slow=16'd125;
4'd7: partial_slow=16'd332;
4'd8: partial_slow=16'd514;
4'd9: partial_slow=16'd463;
4'd10: partial_slow=16'd655;
4'd11: partial_slow=16'd662;
default: partial_slow=16'd0;
endcase
4'd11: case(idx) // Fs4
4'd0: partial_slow=16'd727;
4'd1: partial_slow=16'd382;
4'd2: partial_slow=16'd615;
4'd3: partial_slow=16'd598;
4'd4: partial_slow=16'd796;
4'd5: partial_slow=16'd680;
4'd6: partial_slow=16'd586;
4'd7: partial_slow=16'd580;
4'd8: partial_slow=16'd581;
4'd9: partial_slow=16'd636;
4'd10: partial_slow=16'd615;
4'd11: partial_slow=16'd617;
default: partial_slow=16'd0;
endcase
4'd12: case(idx) // Gs4
4'd0: partial_slow=16'd677;
4'd1: partial_slow=16'd230;
4'd2: partial_slow=16'd81;
4'd3: partial_slow=16'd324;
4'd4: partial_slow=16'd172;
4'd5: partial_slow=16'd711;
4'd6: partial_slow=16'd556;
4'd7: partial_slow=16'd741;
4'd8: partial_slow=16'd552;
4'd9: partial_slow=16'd394;
4'd10: partial_slow=16'd568;
4'd11: partial_slow=16'd549;
default: partial_slow=16'd0;
endcase
4'd13: case(idx) // As4
4'd0: partial_slow=16'd193;
4'd1: partial_slow=16'd478;
4'd2: partial_slow=16'd85;
4'd3: partial_slow=16'd380;
4'd4: partial_slow=16'd854;
4'd5: partial_slow=16'd480;
4'd6: partial_slow=16'd757;
4'd7: partial_slow=16'd514;
4'd8: partial_slow=16'd201;
4'd9: partial_slow=16'd206;
4'd10: partial_slow=16'd228;
4'd11: partial_slow=16'd280;
default: partial_slow=16'd0;
endcase
4'd14: case(idx) // Cs5
4'd0: partial_slow=16'd304;
4'd1: partial_slow=16'd250;
4'd2: partial_slow=16'd418;
4'd3: partial_slow=16'd493;
4'd4: partial_slow=16'd664;
4'd5: partial_slow=16'd333;
4'd6: partial_slow=16'd563;
4'd7: partial_slow=16'd299;
4'd8: partial_slow=16'd307;
4'd9: partial_slow=16'd281;
4'd10: partial_slow=16'd297;
4'd11: partial_slow=16'd294;
default: partial_slow=16'd0;
endcase
4'd15: case(idx) // Ds5
4'd0: partial_slow=16'd300;
4'd1: partial_slow=16'd435;
4'd2: partial_slow=16'd305;
4'd3: partial_slow=16'd590;
4'd4: partial_slow=16'd515;
4'd5: partial_slow=16'd390;
4'd6: partial_slow=16'd312;
4'd7: partial_slow=16'd281;
4'd8: partial_slow=16'd310;
4'd9: partial_slow=16'd285;
4'd10: partial_slow=16'd306;
4'd11: partial_slow=16'd313;
default: partial_slow=16'd0;
endcase
default: partial_slow=16'd0;
endcase end
endfunction
