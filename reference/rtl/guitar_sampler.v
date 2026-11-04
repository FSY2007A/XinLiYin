// CC0 Martin recordings, eight roots, one-shot IMA ADPCM and 32 voice contexts.
// 50MHz/4096 source, Q16 variable-rate interpolation to 50MHz/1024 output.
module guitar_sampler(
    input wire clk, reset_n, frame_tick, enable,
    input wire [31:0] held,
    input wire octave,
    output reg signed [15:0] sample,
    output reg ready
);
    `include "guitar_metadata.vh"
    reg [15:0] rom0[0:4095],rom1[0:4095],rom2[0:4095],rom3[0:4095];
    reg [15:0] rom4[0:4095],rom5[0:4095],rom6[0:4095],rom7[0:4095];
    reg [14:0] address;
    reg [15:0] q0,q1,q2,q3,q4,q5,q6,q7;
    reg [2:0] bank;
    wire [15:0] rom_q=bank==0 ? q0 : bank==1 ? q1 : bank==2 ? q2 : bank==3 ? q3 :
                         bank==4 ? q4 : bank==5 ? q5 : bank==6 ? q6 : q7;
    initial begin
        $readmemh("guitar_adpcm_0.mem",rom0);$readmemh("guitar_adpcm_1.mem",rom1);
        $readmemh("guitar_adpcm_2.mem",rom2);$readmemh("guitar_adpcm_3.mem",rom3);
        $readmemh("guitar_adpcm_4.mem",rom4);$readmemh("guitar_adpcm_5.mem",rom5);
        $readmemh("guitar_adpcm_6.mem",rom6);$readmemh("guitar_adpcm_7.mem",rom7);
    end
    always @(posedge clk) begin
        q0<=rom0[address[11:0]];q1<=rom1[address[11:0]];q2<=rom2[address[11:0]];q3<=rom3[address[11:0]];
        q4<=rom4[address[11:0]];q5<=rom5[address[11:0]];q6<=rom6[address[11:0]];q7<=rom7[address[11:0]];
        bank<=address[14:12];
    end
    // Tiny resettable voice contexts use registers; Gowin's inferred SP mode2
    // cannot implement this read/write contract and would also waste BSRAM.
    reg signed [15:0] predictors[0:31] /* synthesis syn_ramstyle="registers" */;
    reg signed [15:0] left_samples[0:31] /* synthesis syn_ramstyle="registers" */;
    reg signed [15:0] right_samples[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [6:0] indices[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [17:0] positions[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [16:0] endings[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [15:0] fractions[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [15:0] increments[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [15:0] envelopes[0:31] /* synthesis syn_ramstyle="registers" */;
    reg [31:0] keys,onset,previous_keys;
    reg enabled,upper;
    reg [4:0] voice;
    reg [3:0] state;
    reg [56:0] info;
    reg [15:0] increment,envelope;
    reg [16:0] fraction,last;
    reg [17:0] position;
    reg signed [15:0] prediction,a,b,decoded,value;
    reg [6:0] index,next_index;
    reg [3:0] code;
    reg [14:0] step;
    reg signed [33:0] interpolation;
    reg signed [32:0] product;
    reg signed [23:0] sum;
    wire [5:0] note={1'b0,voice}+(upper ? 6'd12 : 6'd0);
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
            info<=0;increment<=0;envelope<=0;fraction<=0;last<=0;position<=0;prediction<=0;
            a<=0;b<=0;decoded<=0;value<=0;index<=0;next_index<=0;code<=0;step<=0;
            interpolation<=0;product<=0;sum<=0;sample<=0;ready<=0;address<=0;
            for(i=0;i<32;i=i+1) begin
                predictors[i]<=0;left_samples[i]<=0;right_samples[i]<=0;indices[i]<=0;
                positions[i]<=0;endings[i]<=0;fractions[i]<=0;increments[i]<=0;envelopes[i]<=0;
            end
        end else if(frame_tick) begin
            keys<=held;onset<=held & ~previous_keys;previous_keys<=enable ? held : 32'd0;
            enabled<=enable;upper<=octave;voice<=0;sum<=0;ready<=0;state<=1;
        end else case(state)
            0: ;
            1: begin
                info<=guitar_info(guitar_root(note));increment<=guitar_increment(note);
                prediction<=predictors[voice];index<=indices[voice];position<=positions[voice];
                last<=endings[voice];fraction<={1'b0,fractions[voice]};envelope<=envelopes[voice];
                a<=left_samples[voice];b<=right_samples[voice];state<=2;
            end
            2: begin
                if(!enabled) begin envelope<=0;a<=0;b<=0;fraction<=0;state<=7;end
                else if(onset[voice]) begin
                    prediction<=info[15:0];index<=info[22:16];position<={1'b0,info[39:23]};last<=info[56:40];
                    increments[voice]<=upper ? increment>>1 : increment;
                    a<=0;b<=0;fraction<=0;envelope<=32767;address<=info[39:25];state<=3;
                end else begin
                    if(!keys[voice]) envelope<=envelope>2 ? envelope-16'd2 : 16'd0;
                    fraction<={1'b0,fractions[voice]}+{1'b0,(upper ? increments[voice]<<1 : increments[voice])};
                    state<=6;
                end
            end
            3: state<=4;
            4: begin code<=rom_q[{position[1:0],2'b00}+:4];step<=guitar_step(index);state<=5;end
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
                        b<=0;if(b==0) envelope<=0;state<=7;
                    end else begin address<=position[16:2];state<=3;end
                end else state<=7;
            end
            7: begin interpolation<=delta*$signed({1'b0,fraction[15:0]});state<=8;end
            8: begin value<=a+(interpolation>>>16);state<=9;end
            9: begin
                product<=value*$signed({1'b0,envelope});envelopes[voice]<=envelope;
                left_samples[voice]<=a;right_samples[voice]<=b;fractions[voice]<=fraction[15:0];
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
