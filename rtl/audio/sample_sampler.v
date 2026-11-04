// CC0 erhu/guzheng multisamples with 32 voice contexts.
// Each 8192-word bank holds four IMA ADPCM nibbles per word.
// Erhu banks use a matched sustain loop; guzheng banks use their natural decay.
module sample_sampler(
    input wire clk, reset_n, frame_tick, enable,
    input wire [31:0] held,
    input wire [1:0] instrument,
    input wire octave,
    output reg signed [15:0] sample,
    output reg ready
);
    `include "sample_metadata.vh"
    reg [15:0] rom0[0:8191],rom1[0:8191],rom2[0:8191],rom3[0:8191];
    reg [15:0] rom4[0:8191],rom5[0:8191],rom6[0:8191],rom7[0:8191];
    reg [15:0] address;
    reg [12:0] word_address;
    reg [15:0] q0,q1,q2,q3,q4,q5,q6,q7;
    reg [2:0] bank_read;
    wire [15:0] rom_q=bank_read==0 ? q0 : bank_read==1 ? q1 : bank_read==2 ? q2 : bank_read==3 ? q3 :
                         bank_read==4 ? q4 : bank_read==5 ? q5 : bank_read==6 ? q6 : q7;
    initial begin
        $readmemh("sample_adpcm_0.mem",rom0);$readmemh("sample_adpcm_1.mem",rom1);
        $readmemh("sample_adpcm_2.mem",rom2);$readmemh("sample_adpcm_3.mem",rom3);
        $readmemh("sample_adpcm_4.mem",rom4);$readmemh("sample_adpcm_5.mem",rom5);
        $readmemh("sample_adpcm_6.mem",rom6);$readmemh("sample_adpcm_7.mem",rom7);
    end
    always @(posedge clk) begin
        word_address<=address[12:0];
        bank_read<=address[15:13];
        q0<=rom0[word_address];q1<=rom1[word_address];q2<=rom2[word_address];q3<=rom3[word_address];
        q4<=rom4[word_address];q5<=rom5[word_address];q6<=rom6[word_address];q7<=rom7[word_address];
    end

    // Small resettable contexts remain registers. Gowin cannot infer this
    // read/write contract as a useful single-clock memory.
    reg signed [15:0] predictors[0:31] /* synthesis syn_ramstyle="registers" */;
    reg signed [15:0] left_samples[0:31] /* synthesis syn_ramstyle="registers" */;
    reg signed [15:0] right_samples[0:31] /* synthesis syn_ramstyle="registers" */;
    reg signed [15:0] loop_predictors[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [6:0] indices[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [6:0] loop_indices[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [15:0] positions[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [14:0] endings[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [14:0] loop_starts[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [16:0] fractions[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [15:0] increments[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [15:0] envelopes[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [2:0] banks[0:31] /* synthesis syn_ramstyle="registers" */;
    reg loop_enables[0:31] /* synthesis syn_ramstyle="registers" */;

    reg [31:0] keys,onset,previous_keys;
    reg enabled,upper;
    reg [4:0] voice;
    reg [3:0] state;
    reg [76:0] info;
    reg [15:0] increment,envelope;
    reg [7:0] gain;
    reg [16:0] fraction;
    reg [15:0] position,last;
    reg [14:0] loop_start;
    reg [2:0] bank_value;
    reg signed [15:0] prediction,a,b,decoded,value,loop_prediction;
    reg [6:0] index,next_index,loop_index;
    reg loop_enable;
    reg [3:0] code;
    reg [14:0] step;
    reg signed [33:0] interpolation;
    reg signed [15:0] gain_product;
    reg signed [32:0] product;
    reg signed [23:0] sum;
    wire [5:0] note={1'b0,voice}+(upper ? 6'd12 : 6'd0);
    wire signed [33:0] next_value_wide=$signed({{16{a[15]}},a})+(interpolation>>>16);
    wire signed [18:0] next_value=next_value_wide[18:0];
    wire signed [26:0] scaled_gain=next_value*$signed({1'b0,gain});
    wire signed [16:0] delta=$signed({b[15],b})-$signed({a[15],a});
    wire [16:0] difference={2'd0,(step>>3)}+(code[2] ? {2'd0,step} : 17'd0)+
                         (code[1] ? {2'd0,(step>>1)} : 17'd0)+(code[0] ? {2'd0,(step>>2)} : 17'd0);
    wire signed [17:0] predicted_next=$signed({{2{prediction[15]}},prediction})+
                         (code[3] ? -$signed({1'b0,difference}) : $signed({1'b0,difference}));
    wire signed [8:0] index_delta=code[2:0]<4 ? -9'sd1 : code[2:0]==4 ? 9'sd2 :
                                code[2:0]==5 ? 9'sd4 : code[2:0]==6 ? 9'sd6 : 9'sd8;
    wire signed [8:0] index_sum=$signed({2'b0,index})+index_delta;
    integer i;
    always @(posedge clk) begin
        if(!reset_n) begin
            state<=0;voice<=0;keys<=0;onset<=0;previous_keys<=0;enabled<=0;upper<=0;
            info<=0;increment<=0;envelope<=0;gain<=8'd128;fraction<=0;position<=0;last<=0;loop_start<=0;
            bank_value<=0;prediction<=0;a<=0;b<=0;decoded<=0;value<=0;index<=0;next_index<=0;
            loop_prediction<=0;loop_index<=0;loop_enable<=0;code<=0;step<=0;
            interpolation<=0;gain_product<=0;product<=0;sum<=0;sample<=0;ready<=0;address<=0;
            for(i=0;i<32;i=i+1) begin
                predictors[i]<=0;left_samples[i]<=0;right_samples[i]<=0;loop_predictors[i]<=0;
                indices[i]<=0;loop_indices[i]<=0;positions[i]<=0;endings[i]<=0;loop_starts[i]<=0;
                fractions[i]<=0;increments[i]<=0;envelopes[i]<=0;banks[i]<=0;loop_enables[i]<=0;
            end
        end else if(frame_tick) begin
            keys<=held;onset<=held & ~previous_keys;previous_keys<=enable ? held : 32'd0;
            enabled<=enable;upper<=octave;voice<=0;sum<=0;ready<=0;state<=1;
        end else case(state)
            0: ;
            1: begin
                info<=sample_info(sample_bank(voice,instrument));
                bank_value<=sample_bank(voice,instrument);
                increment<=sample_increment(voice,note,instrument);
                gain<=sample_gain(sample_bank(voice,instrument));
                prediction<=predictors[voice];index<=indices[voice];position<=positions[voice];
                last<=endings[voice];loop_start<=loop_starts[voice];fraction<=fractions[voice];
                loop_prediction<=loop_predictors[voice];loop_index<=loop_indices[voice];
                loop_enable<=loop_enables[voice];
                envelope<=envelopes[voice];a<=left_samples[voice];b<=right_samples[voice];
                state<=2;
            end
            2: begin
                if(!enabled) begin envelope<=0;a<=0;b<=0;fraction<=0;state<=7;end
                else if(onset[voice]) begin
                    prediction<=info[15:0];index<=info[22:16];position<=0;
                    last<=info[37:23];loop_start<=info[52:38];
                    loop_prediction<=$signed(info[68:53]);loop_index<=info[75:69];
                    loop_enable<=info[76];increments[voice]<=increment;
                    banks[voice]<=bank_value;loop_starts[voice]<=info[52:38];
                    loop_predictors[voice]<=$signed(info[68:53]);loop_indices[voice]<=info[75:69];
                    loop_enables[voice]<=info[76];
                    a<=info[15:0];b<=info[15:0];fraction<=0;envelope<=32767;
                    address<={bank_value,13'd0};state<=3;
                end else begin
                    if(!keys[voice]) envelope<=envelope>2 ? envelope-16'd2 : 16'd0;
                    fraction<={1'b0,fractions[voice]}+{1'b0,increments[voice]};
                    state<=6;
                end
            end
            3: state<=4;
            4: begin code<=rom_q[{position[1:0],2'b00}+:4];step<=sample_step(index);state<=5;end
            5: begin
                decoded<=predicted_next>18'sd32767 ? 16'sh7fff :
                    predicted_next< -18'sd32768 ? 16'sh8000 : predicted_next[15:0];
                next_index<=index_sum<0 ? 7'd0 : index_sum>88 ? 7'd88 : index_sum[6:0];state<=12;
            end
            6: begin
                if(envelope==0) begin a<=0;b<=0;fraction<=0;state<=7;end
                else if(fraction[16]) begin
                    fraction<={1'b0,fraction[15:0]};a<=b;
                    if(position>{1'b0,last}) begin
                        if(loop_enable) begin
                            position<=loop_start;prediction<=loop_prediction;index<=loop_index;
                            address<={banks[voice],loop_start[14:2]};state<=3;
                        end else begin b<=0;envelope<=0;state<=7;end
                    end else begin address<={banks[voice],position[14:2]};state<=3;end
                end else state<=7;
            end
            7: begin interpolation<=delta*$signed({1'b0,fraction[15:0]});state<=8;end
            8: begin
                value<=next_value[15:0];
                if((scaled_gain>>>7)>27'sd32767) gain_product<=16'sd32767;
                else if((scaled_gain>>>7)< -27'sd32768) gain_product<=-16'sd32768;
                else gain_product<=(scaled_gain>>>7);
                state<=14;
            end
            14: begin product<=gain_product*$signed({1'b0,envelope});state<=9;end
            9: begin
                envelopes[voice]<=envelope;
                left_samples[voice]<=a;right_samples[voice]<=b;fractions[voice]<=fraction;
                endings[voice]<=last;state<=10;
            end
            10: begin sum<=sum+(product>>>15);state<=11;end
            11: if(voice==31) state<=13;else begin voice<=voice+1'b1;state<=1;end
            12: begin
                b<=decoded;predictors[voice]<=decoded;indices[voice]<=next_index;
                positions[voice]<=position+1'b1;state<=7;
            end
            13: begin
                sample<=(sum>>>3)>24'sd32767 ? 16'sh7fff : (sum>>>3)< -24'sd32768 ? 16'sh8000 : (sum>>>3);
                ready<=1;state<=0;
            end
            default: state<=0;
        endcase
    end
endmodule
