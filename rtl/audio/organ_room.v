// Eight-line damped Householder room at 50MHz/4096, Q16.8 pooled RAM.
// Dry stays at the original sample rate. Only the wet network is decimated.
module organ_room #(parameter integer TAIL_STEPS=146484)(
    input wire clk, reset_n, sample_valid, enable,
    input wire signed [15:0] sample_in,
    output wire signed [15:0] left, right,
    output reg valid,
    output wire tail_active
);
    reg signed [23:0] memory[0:8191];
    reg [12:0] address, write_address;
    reg signed [23:0] q, write_data;
    reg write_enable;
    always @(posedge clk) begin
        q<=memory[address];
        if(write_enable) memory[write_address]<=write_data;
    end
    function [10:0] delay_length;
        input [2:0] i;
        begin case(i)
            0:delay_length=380;1:delay_length=455;2:delay_length=508;3:delay_length=606;
            4:delay_length=711;5:delay_length=804;6:delay_length=905;7:delay_length=1018;
        endcase end
    endfunction
    function [12:0] base_address;
        input [2:0] i;
        begin case(i)
            0:base_address=0;1:base_address=380;2:base_address=835;3:base_address=1343;
            4:base_address=1949;5:base_address=2660;6:base_address=3464;7:base_address=4369;
        endcase end
    endfunction
    function signed [15:0] feedback_gain;
        input [2:0] i;
        begin case(i)
            0:feedback_gain=30965;1:feedback_gain=30621;2:feedback_gain=30381;3:feedback_gain=29940;
            4:feedback_gain=29476;5:feedback_gain=29070;6:feedback_gain=28637;7:feedback_gain=28159;
        endcase end
    endfunction
    function signed [15:0] injection_gain;
        input [2:0] i;
        begin case(i)
            0:injection_gain=11585;1:injection_gain=-9268;2:injection_gain=8109;3:injection_gain=-10426;
            4:injection_gain=9268;5:injection_gain=-8109;6:injection_gain=10426;7:injection_gain=-11585;
        endcase end
    endfunction
    function signed [27:0] truncate15;
        input signed [43:0] value;
        begin truncate15=(value<0 ? value+44'sd32767 : value)>>>15;end
    endfunction
    function signed [23:0] saturate24;
        input signed [27:0] value;
        begin saturate24=value>28'sd8388607 ? 24'sh7fffff :
                         value< -28'sd8388608 ? 24'sh800000 : value[23:0];end
    endfunction
    function signed [15:0] pcm16;
        input signed [27:0] value;
        reg signed [27:0] rounded;
        begin
            rounded=(value<0 ? value+28'sd255 : value)>>>8;
            pcm16=rounded>32767 ? 16'sh7fff : rounded< -32768 ? 16'sh8000 : rounded[15:0];
        end
    endfunction
    reg [5:0] state;
    reg [2:0] line;
    reg [9:0] pointers[0:7],pre_pointer;
    reg signed [23:0] filtered[0:7],damped[0:7];
    reg [10:0] filled;
    reg [1:0] divider;
    reg mode;
    reg signed [17:0] input_sum;
    reg signed [23:0] input_q,pre_q,tap;
    reg signed [27:0] total,sum_left,sum_right,householder;
    reg signed [43:0] product_a,product_b;
    reg signed [27:0] early_left,early_right,wet_left,wet_right;
    reg signed [15:0] dry;
    reg [17:0] tail_steps;
    reg early_valid;
    reg [2:0] early_index;
    wire [9:0] early_delay=early_index==0 ? 10'd342 : early_index==1 ? 10'd452 :
                               early_index==2 ? 10'd525 : early_index==3 ? 10'd745 : 10'd964;
    wire [9:0] pre_read_pointer=pre_pointer-early_delay;
    wire signed [27:0] divide4=(total<0 ? total+28'sd3 : total)>>>2;
    wire signed [27:0] early_value=truncate15(product_a);
    wire signed [27:0] feedback_value=truncate15(product_a)+truncate15(product_b);
    wire signed [27:0] dry_q=$signed({{12{dry[15]}},dry})<<<8;
    assign left=pcm16(dry_q+wet_left);
    assign right=pcm16(dry_q+wet_right);
    assign tail_active=mode && tail_steps!=0;
    integer i;
    always @(posedge clk) begin
        write_enable<=0;
        valid<=0;
        if(!reset_n) begin
            state<=0;line<=0;pre_pointer<=0;filled<=0;divider<=0;mode<=0;input_sum<=0;
            input_q<=0;pre_q<=0;tap<=0;total<=0;sum_left<=0;sum_right<=0;householder<=0;
            product_a<=0;product_b<=0;early_left<=0;early_right<=0;wet_left<=0;wet_right<=0;
            dry<=0;tail_steps<=0;valid<=0;early_valid<=0;early_index<=0;
            address<=0;write_address<=0;write_data<=0;write_enable<=0;
            for(i=0;i<8;i=i+1) begin pointers[i]<=0;filtered[i]<=0;damped[i]<=0;end
        end else case(state)
            0: if(sample_valid) begin
                dry<=sample_in;valid<=0;mode<=enable;
                if(!enable || !mode) begin
                    filled<=0;pre_pointer<=0;divider<=0;input_sum<=0;wet_left<=0;wet_right<=0;tail_steps<=0;
                    for(i=0;i<8;i=i+1) begin pointers[i]<=0;filtered[i]<=0;damped[i]<=0;end
                    state<=35;
                end else begin
                    divider<=divider+1'b1;
                    if(divider==3) begin
                        input_q<=($signed({{8{input_sum[17]}},input_sum})+$signed({{10{sample_in[15]}},sample_in}))<<<6;
                        input_sum<=0;early_index<=0;early_left<=0;early_right<=0;total<=0;sum_left<=0;sum_right<=0;
                        if(input_sum!=0 || sample_in!=0) tail_steps<=TAIL_STEPS;
                        else if(tail_steps!=0) tail_steps<=tail_steps-1'b1;
                        state<=1;
                    end else begin input_sum<=input_sum+sample_in;state<=35;end
                end
            end
            1: begin address<=13'd5387+{3'd0,pre_read_pointer};early_valid<=filled>={1'b0,early_delay};state<=2;end
            2: state<=3;
            3: begin
                if(early_index==0) pre_q<=early_valid ? q : 24'sd0;
                product_a<=(early_valid ? q : 24'sd0)*(early_index<3 ? 16'sd2294 : 16'sd1491);
                state<=4;
            end
            4: begin
                if(early_index==1 || early_index==3) early_left<=early_left+early_value;
                if(early_index==2 || early_index==4) early_right<=early_right+early_value;
                if(early_index==4) begin line<=0;state<=10;end
                else begin early_index<=early_index+1'b1;state<=1;end
            end
            10: begin address<=base_address(line)+{3'd0,pointers[line]};state<=11;end
            11: state<=12;
            12: begin tap<=filled>=delay_length(line) ? q : 24'sd0;state<=13;end
            13: begin
                product_a<=tap*16'sd28797;
                product_b<=filtered[line]*16'sd3971;
                sum_left<=sum_left+((line==0 || line==1 || line==4 || line==6) ? tap : -$signed({{4{tap[23]}},tap}));
                sum_right<=sum_right+((line==0 || line==2 || line==5 || line==6) ? tap : -$signed({{4{tap[23]}},tap}));
                state<=14;
            end
            14: begin
                damped[line]<=saturate24(feedback_value);filtered[line]<=saturate24(feedback_value);
                total<=total+feedback_value;state<=15;
            end
            15: if(line==7) begin line<=0;state<=20;end else begin line<=line+1'b1;state<=10;end
            20: begin householder<=$signed({{4{damped[line][23]}},damped[line]})-divide4;state<=21;end
            21: begin product_a<=householder*feedback_gain(line);product_b<=pre_q*injection_gain(line);state<=22;end
            22: begin write_address<=base_address(line)+{3'd0,pointers[line]};write_data<=saturate24(feedback_value);write_enable<=1;state<=23;end
            23: begin
                pointers[line]<=pointers[line]==delay_length(line)-1 ? 10'd0 : pointers[line]+1'b1;
                if(line==7) state<=30;else begin line<=line+1'b1;state<=20;end
            end
            30: begin
                write_address<=13'd5387+{3'd0,pre_pointer};write_data<=input_q;write_enable<=1;
                pre_pointer<=pre_pointer+1'b1;if(filled<2047) filled<=filled+1'b1;
                product_a<=sum_left*16'sd5677;product_b<=sum_right*16'sd5677;state<=31;
            end
            31: begin
                wet_left<=tail_steps!=0 ? truncate15(product_a)+early_left : 28'sd0;
                wet_right<=tail_steps!=0 ? truncate15(product_b)+early_right : 28'sd0;
                state<=35;
            end
            35: begin valid<=1;state<=0;end
            default: state<=0;
        endcase
    end
endmodule
