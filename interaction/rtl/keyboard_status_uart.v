// Read-only 115200 8N1 display telemetry. No UART command can modify HID notes.
// F2/zero -> F3: same held/timbre/audio-ready/audio-fault/octave format as laptop.
// F4/zero -> F5: a={invalid,keyboard_ready}, b=2 (J18 source), c=1 (revision).
// F6/zero -> F7 a b c d e check: unsigned 16-bit L/R peaks packed into 5x7 bits.
// Peaks cover the latest 20ms of final DAC samples, including -32768 => 32768.
// F8/zero -> F9 seq (a b c)x64 xor: signed left DAC samples, 4096 clocks apart.
module keyboard_status_uart #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200,
    parameter integer NOTE_ECHO = 0,
    parameter integer SOURCE_ID = 2,
    parameter integer VOLUME_CONTROL = 0
)(
    input wire clk, reset_n, rx,
    output reg tx,
    input wire [15:0] held,
    input wire [1:0] timbre,
    input wire audio_ready, audio_fault, octave, keyboard_ready, invalid_report,
    input wire [15:0] pcm_left, pcm_right,
    input wire note_snapshot,
    input wire [8:0] volume_target,volume_applied,
    output wire [1023:0] hmi_wave_history
);
    localparam integer BIT_CYCLES = (CLK_HZ + BAUD/2)/BAUD;
    localparam integer GAP_CYCLES = CLK_HZ/1000*5;
    localparam integer PEAK_CYCLES = CLK_HZ/50;
    localparam integer PEAK_BITS = PEAK_CYCLES > 1 ? $clog2(PEAK_CYCLES) : 1;
    reg [PEAK_BITS-1:0] peak_timer;
    reg [15:0] peak_left, peak_right, published_left, published_right;
    wire [15:0] magnitude_left = pcm_left[15] ? (~pcm_left + 16'd1) : pcm_left;
    wire [15:0] magnitude_right = pcm_right[15] ? (~pcm_right + 16'd1) : pcm_right;
    wire [15:0] maximum_left = magnitude_left > peak_left ? magnitude_left : peak_left;
    wire [15:0] maximum_right = magnitude_right > peak_right ? magnitude_right : peak_right;
    reg [11:0] wave_divider;
    reg [1023:0] wave_history, wave_snapshot;
    assign hmi_wave_history=wave_history;
    reg [6:0] wave_sequence, next_sequence, wave_checksum;
    reg [1:0] wave_phase;
    always @(posedge clk) begin
        if(!reset_n) begin wave_divider<=0;wave_history<=0;end
        else begin
            wave_divider<=wave_divider+1'b1;
            if(wave_divider==12'hfff) wave_history<={pcm_left,wave_history[1023:16]};
        end
    end
    always @(posedge clk) begin
        if(!reset_n) begin
            peak_timer<=0;peak_left<=0;peak_right<=0;published_left<=0;published_right<=0;
        end else if(peak_timer == PEAK_CYCLES-1) begin
            peak_timer<=0;published_left<=maximum_left;published_right<=maximum_right;
            peak_left<=0;peak_right<=0;
        end else begin
            peak_timer<=peak_timer+1'b1;peak_left<=maximum_left;peak_right<=maximum_right;
        end
    end
    reg rx_meta, rx_sync;
    reg [1:0] rx_state;
    reg [15:0] rx_timer;
    reg [2:0] rx_bit;
    reg [7:0] rx_shift, byte_data;
    reg byte_valid, byte_bad;
    always @(posedge clk) begin
        if (!reset_n) begin
            rx_meta<=1;rx_sync<=1;rx_state<=0;rx_timer<=0;rx_bit<=0;
            rx_shift<=0;byte_data<=0;byte_valid<=0;byte_bad<=0;
        end else begin
            rx_meta<=rx;rx_sync<=rx_meta;byte_valid<=0;byte_bad<=0;
            case(rx_state)
                0: if(!rx_sync) begin rx_timer<=BIT_CYCLES/2-1;rx_state<=1;end
                1: if(rx_timer!=0) rx_timer<=rx_timer-1'b1;
                   else if(rx_sync) rx_state<=0;
                   else begin rx_timer<=BIT_CYCLES-1;rx_bit<=0;rx_state<=2;end
                2: if(rx_timer!=0) rx_timer<=rx_timer-1'b1;
                   else begin
                       rx_shift[rx_bit]<=rx_sync;rx_timer<=BIT_CYCLES-1;
                       if(rx_bit==7) rx_state<=3;else rx_bit<=rx_bit+1'b1;
                   end
                3: if(rx_timer!=0) rx_timer<=rx_timer-1'b1;
                   else begin
                       byte_data<=rx_shift;byte_valid<=rx_sync;byte_bad<=!rx_sync;rx_state<=0;
                   end
            endcase
        end
    end
    reg [2:0] packet_index;
    reg [6:0] checksum;
    reg [31:0] gap_timer;
    reg [2:0] query_kind;
    reg all_zero, request_status, request_health, request_level, request_wave, request_volume;
    always @(posedge clk) begin
        if(!reset_n) begin
            packet_index<=0;checksum<=0;gap_timer<=0;query_kind<=0;all_zero<=1;
            request_status<=0;request_health<=0;request_level<=0;request_wave<=0;request_volume<=0;
        end else begin
            request_status<=0;request_health<=0;request_level<=0;request_wave<=0;request_volume<=0;
            if(gap_timer<GAP_CYCLES) gap_timer<=gap_timer+1'b1;
            if(gap_timer==GAP_CYCLES-1 || byte_bad) packet_index<=0;
            if(byte_valid) begin
                gap_timer<=0;
                if(byte_data==8'hf2 || byte_data==8'hf4 || byte_data==8'hf6 || byte_data==8'hf8 ||
                   (VOLUME_CONTROL!=0 && byte_data==8'hfc)) begin
                    packet_index<=1;checksum<=0;all_zero<=1;
                    query_kind<=byte_data==8'hfc ? 3'd4 : byte_data==8'hf8 ? 3'd3 : byte_data==8'hf6 ? 3'd2 : byte_data==8'hf4 ? 3'd1 : 3'd0;
                end else if(byte_data[7]) packet_index<=0;
                else case(packet_index)
                    1,2,3: begin
                        checksum<=checksum^byte_data[6:0];
                        all_zero<=all_zero && byte_data==0;
                        packet_index<=packet_index+1'b1;
                    end
                    4: begin
                        if(all_zero && byte_data[6:0]==checksum) begin
                            case(query_kind)
                                0:request_status<=1;
                                1:request_health<=1;
                                2:request_level<=1;
                                3:request_wave<=1;
                                4:request_volume<=1;
                            endcase
                        end
                        packet_index<=0;
                    end
                    default: packet_index<=0;
                endcase
            end
        end
    end
    reg [55:0] reply;
    reg [15:0] tx_timer;
    reg [3:0] tx_bit;
    reg [7:0] tx_byte;
    reg tx_busy, status_pending, health_pending, level_pending, wave_pending, echo_pending, volume_pending, level_reply, wave_reply;
    reg [2:0] last_kind;
    wire want_status=status_pending || request_status;
    wire want_health=health_pending || request_health;
    wire want_level=level_pending || request_level;
    wire want_wave=wave_pending || request_wave;
    wire want_echo=NOTE_ECHO!=0 && (echo_pending || note_snapshot);
    wire want_volume=VOLUME_CONTROL!=0 && (volume_pending || request_volume);
    // Optional laptop echoes share the same serializer, so long scope replies cannot collide.
    wire [2:0] send_kind = last_kind==0 ? (want_health ? 3'd1 : want_level ? 3'd2 : want_wave ? 3'd3 : want_echo ? 3'd4 : want_volume ? 3'd5 : 3'd0) :
                           last_kind==1 ? (want_level ? 3'd2 : want_wave ? 3'd3 : want_echo ? 3'd4 : want_volume ? 3'd5 : want_status ? 3'd0 : 3'd1) :
                           last_kind==2 ? (want_wave ? 3'd3 : want_echo ? 3'd4 : want_volume ? 3'd5 : want_status ? 3'd0 : want_health ? 3'd1 : 3'd2) :
                           last_kind==3 ? (want_echo ? 3'd4 : want_volume ? 3'd5 : want_status ? 3'd0 : want_health ? 3'd1 : want_level ? 3'd2 : 3'd3) :
                           last_kind==4 ? (want_volume ? 3'd5 : want_status ? 3'd0 : want_health ? 3'd1 : want_level ? 3'd2 : want_wave ? 3'd3 : 3'd4) :
                                          (want_status ? 3'd0 : want_health ? 3'd1 : want_level ? 3'd2 : want_wave ? 3'd3 : want_echo ? 3'd4 : 3'd5);
    wire send_status=send_kind==0, send_level=send_kind==2, send_wave=send_kind==3, send_echo=send_kind==4, send_volume=send_kind==5;
    wire [6:0] wave_payload = wave_phase==0 ? wave_snapshot[6:0] :
                              wave_phase==1 ? wave_snapshot[13:7] : {5'd0,wave_snapshot[15:14]};
    wire [31:0] peak_pair={published_right,published_left};
    wire [6:0] a=send_volume ? volume_target[6:0] : send_level ? peak_pair[6:0] : send_status || send_echo ? held[6:0] : {5'd0,invalid_report,keyboard_ready};
    wire [6:0] b=send_volume ? {volume_applied[4:0],volume_target[8:7]} : send_level ? peak_pair[13:7] : send_status || send_echo ? held[13:7] : SOURCE_ID[6:0];
    wire [6:0] c=send_volume ? {3'd0,volume_applied[8:5]} : send_level ? peak_pair[20:14] : send_status ? {octave,audio_ready,audio_fault,timbre,held[15:14]} :
                 send_echo ? {5'd0,held[15:14]} : VOLUME_CONTROL!=0 ? 7'd2 : 7'd1;
    wire [6:0] d=peak_pair[27:21], e={3'd0,peak_pair[31:28]};
    always @(posedge clk) begin
        if(!reset_n) begin
            tx<=1;reply<=0;tx_timer<=0;tx_bit<=0;tx_byte<=0;tx_busy<=0;
            status_pending<=0;health_pending<=0;level_pending<=0;wave_pending<=0;echo_pending<=0;volume_pending<=0;
            last_kind<=5;level_reply<=0;wave_reply<=0;wave_snapshot<=0;
            wave_sequence<=0;next_sequence<=0;wave_checksum<=0;wave_phase<=0;
        end else begin
            status_pending<=want_status;health_pending<=want_health;level_pending<=want_level;wave_pending<=want_wave;
            echo_pending<=want_echo;
            volume_pending<=want_volume;
            if(!tx_busy) begin
                if(want_status || want_health || want_level || want_wave || want_echo || want_volume) begin
                    case(send_kind)
                        0:status_pending<=0;
                        1:health_pending<=0;
                        2:level_pending<=0;
                        3:wave_pending<=0;
                        4:echo_pending<=0;
                        5:volume_pending<=0;
                    endcase
                    last_kind<=send_kind;level_reply<=send_level;wave_reply<=send_wave;
                    if(send_wave) begin
                        wave_snapshot<=wave_history;wave_sequence<=next_sequence;
                        wave_checksum<=next_sequence;next_sequence<=next_sequence+1'b1;wave_phase<=0;
                    end
                    reply<=send_wave ? {48'd0,8'hf9} : send_level ? {1'b0,(a^b^c^d^e),1'b0,e,1'b0,d,1'b0,c,1'b0,b,1'b0,a,8'hf7} :
                                        {16'd0,1'b0,(a^b^c),1'b0,c,1'b0,b,1'b0,a,(send_volume ? 8'hfb : send_echo ? 8'hf1 : send_status ? 8'hf3 : 8'hf5)};
                    tx<=0;tx_timer<=BIT_CYCLES-1;tx_bit<=0;tx_byte<=0;tx_busy<=1;
                end
            end else if(tx_timer!=0) tx_timer<=tx_timer-1'b1;
            else begin
                tx_timer<=BIT_CYCLES-1;
                if(tx_bit<8) begin tx<=reply[0];reply<=reply>>1;tx_bit<=tx_bit+1'b1;end
                else if(tx_bit==8) begin tx<=1;tx_bit<=9;end
                else if(tx_byte==(wave_reply ? 8'd194 : level_reply ? 8'd6 : 8'd4)) begin tx<=1;tx_busy<=0;end
                else begin
                    tx<=0;tx_bit<=0;tx_byte<=tx_byte+1'b1;
                    if(wave_reply) begin
                        if(tx_byte==0) reply<={48'd0,1'b0,wave_sequence};
                        else if(tx_byte==193) reply<={48'd0,1'b0,wave_checksum};
                        else begin
                            reply<={48'd0,1'b0,wave_payload};wave_checksum<=wave_checksum^wave_payload;
                            if(wave_phase==2) begin wave_phase<=0;wave_snapshot<=wave_snapshot>>16;end
                            else wave_phase<=wave_phase+1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule
