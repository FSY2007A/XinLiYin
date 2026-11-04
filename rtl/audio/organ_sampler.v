// Six real ranks, mixed offline; 16 independent IMA-ADPCM attack/loop voices.
// Source rate is 50MHz/2048, linearly interpolated to the original frame rate.
module organ_sampler(
    input wire clk, reset_n, frame_tick, enable,
    input wire [15:0] held,
    input wire octave,
    output reg signed [15:0] sample,
    output reg ready
);
    `include "organ_metadata.vh"
    `include "organ_steps.vh"
    // Explicit 4K-word banks avoid padding a 20K-word ROM to 32K in Gowin.
    reg [15:0] rom0[0:4095],rom1[0:4095],rom2[0:4095],rom3[0:4095],rom4[0:4095];
    reg [14:0] address;
    reg [15:0] q0,q1,q2,q3,q4;
    reg [2:0] bank;
    wire [15:0] rom_q=bank==0 ? q0 : bank==1 ? q1 : bank==2 ? q2 : bank==3 ? q3 : q4;
    initial begin
        $readmemh("organ_adpcm_0.mem",rom0);$readmemh("organ_adpcm_1.mem",rom1);
        $readmemh("organ_adpcm_2.mem",rom2);$readmemh("organ_adpcm_3.mem",rom3);
        $readmemh("organ_adpcm_4.mem",rom4);
    end
    always @(posedge clk) begin
        q0<=rom0[address[11:0]];q1<=rom1[address[11:0]];q2<=rom2[address[11:0]];
        q3<=rom3[address[11:0]];q4<=rom4[address[11:0]];bank<=address[14:12];
    end
    reg signed [15:0] predictors[0:15],audio_a[0:15],audio_b[0:15];
    reg [6:0] indices[0:15];
    reg [12:0] positions[0:15];
    reg [15:0] envelopes[0:15];
    reg [3:0] state, voice;
    reg [15:0] keys, onset, previous_keys;
    reg enabled, upper, divider;
    reg [63:0] info;
    reg signed [15:0] prediction, a, b, decoded, value;
    reg [6:0] index, next_index;
    reg [12:0] position;
    reg [15:0] envelope;
    reg [3:0] code;
    reg [14:0] step;
    reg signed [32:0] product;
    reg signed [23:0] sum;
    wire [16:0] difference={2'd0,(step>>3)} + (code[2] ? {2'd0,step} : 17'd0) +
                           (code[1] ? {2'd0,(step>>1)} : 17'd0) + (code[0] ? {2'd0,(step>>2)} : 17'd0);
    wire signed [17:0] predicted_next=$signed({{2{prediction[15]}},prediction}) +
        (code[3] ? -$signed({1'b0,difference}) : $signed({1'b0,difference}));
    wire signed [8:0] index_delta=code[2:0]<4 ? -9'sd1 :
        code[2:0]==4 ? 9'sd2 : code[2:0]==5 ? 9'sd4 : code[2:0]==6 ? 9'sd6 : 9'sd8;
    wire signed [8:0] index_sum=$signed({2'b0,index})+index_delta;
    wire signed [16:0] midpoint=($signed({a[15],a})+$signed({b[15],b}))>>>1;
    wire [14:0] voice_base=({11'd0,voice}<<10)+({11'd0,voice}<<8);
    wire [12:0] loop_last=13'd3071+{1'b0,info[57:46]};
    integer i;
    always @(posedge clk) begin
        if(!reset_n) begin
            state<=0;voice<=0;keys<=0;onset<=0;previous_keys<=0;
            enabled<=0;upper<=0;divider<=0;info<=0;prediction<=0;a<=0;b<=0;
            decoded<=0;value<=0;index<=0;next_index<=0;position<=0;envelope<=0;
            code<=0;step<=0;product<=0;sum<=0;sample<=0;ready<=0;address<=0;
            for(i=0;i<16;i=i+1) begin
                predictors[i]<=0;indices[i]<=0;positions[i]<=0;envelopes[i]<=0;
                audio_a[i]<=0;audio_b[i]<=0;
            end
        end else if(frame_tick) begin
            keys<=held;onset<=held & ~previous_keys;
            previous_keys<=enable ? held : 16'd0;
            enabled<=enable;upper<=octave;divider<=~divider;
            voice<=0;sum<=0;ready<=0;state<=1;
        end else case(state)
            0: ;
            1: begin
                info<=organ_info(voice);prediction<=predictors[voice];index<=indices[voice];
                position<=positions[voice];envelope<=envelopes[voice];
                a<=audio_a[voice];b<=audio_b[voice];state<=2;
            end
            2: begin
                if(!enabled) begin envelope<=0;value<=0;state<=8;end
                else if(onset[voice]) begin
                    prediction<=info[15:0];index<=info[22:16];position<=0;
                    a<=0;b<=0;envelope<=32767;address<=voice_base;state<=3;
                end else begin
                    if(!keys[voice]) envelope<=envelope==0 ? 16'd0 :
                        envelope-((envelope>>11)!=0 ? envelope>>11 : 16'd1);
                    if(envelope==0) begin value<=0;state<=8;end
                    else if(upper || divider) begin address<=voice_base+{4'd0,position[12:2]};state<=3;end
                    else begin value<=midpoint[15:0];state<=8;end
                end
            end
            3: state<=4; // Synchronous ROM read.
            4: begin code<=rom_q[{position[1:0],2'b00}+:4];step<=organ_step(index);state<=5;end
            5: begin
                decoded<=predicted_next>18'sd32767 ? 16'sh7fff :
                    predicted_next< -18'sd32768 ? 16'sh8000 : predicted_next[15:0];
                next_index<=index_sum<0 ? 7'd0 : index_sum>88 ? 7'd88 : index_sum[6:0];state<=6;
            end
            6: begin
                value<=upper ? decoded : a;
                audio_b[voice]<=a;audio_a[voice]<=decoded;
                if(position==13'd3071 || position==loop_last) begin
                    positions[voice]<=13'd3072;predictors[voice]<=info[38:23];indices[voice]<=info[45:39];
                end else begin
                    positions[voice]<=position+1'b1;predictors[voice]<=decoded;indices[voice]<=next_index;
                end
                state<=8;
            end
            8: begin product<=value*$signed({1'b0,envelope});envelopes[voice]<=envelope;state<=9;end
            9: begin sum<=sum+(product>>>15);state<=10;end
            10: if(voice==15) state<=11;else begin voice<=voice+1'b1;state<=1;end
            11: begin
                sample<=sum>24'sd32767 ? 16'sh7fff : sum< -24'sd32768 ? 16'sh8000 : sum[15:0];
                ready<=1;state<=0;
            end
            default: state<=0;
        endcase
    end
endmodule
