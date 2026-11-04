module keyboard_audio_core #(
    parameter integer PIANO_PROFILE = 1,
    parameter integer NEAR_NOTE_SOFTEN = 1,
    parameter integer NEAR_SPECTRAL_STRINGS = 0,
    parameter integer STRING_GAIN_BOOST = 0,
    parameter integer BOWED_STRINGS = 0,
    parameter integer SAMPLED_ORGAN = 0,
    parameter integer STRING_SAMPLE = 1,
    parameter integer SPATIAL_STRINGS = 1,
    parameter integer FIXED_TIMBRE = -1,
    parameter integer OUTPUT_OVERSAMPLE = 1,
    parameter integer STARTUP_CYCLES = 5000000,
    parameter integer KEY_PRESS_CYCLES = 50000,
    parameter integer KEY_RELEASE_CYCLES = 150000,
    parameter integer PACKED_BOWED_MASK = 0,
    parameter integer SAMPLED_GUITAR = 0,
    parameter integer MASTER_VOLUME = 0,
    parameter integer OUTPUT_GAIN_SHIFT = 0
)(
    input wire clk, reset_n, key0_n, key1_n,
    input wire [17:0] keyboard_state,
    input wire remote_timbre_valid,
    input wire [1:0] remote_timbre,
    output wire bck, ws, din, pa_en,
    output wire ready,
    output reg underrun_seen,
    output reg amp_active /* synthesis syn_preserve=1 */,
    output reg [1:0] timbre,
    output wire [1:0] controls,
    output wire [15:0] tx_pcm, tx_pcm_left,
    input wire [8:0] volume_target,
    output wire [8:0] volume_applied
);
    reg control0_d;
    wire frame_tick, pcm_valid, voice_valid, underrun;
    wire signed [15:0] raw_left, pcm_left, pcm_right, base_left, base_right;
    wire base_valid, organ_valid, organ_tail;
    wire signed [15:0] organ_left, organ_right;
    wire can_play = keyboard_state[17] && !keyboard_state[16];
    wire [15:0] held = can_play ? keyboard_state[15:0] : 16'd0;
    reg [8:0] quiet_frames;
    reg stream_active;
    key_capture2 #(.PRESS_CYCLES(KEY_PRESS_CYCLES), .RELEASE_CYCLES(KEY_RELEASE_CYCLES)) buttons(
        .clk(clk), .reset_n(reset_n), .key_n({key1_n, key0_n}), .held(controls));
    always @(posedge clk) begin
        if (!reset_n) begin timbre <= FIXED_TIMBRE < 0 ? 2'd0 : FIXED_TIMBRE[1:0]; control0_d <= 0; underrun_seen <= 0; end
        else begin
            control0_d <= controls[0];
            if (FIXED_TIMBRE >= 0) timbre <= FIXED_TIMBRE[1:0];
            else if (remote_timbre_valid) timbre <= remote_timbre;
            else if (controls[0] && !control0_d) timbre <= timbre + 1'b1;
            if (underrun) underrun_seen <= 1;
        end
    end
    // Keep analog bias stable across ordinary key releases to avoid shutdown
    // transients. Pause serial clocks only after the release tail has settled.
    always @(posedge clk) begin
        if (!reset_n || !ready || underrun_seen) amp_active <= 0;
        else amp_active <= 1;
        if (!reset_n || !ready || !can_play || underrun_seen) begin
            stream_active <= 0; quiet_frames <= 0;
        end else if (|held) begin
            stream_active <= 1; quiet_frames <= 0;
        end else if (SAMPLED_ORGAN != 0 && timbre == 2 && organ_tail) begin
            stream_active <= 1; quiet_frames <= 0;
        end else if (frame_tick) begin
            if (tx_pcm != 0 || tx_pcm_left != 0 ||
                (MASTER_VOLUME != 0 && (pcm_left != 0 || pcm_right != 0))) quiet_frames <= 0;
            else if (quiet_frames == 9'd511) stream_active <= 0;
            else quiet_frames <= quiet_frames + 1'b1;
        end
    end
    voice_engine_32 #(.PIANO_PROFILE(PIANO_PROFILE),.NEAR_NOTE_SOFTEN(NEAR_NOTE_SOFTEN),.NEAR_SPECTRAL_STRINGS(NEAR_SPECTRAL_STRINGS),.BOWED_STRINGS(BOWED_STRINGS),.PACKED_BOWED_MASK(PACKED_BOWED_MASK),.STRING_SAMPLE(STRING_SAMPLE),.PAN_STRINGS(SPATIAL_STRINGS),.PAN_RIGHT(0)) voices(
        .clk(clk), .reset_n(reset_n), .frame_tick(frame_tick), .gate({16'd0, held}),
        .timbre(timbre), .octave(controls[1]), .expression(8'd255),
        .next_pcm(raw_left), .ready(voice_valid), .retrigger(32'd0), .pitch_offset(16'sd0));
    // Piano remains algorithmic. Erhu and guzheng use the shared sample bank.
    assign base_left=raw_left;
    assign base_right=raw_left;
    assign base_valid=voice_valid;
    generate if(SAMPLED_ORGAN != 0) begin: sampled_organ
        wire signed [15:0] dry_organ;
        wire rendered_organ,room_valid;
        wire rendered=voice_valid && rendered_organ;
        reg rendered_d,effect_ready;
        reg [1:0] render_timbre;
        always @(posedge clk) begin
            if(!reset_n) begin rendered_d<=0;effect_ready<=0;render_timbre<=0;end
            else begin
                rendered_d<=rendered;
                if(frame_tick) begin effect_ready<=0;render_timbre<=timbre;end
                if(room_valid) effect_ready<=1;
            end
        end
        organ_sampler pipes(.clk(clk),.reset_n(reset_n),.frame_tick(frame_tick),
            .enable(timbre==2 && can_play && !underrun_seen),.held(held),.octave(controls[1]),
            .sample(dry_organ),.ready(rendered_organ));
        organ_room hall(.clk(clk),.reset_n(reset_n),.sample_valid(rendered && !rendered_d),
            .enable(render_timbre==2 && can_play && !underrun_seen),.sample_in(dry_organ),
            .left(organ_left),.right(organ_right),.valid(room_valid),.tail_active(organ_tail));
        assign organ_valid=effect_ready;
    end else begin: legacy_organ
        assign organ_left=0;assign organ_right=0;assign organ_valid=0;assign organ_tail=0;
    end endgenerate
    wire signed [15:0] sampled_instrument_pcm;
    wire sampled_instrument_valid;
    wire sampled_instrument_enable=(timbre==2'd1 || timbre==2'd3) && can_play && !underrun_seen;
    sample_sampler instruments(
        .clk(clk),.reset_n(reset_n),.frame_tick(frame_tick),
        .enable(sampled_instrument_enable),.held({16'd0,held}),
        .instrument(timbre==2'd3 ? 2'd1 : 2'd0),.octave(controls[1]),
        .sample(sampled_instrument_pcm),.ready(sampled_instrument_valid));
    assign pcm_left=sampled_instrument_enable ? sampled_instrument_pcm :
                    SAMPLED_ORGAN!=0 && timbre==2 ? organ_left : base_left;
    assign pcm_right=sampled_instrument_enable ? sampled_instrument_pcm :
                     SAMPLED_ORGAN!=0 && timbre==2 ? organ_right : base_right;
    assign pcm_valid=sampled_instrument_enable ? sampled_instrument_valid :
                     SAMPLED_ORGAN!=0 && timbre==2 ? organ_valid : base_valid;
    // Symmetric truncation preserves exact zero and avoids a DC rounding bias.
    function signed [15:0] boost_string;
        input signed [15:0] value;
        reg signed [16:0] extended, half_value, scaled;
        begin
            extended={value[15],value};
            half_value=(value<0 ? extended+17'sd1 : extended) >>> 1;
            scaled=extended+half_value;
            boost_string=scaled>17'sd32767 ? 16'sh7fff :
                         scaled< -17'sd32768 ? 16'sh8000 : scaled[15:0];
        end
    endfunction
    wire string_boost = STRING_GAIN_BOOST != 0 && timbre == 1;
    wire signed [15:0] dac_pcm = can_play && !underrun_seen ?
                                (string_boost ? boost_string(pcm_right) : pcm_right) : 16'sd0;
    wire signed [15:0] dac_left = can_play && !underrun_seen ?
                                 (string_boost ? boost_string(pcm_left) : pcm_left) : 16'sd0;
    wire signed [15:0] output_right, output_left;
    wire output_valid;
    generate if(MASTER_VOLUME!=0) begin: master_volume
        audio_master_volume gain(.clk(clk),.reset_n(reset_n),.target(volume_target),
            .pcm_left(dac_left),.pcm_right(dac_pcm),.pcm_valid(pcm_valid),
            .left(output_left),.right(output_right),.valid(output_valid),.applied(volume_applied));
    end else begin: fixed_volume
        assign output_left=dac_left;assign output_right=dac_pcm;assign output_valid=pcm_valid;
        assign volume_applied=9'd256;
    end endgenerate
    function signed [15:0] apply_gain;
        input signed [15:0] value;
        reg signed [19:0] widened;
        begin
            widened={{4{value[15]}},value} <<< OUTPUT_GAIN_SHIFT;
            if(widened>20'sd32767) apply_gain=16'sh7fff;
            else if(widened< -20'sd32768) apply_gain=16'sh8000;
            else apply_gain=widened[15:0];
        end
    endfunction
    wire signed [15:0] dac_output_right=apply_gain(output_right);
    wire signed [15:0] dac_output_left=apply_gain(output_left);
    i2s_pcm5102_stream #(.STARTUP_CYCLES(STARTUP_CYCLES),.STEREO(SPATIAL_STRINGS),
        .BCK_HALF_CYCLES(16/OUTPUT_OVERSAMPLE),.INTERPOLATE_4X(OUTPUT_OVERSAMPLE==4)) audio(
        .clk(clk), .reset_n(reset_n), .pcm(dac_output_right), .pcm_left(dac_output_left), .pcm_valid(output_valid),
        .pause_when_zero(ready && !stream_active),
        .bck(bck), .ws(ws), .din(din), .frame_tick(frame_tick),
        .underrun(underrun), .ready(ready), .sample(tx_pcm),.sample_left(tx_pcm_left));
    assign pa_en = !ready || underrun_seen || !amp_active;
endmodule

// Q8 attenuation only, unity=256. Independent ramp keeps moving even while audio is paused.
module audio_master_volume #(parameter integer STEP_CYCLES=4096)(
    input wire clk,reset_n,
    input wire [8:0] target,
    input wire signed [15:0] pcm_left,pcm_right,
    input wire pcm_valid,
    output reg signed [15:0] left,right,
    output reg valid,
    output reg [8:0] applied
);
    localparam integer TIMER_BITS=STEP_CYCLES>1 ? $clog2(STEP_CYCLES) : 1;
    reg [TIMER_BITS-1:0] timer;
    wire signed [9:0] gain={1'b0,applied};
    reg signed [25:0] product_left,product_right;
    function [15:0] truncate_gain;
        input signed [25:0] value;
        reg signed [25:0] scaled;
        begin
            scaled=value<0 ? -((-value)>>>8) : value>>>8;
            truncate_gain=scaled[15:0];
        end
    endfunction
    // Register the multiplies before rounding, avoiding a long path into the serial sender.
    reg product_valid;
    always @(posedge clk) begin
        if(!reset_n) begin
            timer<=0;applied<=9'd256;product_left<=0;product_right<=0;
            product_valid<=0;left<=0;right<=0;valid<=0;
        end else begin
            if(timer==STEP_CYCLES-1) begin
                timer<=0;
                if(applied<target) applied<=applied+1'b1;
                else if(applied>target) applied<=applied-1'b1;
            end else timer<=timer+1'b1;
            product_left<=pcm_left*gain;product_right<=pcm_right*gain;product_valid<=pcm_valid;
            left<=truncate_gain(product_left);right<=truncate_gain(product_right);valid<=product_valid;
        end
    end
endmodule
