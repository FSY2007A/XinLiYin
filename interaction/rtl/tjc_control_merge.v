// Last valid event wins; PC has explicit priority on the same clock.
module tjc_control_merge(
 input wire clk,reset_n,pc_volume_valid,screen_volume_valid,pc_gain_valid,screen_gain_valid,
 input wire [8:0] pc_volume,screen_volume,
 input wire [6:0] pc_gain,screen_gain,
 output reg [8:0] volume, output reg [6:0] gain, output reg gain_valid
);
 always @(posedge clk) begin
  if(!reset_n) begin volume<=256;gain<=64;gain_valid<=0;end
  else begin
   gain_valid<=0;
   if(pc_volume_valid) volume<=pc_volume;
   else if(screen_volume_valid) volume<=screen_volume;
   if(pc_gain_valid) begin gain<=pc_gain;gain_valid<=1;end
   else if(screen_gain_valid) begin gain<=screen_gain;gain_valid<=1;end
  end
 end
endmodule
