// Screen UART 115200 8N1. Drop invalid stop bits, time out partial packets.
module tjc_hmi_rx #(parameter integer CLK_HZ=50000000, BAUD=115200)(
 input wire clk,reset_n,rx,
 output reg timbre_valid, volume_valid, gain_valid, resync_request,
 output reg [1:0] timbre_value,
 output reg [8:0] volume_value,
 output reg [6:0] gain_value,
 output reg note_valid, output reg [4:0] note_value,
 output reg mask_valid, output reg [15:0] mask_value
);
    localparam integer BIT_CYCLES = (CLK_HZ + BAUD/2)/BAUD;
    reg rx_meta, rx_sync;
    reg [1:0] rx_state;
    reg [15:0] rx_timer;
    reg [2:0] rx_bit;
    reg [7:0] rx_shift, rx_byte;
    reg rx_valid, rx_bad;
    always @(posedge clk) begin
        if (!reset_n) begin
            rx_meta<=1; rx_sync<=1; rx_state<=0; rx_timer<=0;
            rx_bit<=0; rx_shift<=0; rx_byte<=0; rx_valid<=0;rx_bad<=0;
        end else begin
            rx_meta<=rx; rx_sync<=rx_meta; rx_valid<=0;rx_bad<=0;
            case (rx_state)
                0: if (!rx_sync) begin rx_timer<=BIT_CYCLES/2-1; rx_state<=1; end
                1: if (rx_timer!=0) rx_timer<=rx_timer-1'b1;
                   else if (rx_sync) rx_state<=0;
                   else begin rx_timer<=BIT_CYCLES-1; rx_bit<=0; rx_state<=2; end
                2: if (rx_timer!=0) rx_timer<=rx_timer-1'b1;
                   else begin
                       rx_shift[rx_bit]<=rx_sync; rx_timer<=BIT_CYCLES-1;
                       if (rx_bit==7) rx_state<=3;
                       else rx_bit<=rx_bit+1'b1;
                   end
                3: if (rx_timer!=0) rx_timer<=rx_timer-1'b1;
                   else begin
                       rx_byte<=rx_shift; rx_valid<=rx_sync;rx_bad<=!rx_sync; rx_state<=0;
                   end
            endcase
        end
    end

    reg [4:0] packet_state;
    reg [15:0] mask_pending;
    reg [7:0] packet_value;
    reg packet_high_zero;
    reg [19:0] packet_timeout;
    
    always @(posedge clk) begin
        if (!reset_n) begin
            packet_state<=0; packet_value<=0; packet_high_zero<=0;
            packet_timeout<=0; timbre_valid<=0; timbre_value<=0; volume_value<=9'd256;volume_valid<=0;gain_valid<=0;gain_value<=64;
            resync_request<=0;note_valid<=0;mask_valid<=0;note_value<=16;mask_valid<=0;mask_value<=0;mask_pending<=0;
        end else begin
            timbre_valid<=0;volume_valid<=0;gain_valid<=0;resync_request<=0;note_valid<=0;mask_valid<=0;
            if (packet_state!=0) begin
                if (packet_timeout==CLK_HZ/100) packet_state<=0;
                else packet_timeout<=packet_timeout+1'b1;
            end
            if(rx_bad) packet_state<=0;
            if (rx_valid) begin
                packet_timeout<=0;
                case (packet_state)
                    0: if (rx_byte==8'ha5) packet_state<=1;
                    1: packet_state<=rx_byte==8'h10 ? 2 : rx_byte==8'h20 ? 3 :
                                     rx_byte==8'h30 ? 9 : rx_byte==8'h40 ? 10 : rx_byte==8'h50 ? 12 : rx_byte==8'h51 ? 14 : rx_byte==8'ha5 ? 1 : 0;
                    2: begin packet_value<=rx_byte; packet_state<=4; end
                    3: begin packet_value<=rx_byte; packet_high_zero<=1; packet_state<=5; end
                    4: begin
                        if (rx_byte==8'h5a && packet_value<4) begin
                            timbre_value<=packet_value[1:0]; timbre_valid<=1;
                        end
                        packet_state<=0;
                    end
                    5,6,7: begin
                        packet_high_zero<=packet_high_zero && rx_byte==0;
                        packet_state<=packet_state+1'b1;
                    end
                    8: begin
                        if (rx_byte==8'h5a && packet_high_zero) begin
                            volume_value<=packet_value==0 ? 9'd0 : {1'b0,packet_value}+9'd1;volume_valid<=1;end
                        packet_state<=0;
                    end
                    9: begin
                        if (rx_byte==8'h5a) resync_request<=1;
                        packet_state<=0;
                    end
                    10: begin packet_value<=rx_byte;packet_state<=11;end
                    11: begin
                        if(rx_byte==8'h5a && (packet_value==1 || packet_value==4 || packet_value==16 || packet_value==32 || packet_value==64)) begin
                            gain_value<=packet_value[6:0];gain_valid<=1;
                        end
                        packet_state<=0;
                    end
                    12: begin packet_value<=rx_byte;packet_state<=13;end
                    13: begin
                        if(rx_byte==8'h5a && packet_value<=16)begin note_value<=packet_value[4:0];note_valid<=1;end
                        packet_state<=0;
                    end
                    14: begin packet_value<=rx_byte;packet_state<=15;end
                    15: begin mask_pending<={rx_byte,packet_value};packet_state<=16;end
                    16: begin
                        if(rx_byte==8'h5a)begin mask_value<=mask_pending;mask_valid<=1;end
                        packet_state<=0;
                    end
                    default: packet_state<=0;
                endcase
            end
        end
    end

endmodule
