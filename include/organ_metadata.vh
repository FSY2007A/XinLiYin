function [63:0] organ_info;
input [3:0] note;
begin case(note)
4'd0: organ_info=64'h01D2927C90800000;
4'd1: organ_info=64'h01E490FD78800000;
4'd2: organ_info=64'h01C99080C281FFFF;
4'd3: organ_info=64'h01D6D28240000000;
4'd4: organ_info=64'h01E1D2005C000000;
4'd5: organ_info=64'h01E9537F82800000;
4'd6: organ_info=64'h01EF10FF14800000;
4'd7: organ_info=64'h01D352FDB2800000;
4'd8: organ_info=64'h01D691FEAB800000;
4'd9: organ_info=64'h01D7D40041800000;
4'd10: organ_info=64'h01D714FD2281FFFF;
4'd11: organ_info=64'h01EED38126800000;
4'd12: organ_info=64'h01EA11800E000000;
4'd13: organ_info=64'h01E494807D000000;
4'd14: organ_info=64'h01DE12823B800000;
4'd15: organ_info=64'h01EA95FE4683FFFF;
default: organ_info=0;
endcase end endfunction
