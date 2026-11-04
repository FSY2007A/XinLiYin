// 32 独立声部，共享同步波表与乘法器；50 MHz / 1024 帧。
// 混音以 1/32 缩放，保留饱和保护；所有声部独立相位和 ADSR。
module voice_engine_32 #(
    parameter integer PIANO_PROFILE = 0,
    parameter integer NEAR_NOTE_SOFTEN = 0,
    parameter integer STRING_SAMPLE = 0,
    parameter integer PAN_STRINGS = 0,
    parameter integer PAN_RIGHT = 0,
    parameter integer NEAR_SPECTRAL_STRINGS = 0,
    parameter integer BOWED_STRINGS = 0,
    parameter integer PACKED_BOWED_MASK = 0
)(
    input wire clk, reset_n, frame_tick,
    input wire [31:0] gate,
    input wire [1:0] timbre,
    input wire octave,
    input wire [7:0] expression,
    output reg signed [15:0] next_pcm,
    output reg ready,
    input wire [31:0] retrigger,
    input wire signed [15:0] pitch_offset
);
    // 状态机在多个声部之间分时复用一个正弦表端口和混音乘法器。
    localparam ST_IDLE = 0, ST_ADDR1 = 1, ST_WAIT1 = 2, ST_CAP1 = 3,
               ST_WAIT2 = 4, ST_CAP2 = 5, ST_WAIT3 = 6, ST_GAIN = 7,
               ST_MULT = 8, ST_ADD = 9, ST_FINAL = 10, ST_COUNT = 11,
               ST_BLEND1 = 12, ST_BLEND2 = 13, ST_BOW_WAIT = 14,
               ST_ENV_READ = 15, ST_ENV_UPDATE = 16;
    // 每个按键独立的 ADSR 包络状态；起音/衰减/释音步长按采样点更新。
    localparam ENV_OFF = 0, ENV_ATTACK = 1, ENV_DECAY = 2,
               ENV_SUSTAIN = 3, ENV_RELEASE = 4;
    reg [4:0] state;
    reg [4:0] voice_idx;
    // 32 位 DDS 相位累加器；高 10 位用于寻址 1024 项正弦查找表。
    reg [31:0] phase [0:31];
    reg [31:0] string_position [0:31]; // Q16.16 sample position, loop [16384,32768).
    reg [15:0] env [0:31];
    // Q15.8 avoids a coarse/stalled exponential tail at low amplitudes.
    reg [23:0] piano_level [0:31];
    reg [8:0] note_balance [0:31];
    reg [8:0] pan_balance [0:31];
    reg [8:0] spectral_low [0:31], spectral_high [0:31];
    reg [5:0] pan_count, pan_rank;
    reg [4:0] count_index;
    reg [15:0] pan_base_gain;
    reg [24:0] pan_gain_product;
    reg [31:0] gate_frame, onset_frame, near_lower_frame, near_upper_frame;
    reg [2:0] env_state [0:31];
    reg [31:0] gate_d;
    reg [31:0] pending_retrigger;
    reg signed [15:0] pitch_frame;
    reg octave_frame;
    reg [31:0] increment [0:31];
    wire signed [48:0] pitch_product = $signed({1'b0, note_increment(voice_idx)}) * pitch_frame;
    wire [31:0] bent_increment = note_increment(voice_idx) + (pitch_product >>> 12);
    reg [1:0] timbre_frame;
    reg [7:0] expression_frame;
    reg [31:0] release_frame;
    reg timbre_changed_frame;
    reg [15:0] attack_frame, decay_frame, sustain_frame, release_step_frame;
    reg [15:0] env_value;
    reg [2:0] env_state_value;
    reg [23:0] piano_value;
    reg [31:0] phase_value, position_value, increment_value;
    reg [9:0] rom_addr;
    reg [14:0] string_address;
    reg [7:0] string_fraction;
    reg signed [15:0] string_left;
    reg signed [25:0] string_interpolation;
    wire signed [15:0] string_data;
    wire signed [15:0] pair_low_data, pair_high_data;
    reg signed [15:0] string_base;
    reg signed [26:0] spectral_low_product, spectral_high_product;
    wire signed [16:0] pair_low_delta = $signed({pair_low_data[15],pair_low_data}) -
                                      $signed({string_data[15],string_data});
    wire signed [16:0] pair_high_delta = $signed({pair_high_data[15],pair_high_data}) -
                                       $signed({string_data[15],string_data});
    wire signed [27:0] spectral_sum = {spectral_low_product[26],spectral_low_product} +
                                      {spectral_high_product[26],spectral_high_product};
    wire signed [27:0] spectral_value = {{12{string_base[15]}},string_base} + (spectral_sum >>> 8);
    wire signed [15:0] blended_string = spectral_value[15:0];
    wire signed [16:0] blended_delta = $signed({blended_string[15],blended_string}) -
                                     $signed({string_left[15],string_left});
    wire spectral_active = NEAR_SPECTRAL_STRINGS != 0 && timbre_frame == 1;
    wire [8:0] spectral_high_target = near_lower_frame[voice_idx] ? 9'd256 : 9'd0;
    wire [8:0] spectral_low_target = !near_lower_frame[voice_idx] && near_upper_frame[voice_idx] ? 9'd256 : 9'd0;
    wire signed [16:0] string_delta = $signed({string_data[15],string_data}) -
                                      $signed({string_left[15],string_left});
    wire signed [15:0] rom_data;
    reg signed [15:0] fundamental, second;
    // Concatenations are unsigned in Verilog; sign these before arithmetic shifts.
    wire signed [17:0] fundamental_ext = {{2{fundamental[15]}}, fundamental};
    wire signed [17:0] second_ext = {{2{second[15]}}, second};
    wire signed [17:0] third_ext = {{2{rom_data[15]}}, rom_data};
    reg signed [17:0] wave_mix;
    reg [15:0] gain;
    reg signed [34:0] product;
    reg signed [23:0] mix_acc;
    wire [31:0] triple_phase = phase[voice_idx] + (phase[voice_idx] << 1);
    // 先将包络与整体力度相乘，再用于缩放波形幅度。
    wire [23:0] gain_product = env[voice_idx] * expression_frame;
    wire [32:0] balanced_gain = gain_product * note_balance[voice_idx];
    // The spectral-pair audition uses 1/4; the saved D649 path retains 1/16.
    wire [8:0] balance_target = !near_lower_frame[voice_idx] ? 9'd256 :
                                timbre_frame == 1 && BOWED_STRINGS != 0 ? 9'd256 :
                                timbre_frame == 1 && NEAR_SPECTRAL_STRINGS == 0 ? 9'd16 : 9'd64;
    wire signed [8:0] pan_offset = string_pan(pan_count, pan_rank);
    wire [8:0] pan_target = PAN_RIGHT != 0 ? 9'd256 + pan_offset : 9'd256 - pan_offset;
    wire signed [23:0] voice_term = {{9{product[34]}}, product[34:20]};
    // Electric piano, bowed strings, organ, plucked string: distinct ADSR + spectra.
    wire [15:0] attack_step = timbre == 0 ? 16'd168 :
                             timbre == 1 ? (BOWED_STRINGS != 0 ? 16'd9 : 16'd13) : timbre == 2 ? 16'd1024 : 16'd512;
    wire [15:0] decay_step = timbre == 0 ? 16'd64 :
                            timbre == 1 ? 16'd32 : timbre == 2 ? 16'd256 : 16'd96;
    wire [15:0] sustain_level = timbre == 0 ? 16'd20000 :
                               timbre == 1 ? (BOWED_STRINGS != 0 ? 16'd32767 : 16'd22000) : timbre == 2 ? 16'd32767 : 16'd0;
    wire [15:0] release_step = timbre == 0 ? 16'd128 :
                              timbre == 1 ? (BOWED_STRINGS != 0 ? 16'd2 : 16'd16) : 16'd256;
    integer i;

    sine_rom wavetable(clk, rom_addr, rom_data);
    // Rank spread for six Boot Keyboard notes; solo is centred. Larger sets alternate.
    function signed [8:0] string_pan;
        input [5:0] count, rank;
        begin
            case (count)
                0,1: string_pan = 9'sd0;
                2: string_pan = rank == 0 ? -9'sd96 : 9'sd96;
                3: string_pan = rank == 0 ? -9'sd96 : rank == 1 ? 9'sd0 : 9'sd96;
                4: case(rank) 0:string_pan=-9'sd96; 1:string_pan=-9'sd32; 2:string_pan=9'sd32; default:string_pan=9'sd96; endcase
                5: case(rank) 0:string_pan=-9'sd96; 1:string_pan=-9'sd48; 2:string_pan=9'sd0; 3:string_pan=9'sd48; default:string_pan=9'sd96; endcase
                6: case(rank) 0:string_pan=-9'sd96; 1:string_pan=-9'sd58; 2:string_pan=-9'sd19; 3:string_pan=9'sd19; 4:string_pan=9'sd58; default:string_pan=9'sd96; endcase
                default: string_pan = rank[0] ? 9'sd96 : -9'sd96;
            endcase
        end
    endfunction
    generate if (STRING_SAMPLE != 0 && BOWED_STRINGS == 0) begin: sampled_strings
        string_sample_rom sample_table(clk, string_address, string_data);
    end else begin: legacy_strings
        assign string_data = 16'sd0;
    end endgenerate
    generate if (STRING_SAMPLE != 0 && NEAR_SPECTRAL_STRINGS != 0 && BOWED_STRINGS == 0) begin: pair_strings
        string_pair_rom pair_table(clk, string_address[7:0], pair_low_data, pair_high_data);
    end else begin: no_pair_strings
        assign pair_low_data = 16'sd0;
        assign pair_high_data = 16'sd0;
    end endgenerate
    wire signed [17:0] bowed_sample;
    wire bowed_done;
    generate if (BOWED_STRINGS != 0) begin: bowed_strings
        bowed_wave #(.PACKED_MASK(PACKED_BOWED_MASK)) bowed(
            .clk(clk),.reset_n(reset_n),.start(state==ST_ADDR1 && timbre_frame==1),
            .gate(gate),.active(env_state[voice_idx]!=ENV_OFF),
            .held(gate_frame[voice_idx]),.onset(onset_frame[voice_idx]),
            .voice(voice_idx),.phase(phase[voice_idx]),.sample(bowed_sample),.done(bowed_done));
    end else begin: no_bowed_strings
        assign bowed_sample=0;assign bowed_done=0;
    end endgenerate

    function [31:0] advance_string;
        input [31:0] position, step;
        reg [32:0] following;
        begin
            following = {1'b0,position} + {1'b0,step};
            advance_string = following >= 33'h080000000 ? following - 33'h040000000 : following;
        end
    endfunction

    function [23:0] piano_fall;
        input [23:0] value;
        input releasing;
        reg [23:0] drop;
        begin
            drop = releasing ? ((value >> 11) + (value >> 12) + 24'd1) :
                               ((value >> 15) + (value >> 16) + 24'd1);
            piano_fall = value <= 24'd1024 ? 24'd0 : value - drop;
        end
    endfunction

    // 相位步长 = 音符频率 × 2^32 / 采样率；本工程采样率为 50 MHz / 1024。
    function [31:0] note_increment;
        input integer index;
        begin
            case (index)
                0: note_increment = 32'd23012828; // MIDI 60
                1: note_increment = 32'd24381242; // MIDI 61
                2: note_increment = 32'd25831026; // MIDI 62
                3: note_increment = 32'd27367019; // MIDI 63
                4: note_increment = 32'd28994347; // MIDI 64
                5: note_increment = 32'd30718440; // MIDI 65
                6: note_increment = 32'd32545054; // MIDI 66
                7: note_increment = 32'd34480283; // MIDI 67
                8: note_increment = 32'd36530588; // MIDI 68
                9: note_increment = 32'd38702809; // MIDI 69
                10: note_increment = 32'd41004198; // MIDI 70
                11: note_increment = 32'd43442435; // MIDI 71
                12: note_increment = 32'd46025656; // MIDI 72
                13: note_increment = 32'd48762484; // MIDI 73
                14: note_increment = 32'd51662052; // MIDI 74
                15: note_increment = 32'd54734038; // MIDI 75
                16: note_increment = 32'd57988693; // MIDI 76
                17: note_increment = 32'd61436880; // MIDI 77
                18: note_increment = 32'd65090107; // MIDI 78
                19: note_increment = 32'd68960566; // MIDI 79
                20: note_increment = 32'd73061175; // MIDI 80
                21: note_increment = 32'd77405619; // MIDI 81
                22: note_increment = 32'd82008396; // MIDI 82
                23: note_increment = 32'd86884869; // MIDI 83
                24: note_increment = 32'd92051312; // MIDI 84
                25: note_increment = 32'd97524968; // MIDI 85
                26: note_increment = 32'd103324105; // MIDI 86
                27: note_increment = 32'd109468076; // MIDI 87
                28: note_increment = 32'd115977386; // MIDI 88
                29: note_increment = 32'd122873760; // MIDI 89
                30: note_increment = 32'd130180214; // MIDI 90
                31: note_increment = 32'd137921133; // MIDI 91
                default: note_increment = 0;
            endcase
        end
    endfunction

    // The bowed build shares envelope arithmetic across voices. The legacy
    // frame-boundary calls below retain the same per-sample arithmetic.
`define VE32_ADVANCE_VOICE(index,level,envelope_state,piano,angle,position,step,key_held,key_on,key_off,mode_changed,mode,attack,decay,sustain,release_step_value) \
        begin \
            piano_level[index] <= {level,8'd0}; \
            if(key_on) begin \
                phase[index]<=0;string_position[index]<=0;env[index]<=0; \
                piano_level[index]<=0;env_state[index]<=ENV_ATTACK; \
            end else begin \
                if(envelope_state!=ENV_OFF || key_held) begin \
                    phase[index]<=angle+step; \
                    if(STRING_SAMPLE!=0) string_position[index]<=advance_string(position,step>>8); \
                end \
                if(key_off) env_state[index]<=ENV_RELEASE; \
                else if(PIANO_PROFILE!=0 && mode_changed && key_held && \
                        envelope_state!=ENV_OFF && envelope_state!=ENV_ATTACK) \
                    env_state[index]<=mode==0 || mode==3 ? ENV_DECAY : ENV_SUSTAIN; \
                else case(envelope_state) \
                    ENV_ATTACK: if(level>=16'd32767-attack) begin \
                        env[index]<=16'd32767;piano_level[index]<={16'd32767,8'd0}; \
                        env_state[index]<=ENV_DECAY; \
                    end else env[index]<=level+attack; \
                    ENV_DECAY: if(PIANO_PROFILE!=0 && mode==0) begin \
                        piano_level[index]<=piano_fall(piano,1'b0); \
                        env[index]<=piano_fall(piano,1'b0)>>8; \
                        if(piano_fall(piano,1'b0)==0) env_state[index]<=ENV_OFF; \
                    end else if(level<=sustain+decay) begin \
                        env[index]<=sustain;env_state[index]<=ENV_SUSTAIN; \
                    end else env[index]<=level-decay; \
                    ENV_SUSTAIN: if(PIANO_PROFILE!=0 && mode==0) env_state[index]<=ENV_DECAY; \
                    else begin \
                        if(level>sustain+decay) env[index]<=level-decay; \
                        else if(level+attack<sustain) env[index]<=level+attack; \
                        else env[index]<=sustain; \
                    end \
                    ENV_RELEASE: if(PIANO_PROFILE!=0 && mode==0) begin \
                        piano_level[index]<=piano_fall(piano,1'b1); \
                        env[index]<=piano_fall(piano,1'b1)>>8; \
                        if(piano_fall(piano,1'b1)==0) env_state[index]<=ENV_OFF; \
                    end else if(level<=release_step_value) begin \
                        env[index]<=0;env_state[index]<=ENV_OFF; \
                    end else env[index]<=level-release_step_value; \
                    default: ; \
                endcase \
            end \
        end

    always @(posedge clk) begin
        if (!reset_n) begin
            state <= ST_IDLE;
            voice_idx <= 0;
            gate_d <= 0;
            gate_frame <= 0; onset_frame <= 0; near_lower_frame <= 0; near_upper_frame <= 0;
            pending_retrigger <= 0;
            pitch_frame <= 0;
            octave_frame <= 0;
            timbre_frame <= 0;
            expression_frame <= 8'd128;
            release_frame<=0;timbre_changed_frame<=0;
            attack_frame<=0;decay_frame<=0;sustain_frame<=0;release_step_frame<=0;
            env_value<=0;env_state_value<=0;piano_value<=0;
            phase_value<=0;position_value<=0;increment_value<=0;
            rom_addr <= 0;
            string_address <= 0; string_fraction <= 0;
            string_left <= 0; string_interpolation <= 0;
            string_base <= 0; spectral_low_product <= 0; spectral_high_product <= 0;
            fundamental <= 0;
            second <= 0;
            wave_mix <= 0;
            gain <= 0;
            product <= 0;
            mix_acc <= 0;
            next_pcm <= 0;
            ready <= 0;
            pan_count <= 0; pan_rank <= 0; count_index <= 0;
            pan_base_gain <= 0; pan_gain_product <= 0;
            for (i = 0; i < 32; i = i + 1) begin
                phase[i] <= 0;
                string_position[i] <= 0;
                env[i] <= 0;
                piano_level[i] <= 0;
                note_balance[i] <= 9'd256;
                pan_balance[i] <= 9'd256;
                spectral_low[i] <= 0; spectral_high[i] <= 0;
                env_state[i] <= ENV_OFF;
                increment[i] <= 0;
            end
        end else if (frame_tick) begin
            // 在帧边界锁存控制量，保证一个输出样本使用一致的按键、音色和力度设置。
            state <= BOWED_STRINGS!=0 ? ST_ENV_READ :
                     PAN_STRINGS!=0 && timbre==1 ? ST_COUNT : ST_ADDR1;
            pan_count <= 0; pan_rank <= 0; count_index <= 0;
            voice_idx <= 0;
            mix_acc <= 0;
            ready <= 0;
            gate_d <= gate;
            gate_frame <= gate;
            onset_frame <= gate & (~gate_d | pending_retrigger | retrigger);
            near_lower_frame <= (gate << 1) | (gate << 2);
            near_upper_frame <= (gate >> 1) | (gate >> 2);
            pending_retrigger <= 0;
            pitch_frame <= pitch_offset;
            octave_frame <= octave;
            timbre_frame <= timbre;
            expression_frame <= expression;
            release_frame<=~gate & gate_d;
            timbre_changed_frame<=timbre!=timbre_frame;
            attack_frame<=attack_step;decay_frame<=decay_step;
            sustain_frame<=sustain_level;release_step_frame<=release_step;
            if(BOWED_STRINGS==0) for(i=0;i<32;i=i+1)
                `VE32_ADVANCE_VOICE(i,env[i],env_state[i],piano_level[i],phase[i],string_position[i],increment[i],
                    gate[i],gate[i] && (!gate_d[i] || pending_retrigger[i] || retrigger[i]),
                    !gate[i] && gate_d[i],timbre!=timbre_frame,timbre,
                    attack_step,decay_step,sustain_level,release_step);
        end else begin
          pending_retrigger <= pending_retrigger | retrigger;
          case (state)
            ST_IDLE: ;
            ST_ENV_READ: begin
                env_value<=env[voice_idx];env_state_value<=env_state[voice_idx];
                piano_value<=piano_level[voice_idx];phase_value<=phase[voice_idx];
                position_value<=string_position[voice_idx];increment_value<=increment[voice_idx];
                state<=ST_ENV_UPDATE;
            end
            ST_ENV_UPDATE: begin
                `VE32_ADVANCE_VOICE(voice_idx,env_value,env_state_value,piano_value,
                    phase_value,position_value,increment_value,
                    gate_frame[voice_idx],onset_frame[voice_idx],release_frame[voice_idx],
                    timbre_changed_frame,timbre_frame,attack_frame,decay_frame,sustain_frame,release_step_frame);
                state<=ST_ADDR1;
            end
            ST_COUNT: begin
                pan_count <= pan_count + {5'd0,gate_frame[count_index]};
                if (count_index == 31) state <= ST_ADDR1;
                else count_index <= count_index + 1'b1;
            end
            // 从同步正弦表读取基频、可选二次谐波和三次谐波，再进行乘法和累加。
            ST_ADDR1: begin
                if (NEAR_SPECTRAL_STRINGS != 0) begin
                    if (timbre_frame != 1 || env_state[voice_idx] == ENV_OFF) begin
                        spectral_low[voice_idx] <= 0; spectral_high[voice_idx] <= 0;
                    end
                    if (timbre_frame == 1 && gate_frame[voice_idx]) begin
                        if (onset_frame[voice_idx]) begin
                            spectral_low[voice_idx] <= spectral_low_target;
                            spectral_high[voice_idx] <= spectral_high_target;
                        end else begin
                            if (spectral_low[voice_idx] < spectral_low_target) spectral_low[voice_idx] <= spectral_low[voice_idx] + 1'b1;
                            else if (spectral_low[voice_idx] > spectral_low_target) spectral_low[voice_idx] <= spectral_low[voice_idx] - 1'b1;
                            if (spectral_high[voice_idx] < spectral_high_target) spectral_high[voice_idx] <= spectral_high[voice_idx] + 1'b1;
                            else if (spectral_high[voice_idx] > spectral_high_target) spectral_high[voice_idx] <= spectral_high[voice_idx] - 1'b1;
                        end
                    end
                end
                if (PAN_STRINGS != 0) begin
                    if (timbre_frame != 1 || env_state[voice_idx] == ENV_OFF) pan_balance[voice_idx] <= 9'd256;
                    if (timbre_frame == 1 && gate_frame[voice_idx]) begin
                        if (onset_frame[voice_idx]) pan_balance[voice_idx] <= pan_target;
                        else if (pan_balance[voice_idx] < pan_target) pan_balance[voice_idx] <= pan_balance[voice_idx] + 1'b1;
                        else if (pan_balance[voice_idx] > pan_target) pan_balance[voice_idx] <= pan_balance[voice_idx] - 1'b1;
                    end
                end
                // Only the higher near note is attenuated. Keep release tails
                // at their prior gain; otherwise releasing a pair could swell.
                if (NEAR_NOTE_SOFTEN != 0) begin
                    if (onset_frame[voice_idx]) note_balance[voice_idx] <= balance_target;
                    else if (gate_frame[voice_idx]) begin
                        if (note_balance[voice_idx] < balance_target)
                            note_balance[voice_idx] <= note_balance[voice_idx] + 1'b1;
                        else if (note_balance[voice_idx] > balance_target)
                            note_balance[voice_idx] <= note_balance[voice_idx] - 1'b1;
                    end else if (env_state[voice_idx] == ENV_OFF) note_balance[voice_idx] <= 9'd256;
                end
                increment[voice_idx] <= octave_frame ? (bent_increment << 1) : bent_increment;
                rom_addr <= phase[voice_idx][31:22];
                if (STRING_SAMPLE != 0) begin
                    string_address <= string_position[voice_idx][30:16];
                    string_fraction <= string_position[voice_idx][15:8];
                end
                state <= BOWED_STRINGS != 0 && timbre_frame == 1 ? ST_BOW_WAIT : ST_WAIT1;
            end
            ST_BOW_WAIT: if(bowed_done) begin
                wave_mix<=bowed_sample;
                gain<=gain_product[23:8];
                state<=ST_MULT;
            end
            ST_WAIT1: begin
                if (PAN_STRINGS != 0) pan_base_gain <= NEAR_NOTE_SOFTEN != 0 ? balanced_gain[31:16] : gain_product[23:8];
                state <= ST_CAP1;
            end
            ST_CAP1: begin
                if (PAN_STRINGS != 0) pan_gain_product <= pan_base_gain * pan_balance[voice_idx];
                fundamental <= rom_data;
                if (STRING_SAMPLE != 0) begin
                    if (spectral_active) begin
                        string_base <= string_data;
                        spectral_low_product <= pair_low_delta * $signed({1'b0,spectral_low[voice_idx]});
                        spectral_high_product <= pair_high_delta * $signed({1'b0,spectral_high[voice_idx]});
                    end else string_left <= string_data;
                    string_address <= string_position[voice_idx][30:16] == 15'h7fff ?
                                      15'h4000 : string_position[voice_idx][30:16] + 15'd1;
                end
                rom_addr <= phase[voice_idx][30:21];
                state <= spectral_active && STRING_SAMPLE != 0 ? ST_BLEND1 : ST_WAIT2;
            end
            ST_BLEND1: begin string_left <= blended_string; state <= ST_WAIT2; end
            ST_WAIT2: state <= ST_CAP2;
            ST_CAP2: begin
                second <= rom_data;
                if (STRING_SAMPLE != 0) begin
                    if (spectral_active) begin
                        string_base <= string_data;
                        spectral_low_product <= pair_low_delta * $signed({1'b0,spectral_low[voice_idx]});
                        spectral_high_product <= pair_high_delta * $signed({1'b0,spectral_high[voice_idx]});
                    end else string_interpolation <= string_delta * $signed({1'b0,string_fraction});
                end
                rom_addr <= triple_phase[31:22];
                state <= spectral_active && STRING_SAMPLE != 0 ? ST_BLEND2 : ST_WAIT3;
            end
            ST_BLEND2: begin
                string_interpolation <= blended_delta * $signed({1'b0,string_fraction});
                state <= ST_WAIT3;
            end
            ST_WAIT3: state <= ST_GAIN;
            ST_GAIN: begin
                case (timbre_frame)
                    0: wave_mix <= PIANO_PROFILE != 0 ?
                        fundamental_ext - (fundamental_ext >>> 2) +
                        (second_ext >>> 3) + (third_ext >>> 4) : fundamental_ext;
                    1: wave_mix <= STRING_SAMPLE != 0 ?
                        $signed({{2{string_left[15]}},string_left}) + (string_interpolation >>> 8) :
                        fundamental_ext + (second_ext >>> 2) + (third_ext >>> 3);
                    2: wave_mix <= fundamental_ext + (second_ext >>> 1) + (third_ext >>> 2);
                    3: wave_mix <= fundamental_ext + (second_ext >>> 1) - (third_ext >>> 2);
                endcase
                gain <= PAN_STRINGS != 0 && timbre_frame == 1 ? pan_gain_product[23:8] :
                        NEAR_NOTE_SOFTEN != 0 ? balanced_gain[31:16] : gain_product[23:8];
                state <= ST_MULT;
            end
            ST_MULT: begin
                product <= wave_mix * $signed({1'b0, gain});
                state <= ST_ADD;
            end
            ST_ADD: begin
                if (gate_frame[voice_idx]) pan_rank <= pan_rank + 1'b1;
                mix_acc <= mix_acc + voice_term;
                if (voice_idx == 31) state <= ST_FINAL;
                else begin
                    voice_idx <= voice_idx + 1'b1;
                    state <= BOWED_STRINGS!=0 ? ST_ENV_READ : ST_ADDR1;
                end
            end
            ST_FINAL: begin
                if (mix_acc > 24'sd32767) next_pcm <= 16'sd32767;
                else if (mix_acc < -24'sd32768) next_pcm <= -16'sd32768;
                else next_pcm <= mix_acc[15:0];
                ready <= 1;
                state <= ST_IDLE;
            end
            default: state <= ST_IDLE;
        endcase
        end
    end
endmodule
`undef VE32_ADVANCE_VOICE
