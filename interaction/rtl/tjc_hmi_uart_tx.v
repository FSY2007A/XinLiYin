// Duplex HMI: enable touch controls and send paced, complete waveform frames.
module tjc_hmi_uart_tx #(
    parameter integer CLK_HZ=50000000, BAUD=115200,
    parameter integer RESYNC_CYCLES=CLK_HZ*5
)(
    input wire clk,reset_n, resync_request,
    output reg tx,
    input wire [15:0] pcm_left,pcm_right,
    input wire [1:0] timbre,
    input wire [15:0] notes,
    input wire [8:0] volume_applied,volume_target,
    input wire [1023:0] wave_history,
    input wire [6:0] wave_gain,
    input wire wave_gain_valid
);
    localparam integer BIT_CYCLES=(CLK_HZ+BAUD/2)/BAUD;
    localparam integer TICK_CYCLES=CLK_HZ/1000;
    localparam integer FRAME_PAUSE=CLK_HZ/10;
    localparam integer FRAME_BITS=$clog2(FRAME_PAUSE+1);
    localparam integer RESYNC_BITS=RESYNC_CYCLES>1 ? $clog2(RESYNC_CYCLES) : 1;
    reg [RESYNC_BITS-1:0] resync_timer;
    reg resync_pending;
    wire resync_tick=resync_timer==RESYNC_CYCLES-1;
    always @(posedge clk)
        if(!reset_n)resync_timer<=0;
        else if(resync_tick)resync_timer<=0;
        else resync_timer<=resync_timer+1'b1;
    function [15:0] magnitude;
        input [15:0] sample;
        begin magnitude=sample[15] ? (~sample+16'd1) : sample;end
    endfunction
    function [7:0] meter_percent;
        input [15:0] peak;
        begin
            casez(peak)
                16'b1???????????????:meter_percent=100;
                16'b011?????????????:meter_percent=95;
                16'b010?????????????:meter_percent=90;
                16'b0011????????????:meter_percent=85;
                16'b0010????????????:meter_percent=80;
                16'b00011???????????:meter_percent=75;
                16'b00010???????????:meter_percent=70;
                16'b000011??????????:meter_percent=65;
                16'b000010??????????:meter_percent=60;
                16'b0000011?????????:meter_percent=55;
                16'b0000010?????????:meter_percent=50;
                16'b00000011????????:meter_percent=45;
                16'b00000010????????:meter_percent=40;
                16'b000000011???????:meter_percent=35;
                16'b000000010???????:meter_percent=30;
                16'b0000000011??????:meter_percent=25;
                16'b0000000010??????:meter_percent=20;
                16'b00000000011?????:meter_percent=15;
                16'b00000000010?????:meter_percent=10;
                16'b000000000011????:meter_percent=5;
                default:meter_percent=0;
            endcase
        end
    endfunction
    `include "animation_layout.vh"
    reg [15:0] peak_l,peak_r,meter_peak_l,meter_peak_r;
    wire [15:0] mag_l=magnitude(pcm_left),mag_r=magnitude(pcm_right);
    wire [15:0] max_l=mag_l>peak_l ? mag_l : peak_l;
    wire [15:0] max_r=mag_r>peak_r ? mag_r : peak_r;
    reg [7:0] level_l,level_r;
    reg [17:0] tick_timer;
    reg [4:0] meter_window;
    reg [2:0] slot;
    wire tick=tick_timer==TICK_CYCLES-1;
    reg [3:0] command_kind;
    reg [7:0] command_value;
    reg [5:0] command_index,page_delay,wave_index;
    reg [1023:0] wave_snapshot;
    wire [15:0] next_sample=wave_snapshot[15:0];
    reg [FRAME_BITS-1:0] frame_timer;
    reg wave_active,frame_draw_pending;
    reg [27:0] decimal_digits;
    reg [21:0] binary_value;
    reg [4:0] decimal_bits;
    reg [27:0] adjusted_digits;
    integer d;
    always @* begin
        adjusted_digits=decimal_digits;
        for(d=0;d<7;d=d+1)
            if(adjusted_digits[d*4+:4]>=5)adjusted_digits[d*4+:4]=adjusted_digits[d*4+:4]+4'd3;
    end
    reg command_active,tx_busy,page_valid;
    wire byte_ready=!tx_busy && (command_kind!=0 && command_kind!=6 && command_kind!=10 || command_index<3 || decimal_bits==0);
    reg [1:0] displayed_timbre,digits_pending;
    reg [15:0] displayed_notes;
    reg [7:0] displayed_level_l,displayed_level_r,displayed_volume,volume_snapshot;
    reg level_l_valid,level_r_valid,volume_valid,slider_pending,touch_pending,gain_pending;
    reg [6:0] pending_gain;
    reg [8:0] slider_target_seen;
    wire [7:0] volume_display=volume_applied[8] ? 8'd255 : volume_applied[7:0];
    wire [5:0] command_last=command_kind==0 ? 6'd11 : command_kind==5 ? 6'd8 :
        command_kind==6 ? 6'd23 : command_kind==11 ? 6'd19 : command_kind==7 ? 6'd12 : command_kind==9 ? 6'd22 :
        command_kind==10 ? 6'd8 : 6'd34;
    always @(posedge clk) begin
        if(!reset_n)begin
            tick_timer<=0;slot<=0;meter_window<=0;peak_l<=0;peak_r<=0;meter_peak_l<=0;meter_peak_r<=0;
            level_l<=0;level_r<=0;command_kind<=0;command_value<=0;command_index<=0;command_active<=0;
            page_valid<=0;displayed_timbre<=0;displayed_notes<=0;page_delay<=0;wave_index<=0;wave_snapshot<=0;
            decimal_digits<=0;binary_value<=0;decimal_bits<=0;
            displayed_level_l<=0;displayed_level_r<=0;displayed_volume<=0;volume_snapshot<=0;digits_pending<=0;
            level_l_valid<=0;level_r_valid<=0;volume_valid<=0;slider_pending<=0;touch_pending<=0;
            gain_pending<=0;pending_gain<=64;slider_target_seen<=0;resync_pending<=0;
            frame_timer<=0;wave_active<=0;frame_draw_pending<=0;
        end else begin
            if(frame_timer!=0)frame_timer<=frame_timer-1'b1;
            level_l<=meter_percent(meter_peak_l);level_r<=meter_percent(meter_peak_r);
            if(decimal_bits!=0)begin
                decimal_digits<={adjusted_digits[26:0],binary_value[21]};
                binary_value<=binary_value<<1;decimal_bits<=decimal_bits-1'b1;
            end
            if(tick)begin
                tick_timer<=0;slot<=slot+1'b1;
                meter_window<=meter_window==19 ? 5'd0 : meter_window+1'b1;
                if(meter_window==19)begin meter_peak_l<=max_l;meter_peak_r<=max_r;end
                if(!command_active && !tx_busy)begin
                    command_index<=0;command_active<=1;
                    if(!page_valid || displayed_timbre!=timbre || resync_pending)begin
                        command_kind<=5;command_value<={6'd0,timbre};displayed_timbre<=timbre;page_valid<=1;
                        displayed_notes<=~notes;page_delay<=40;wave_index<=0;slider_pending<=1;touch_pending<=1;
                        digits_pending<=0;level_l_valid<=0;level_r_valid<=0;volume_valid<=0;resync_pending<=0;
                        wave_active<=0;frame_draw_pending<=0;frame_timer<=0;
                        pending_gain<=wave_gain;gain_pending<=1;
                    end else if(page_delay!=0)begin page_delay<=page_delay-1'b1;command_active<=0;end
                    else if(touch_pending)begin command_kind<=9;touch_pending<=0;end
                    else if(notes!=displayed_notes)begin
                        command_kind<=6;binary_value<={6'd0,notes};decimal_digits<=0;decimal_bits<=22;displayed_notes<=notes;
                    end
                    else if(gain_pending)begin
                        command_kind<=10;binary_value<={15'd0,pending_gain};decimal_digits<=0;decimal_bits<=22;gain_pending<=0;
                    end else if(slider_pending)begin
                        command_kind<=7;command_value<=volume_target==0 ? 8'd0 : volume_target[8] ? 8'd255 : volume_target[7:0]-1'b1;
                        slider_pending<=0;
                    end else if(digits_pending!=0)begin
                        command_kind<=digits_pending==2 ? 4'd4 : 4'd8;
                        command_value<=digits_pending==2 ? (volume_snapshot/8'd10)%8'd10 : volume_snapshot%8'd10;
                        digits_pending<=digits_pending-1'b1;
                    end else if(slot==1 && (!level_l_valid || displayed_level_l!=level_l))begin
                        command_kind<=1;command_value<=level_l;displayed_level_l<=level_l;level_l_valid<=1;
                    end else if(slot==3 && (!level_r_valid || displayed_level_r!=level_r))begin
                        command_kind<=2;command_value<=level_r;displayed_level_r<=level_r;level_r_valid<=1;
                    end else if(slot==5 && (!volume_valid || displayed_volume!=volume_display))begin
                        command_kind<=3;command_value<=volume_display/8'd100;volume_snapshot<=volume_display;
                        digits_pending<=2;displayed_volume<=volume_display;volume_valid<=1;
                    end else if(frame_draw_pending)begin
                        command_kind<=11;frame_draw_pending<=0;frame_timer<=FRAME_PAUSE;
                    end else if(wave_active)begin
                        command_kind<=0;command_value<={2'd0,wave_index};
                        binary_value<={6'd0,~next_sample[15],next_sample[14:0]};
                        decimal_digits<=0;decimal_bits<=22;wave_index<=wave_index+1'b1;
                        wave_snapshot<=wave_snapshot>>32;
                        if(wave_index==31)begin wave_active<=0;frame_draw_pending<=1;end
                    end else if(frame_timer==0)begin
                        wave_snapshot<=wave_history;wave_index<=0;wave_active<=1;command_active<=0;
                    end else command_active<=0;
                end
            end else tick_timer<=tick_timer+1'b1;
            if(tick && meter_window==19)begin peak_l<=0;peak_r<=0;end
            else begin peak_l<=max_l;peak_r<=max_r;end
            if(command_active && byte_ready)begin
                if(command_index==command_last)command_active<=0;
                else command_index<=command_index+1'b1;
            end
            if((resync_tick && notes==0) || resync_request)resync_pending<=1;
            if(volume_target!=slider_target_seen)begin slider_target_seen<=volume_target;slider_pending<=1;end
            // New PC requests win if they coincide with serializing an older one.
            // Duplex controls share the same applied gain, also restored after reboot.
            if(wave_gain_valid)begin pending_gain<=wave_gain;gain_pending<=1;end
        end
    end
    function [7:0] digit;
        input [8:0] value;
        input [1:0] place;
        reg [8:0] decimal;
        begin
            case (place)
                0: decimal=value/9'd100;
                1: decimal=(value/9'd10)%9'd10;
                default: decimal=value%9'd10;
            endcase
            digit=8'd48+{4'd0,decimal[3:0]};
        end
    endfunction
    wire [7:0] meter_divided=command_value/8'd5;
    wire [4:0] meter_index=meter_divided[4:0];
    wire [17:0] meter_xy=meter_source(meter_index);
    wire [17:0] glyph_xy=digit_source(command_value[3:0]);
    wire [62:0] rectangle = command_kind==1 || command_kind==2 ?
        {command_kind==1 ? 9'd297 : 9'd325,9'd225,9'd14,9'd34,meter_xy,9'd10} :
        {command_kind==3 ? 9'd438 : command_kind==4 ? 9'd447 : 9'd456,
         9'd224,9'd9,9'd15,glyph_xy,9'd10};
    function [7:0] rectangle_char;
        input [5:0] index;
        input [62:0] fields;
        reg [8:0] value;
        reg [5:0] offset;
        begin
            rectangle_char=8'hff; value=0; offset=0;
            case(index)
                0:rectangle_char="x"; 1:rectangle_char="p";
                2:rectangle_char="i"; 3:rectangle_char="c"; 4:rectangle_char=" ";
                8,12,16,20,24,28:rectangle_char=",";
                default: if (index>=5 && index<=31) begin
                    offset=index-6'd5;
                    case (offset/6'd4)
                        0:value=fields[62:54]; 1:value=fields[53:45];
                        2:value=fields[44:36]; 3:value=fields[35:27];
                        4:value=fields[26:18]; 5:value=fields[17:9];
                        default:value=fields[8:0];
                    endcase
                    rectangle_char=digit(value,offset[1:0]);
                end
            endcase
        end
    endfunction
    function [7:0] command_char;
        input [3:0] kind;
        input [5:0] index;
        input [7:0] value;
        reg [5:0] position;
        reg [3:0] number;
        begin
            command_char=8'hff;position=0;number=0;
            if(kind==0)begin
                case(index)
                    0:command_char="w";
                    1:command_char=digit(value,1);
                    2:command_char=digit(value,2);
                    3:command_char="=";
                    default:if(index>=4 && index<=8)begin
                        position=8-index;number=(decimal_digits>>(position*4));command_char=8'd48+{4'd0,number};
                    end
                endcase
            end else if(kind==6 || kind==10)begin
                case(index)
                    0:command_char=kind==6 ? "n" : "w";
                    1:command_char=kind==6 ? "n" : kind==10 ? "g" : "p";
                    2:command_char="=";
                    default:begin
                        if(index>=3 && index<(kind==6 ? 8 : 6))begin
                            position=kind==6 ? 7-index : 5-index;
                            number=(decimal_digits>>(position*4));command_char=8'd48+{4'd0,number};
                        end else if(kind==6)begin
                            case(index)
                                11:command_char="c";12:command_char="l";13:command_char="i";
                                14:command_char="c";15:command_char="k";16:command_char=" ";
                                17:command_char="m";18:command_char="4";19:command_char=",";20:command_char="0";
                            endcase
                        end
                    end
                endcase
            end else if(kind==11)begin
                case(index)
                    0:command_char="w";1:command_char="f";2:command_char="=";3:command_char="1";
                    7:command_char="c";8:command_char="l";9:command_char="i";
                    10:command_char="c";11:command_char="k";12:command_char=" ";
                    13:command_char="m";14:command_char="4";15:command_char=",";16:command_char="0";
                endcase
            end else if(kind==9)begin
                case(index)
                    0,12:command_char="t";1,13:command_char="s";2,14:command_char="w";
                    3,15:command_char=" ";4,5,6:command_char="5";
                    7,18:command_char=",";8:command_char="1";
                    16:command_char="m";17:command_char="4";19:command_char="1";
                endcase
                if(index==4)command_char="2";
            end else if(kind==5)begin
                case(index)
                    0:command_char="p";1:command_char="a";2:command_char="g";3:command_char="e";
                    4:command_char=" ";5:command_char=digit(value,2);
                endcase
            end else if(kind==7)begin
                case(index)
                    0:command_char="h";1:command_char="0";2:command_char=".";
                    3:command_char="v";4:command_char="a";5:command_char="l";6:command_char="=";
                    7:command_char=digit(value,0);8:command_char=digit(value,1);9:command_char=digit(value,2);
                endcase
            end else command_char=rectangle_char(index,rectangle);
        end
    endfunction
    localparam [15:0] BIT_LAST=BIT_CYCLES-1;
    reg [15:0] tx_timer;
    reg [3:0] tx_bit;
    reg [7:0] tx_byte;
    always @(posedge clk)begin
        if(!reset_n)begin tx<=1;tx_busy<=0;tx_timer<=0;tx_bit<=0;tx_byte<=0;end
        else if(!tx_busy)begin
            tx<=1;
            if(command_active && byte_ready)begin
                tx_byte<=command_char(command_kind,command_index,command_value);
                tx<=0;tx_busy<=1;tx_bit<=0;tx_timer<=BIT_LAST;
            end
        end else if(tx_timer!=0)tx_timer<=tx_timer-1'b1;
        else begin
            tx_timer<=BIT_LAST;
            if(tx_bit<8)begin tx<=tx_byte[tx_bit];tx_bit<=tx_bit+1'b1;end
            else if(tx_bit==8)begin tx<=1;tx_bit<=9;end
            else tx_busy<=0;
        end
    end
endmodule
