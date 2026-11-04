// Generated from CC0 multisamples. Banks 0-3: erhu; 4-7: guzheng.
// Root groups follow the currently playable C4..D#6 range.
function [1:0] sample_root;
input [4:0] voice;
input [1:0] instrument;
begin
if(instrument==0) sample_root=voice<=1 ? 2'd0 : voice<=5 ? 2'd1 : voice<=8 ? 2'd2 : 2'd3;
else sample_root=voice<=6 ? 2'd0 : voice<=13 ? 2'd1 : voice<=15 ? 2'd2 : 2'd3;
end endfunction
function [3:0] sample_bank;
input [4:0] voice;
input [1:0] instrument;
begin sample_bank={1'b0,instrument,2'b00}+{2'b0,sample_root(voice,instrument)}; end
endfunction
function [76:0] sample_info;
input [3:0] bank;
begin case(bank)
4'd0: sample_info=77'h1A1808A6D5DCE30C00DA;
4'd1: sample_info=77'h18FC2205FD18998CFFEA;
4'd2: sample_info=77'h188319897063C90CFFE5;
4'd3: sample_info=77'h1943DE4CA8AC288CFFE4;
4'd4: sample_info=77'h01800020003FFF0C0001;
4'd5: sample_info=77'h01800280003FFF0C0014;
4'd6: sample_info=77'h019FFFA0003FFF0CFFFD;
4'd7: sample_info=77'h01800280003FFF0C0014;
default: sample_info=0; endcase end endfunction

// Q7 bank gain keeps the high guzheng register level with the other roots.
function [7:0] sample_gain;
input [3:0] bank;
begin sample_gain=bank==4'd7 ? 8'd247 : 8'd128; end
endfunction

// Q16 source-step increments for a 13 kHz bank and 48.828125 kHz output.
function [15:0] sample_increment;
input [4:0] voice;
input [5:0] note;
input [1:0] instrument;
integer root_offset;
integer semitone;
begin
if(instrument==0) root_offset=voice<=1 ? 0 : voice<=5 ? 4 : voice<=8 ? 7 : 9;
else root_offset=voice<=6 ? 0 : voice<=13 ? 7 : 14;
semitone=note-root_offset;
case(semitone+8)
0: sample_increment=16'd10992; // -8 semitones
1: sample_increment=16'd11645; // -7 semitones
2: sample_increment=16'd12338; // -6 semitones
3: sample_increment=16'd13071; // -5 semitones
4: sample_increment=16'd13849; // -4 semitones
5: sample_increment=16'd14672; // -3 semitones
6: sample_increment=16'd15545; // -2 semitones
7: sample_increment=16'd16469; // -1 semitones
8: sample_increment=16'd17448; // 0 semitones
9: sample_increment=16'd18486; // 1 semitones
10: sample_increment=16'd19585; // 2 semitones
11: sample_increment=16'd20750; // 3 semitones
12: sample_increment=16'd21983; // 4 semitones
13: sample_increment=16'd23291; // 5 semitones
14: sample_increment=16'd24676; // 6 semitones
15: sample_increment=16'd26143; // 7 semitones
16: sample_increment=16'd27697; // 8 semitones
17: sample_increment=16'd29344; // 9 semitones
18: sample_increment=16'd31089; // 10 semitones
19: sample_increment=16'd32938; // 11 semitones
20: sample_increment=16'd34897; // 12 semitones
21: sample_increment=16'd36972; // 13 semitones
22: sample_increment=16'd39170; // 14 semitones
23: sample_increment=16'd41499; // 15 semitones
24: sample_increment=16'd43967; // 16 semitones
25: sample_increment=16'd46581; // 17 semitones
26: sample_increment=16'd49351; // 18 semitones
default: sample_increment=16'd0;
endcase end endfunction

function [14:0] sample_step;
input [6:0] index;
begin case(index)
7'd0: sample_step=15'd7;
7'd1: sample_step=15'd8;
7'd2: sample_step=15'd9;
7'd3: sample_step=15'd10;
7'd4: sample_step=15'd11;
7'd5: sample_step=15'd12;
7'd6: sample_step=15'd13;
7'd7: sample_step=15'd14;
7'd8: sample_step=15'd16;
7'd9: sample_step=15'd17;
7'd10: sample_step=15'd19;
7'd11: sample_step=15'd21;
7'd12: sample_step=15'd23;
7'd13: sample_step=15'd25;
7'd14: sample_step=15'd28;
7'd15: sample_step=15'd31;
7'd16: sample_step=15'd34;
7'd17: sample_step=15'd37;
7'd18: sample_step=15'd41;
7'd19: sample_step=15'd45;
7'd20: sample_step=15'd50;
7'd21: sample_step=15'd55;
7'd22: sample_step=15'd60;
7'd23: sample_step=15'd66;
7'd24: sample_step=15'd73;
7'd25: sample_step=15'd80;
7'd26: sample_step=15'd88;
7'd27: sample_step=15'd97;
7'd28: sample_step=15'd107;
7'd29: sample_step=15'd118;
7'd30: sample_step=15'd130;
7'd31: sample_step=15'd143;
7'd32: sample_step=15'd157;
7'd33: sample_step=15'd173;
7'd34: sample_step=15'd190;
7'd35: sample_step=15'd209;
7'd36: sample_step=15'd230;
7'd37: sample_step=15'd253;
7'd38: sample_step=15'd279;
7'd39: sample_step=15'd307;
7'd40: sample_step=15'd337;
7'd41: sample_step=15'd371;
7'd42: sample_step=15'd408;
7'd43: sample_step=15'd449;
7'd44: sample_step=15'd494;
7'd45: sample_step=15'd544;
7'd46: sample_step=15'd598;
7'd47: sample_step=15'd658;
7'd48: sample_step=15'd724;
7'd49: sample_step=15'd796;
7'd50: sample_step=15'd876;
7'd51: sample_step=15'd963;
7'd52: sample_step=15'd1060;
7'd53: sample_step=15'd1166;
7'd54: sample_step=15'd1282;
7'd55: sample_step=15'd1411;
7'd56: sample_step=15'd1552;
7'd57: sample_step=15'd1707;
7'd58: sample_step=15'd1878;
7'd59: sample_step=15'd2066;
7'd60: sample_step=15'd2272;
7'd61: sample_step=15'd2499;
7'd62: sample_step=15'd2749;
7'd63: sample_step=15'd3024;
7'd64: sample_step=15'd3327;
7'd65: sample_step=15'd3660;
7'd66: sample_step=15'd4026;
7'd67: sample_step=15'd4428;
7'd68: sample_step=15'd4871;
7'd69: sample_step=15'd5358;
7'd70: sample_step=15'd5894;
7'd71: sample_step=15'd6484;
7'd72: sample_step=15'd7132;
7'd73: sample_step=15'd7845;
7'd74: sample_step=15'd8630;
7'd75: sample_step=15'd9493;
7'd76: sample_step=15'd10442;
7'd77: sample_step=15'd11487;
7'd78: sample_step=15'd12635;
7'd79: sample_step=15'd13899;
7'd80: sample_step=15'd15289;
7'd81: sample_step=15'd16818;
7'd82: sample_step=15'd18500;
7'd83: sample_step=15'd20350;
7'd84: sample_step=15'd22385;
7'd85: sample_step=15'd24623;
7'd86: sample_step=15'd27086;
7'd87: sample_step=15'd29794;
7'd88: sample_step=15'd32767;
default: sample_step=15'd32767;
endcase end
endfunction
