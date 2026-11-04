// Legacy momentary note plus latched screen chord; PC ownership stays independent.
module touch_note_merge #(parameter integer TIMEOUT_CYCLES=12500000)(
 input wire clk,reset_n,note_valid,clear_screen,
 input wire [4:0] note_value,
 input wire mask_valid,input wire [15:0] mask_value,
 input wire [15:0] pc_held,
 output wire [15:0] held,output reg changed
);
 localparam integer TIMER_BITS=TIMEOUT_CYCLES>1 ? $clog2(TIMEOUT_CYCLES) : 1;
 reg [TIMER_BITS-1:0] timer;
 reg [15:0] screen_held,previous;
 assign held=pc_held | screen_held;
 always @(posedge clk)begin
  if(!reset_n)begin screen_held<=0;timer<=0;previous<=0;changed<=0;end
  else begin
   previous<=held;changed<=held!=previous;
   if(clear_screen)begin screen_held<=0;timer<=0;end
   else if(mask_valid)begin screen_held<=mask_value;timer<=0;end
   else if(note_valid)begin
    screen_held<=note_value<16 ? (16'd1<<note_value) : 16'd0;timer<=0;
   end else if(screen_held!=0)begin
    if(timer==TIMEOUT_CYCLES-1)begin screen_held<=0;timer<=0;end
    else timer<=timer+1'b1;
   end
  end
 end
endmodule
