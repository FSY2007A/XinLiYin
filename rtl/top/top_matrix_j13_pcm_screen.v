// Matrix J9 plus TJC touch, with PCM5102A and screen placed on J13 so the
// user's existing J8 control wiring remains physically untouched.
module top_matrix_j13_pcm_screen #(
    parameter integer STARTUP_CYCLES=5000000,
    parameter integer KEY_PRESS_CYCLES=50000,
    parameter integer KEY_RELEASE_CYCLES=150000
)(
    input wire sys_clk,rst_n,key0_n,key1_n,
    inout wire [3:0] matrix_row_n,
    input wire [3:0] matrix_col_n,
    input wire hmi_rx,pc_rx,
    output wire hmi_tx,pc_tx,
    output wire i2s_bck,i2s_lrck,i2s_din
);
    reg [2:0] reset_pipe=0;
    always @(posedge sys_clk or negedge rst_n)
        if(!rst_n)reset_pipe<=0;
        else reset_pipe<={reset_pipe[1:0],1'b1};
    wire reset_n=reset_pipe[2];

    wire [15:0] matrix_held,note_on,note_off,held;
    wire [3:0] row_pull_low;
    genvar row_pin;
    generate for(row_pin=0;row_pin<4;row_pin=row_pin+1) begin:row_driver
        assign matrix_row_n[row_pin]=row_pull_low[row_pin] ? 1'b0 : 1'bz;
    end endgenerate
    matrix_keyscan16 keys(.clk(sys_clk),.reset_n(reset_n),.col_n(matrix_col_n),
        .row_pull_low(row_pull_low),.held(matrix_held),.note_on(note_on),.note_off(note_off));

    wire screen_note_valid,screen_mask_valid,screen_volume_valid;
    wire screen_timbre_valid,screen_gain_valid,resync_request;
    wire [4:0] screen_note;
    wire [15:0] screen_mask;
    wire [1:0] screen_timbre;
    wire [8:0] screen_volume;
    wire [6:0] screen_gain;
    tjc_hmi_rx screen_input(.clk(sys_clk),.reset_n(reset_n),.rx(hmi_rx),
        .timbre_valid(screen_timbre_valid),.timbre_value(screen_timbre),
        .volume_valid(screen_volume_valid),.volume_value(screen_volume),
        .gain_valid(screen_gain_valid),.gain_value(screen_gain),
        .resync_request(resync_request),.note_valid(screen_note_valid),
        .note_value(screen_note),.mask_valid(screen_mask_valid),.mask_value(screen_mask));

    wire merged_changed;
    touch_note_merge notes_merge(.clk(sys_clk),.reset_n(reset_n),
        .pc_held(matrix_held),.note_valid(screen_note_valid),.note_value(screen_note),
        .mask_valid(screen_mask_valid),.mask_value(screen_mask),
        .clear_screen(resync_request || screen_timbre_valid),
        .held(held),.changed(merged_changed));

    wire [8:0] volume_target,volume_applied;
    wire [6:0] display_gain;
    wire display_gain_valid;
    tjc_control_merge controls_merge(.clk(sys_clk),.reset_n(reset_n),
        .pc_volume_valid(1'b0),.pc_volume(9'd256),
        .screen_volume_valid(screen_volume_valid),.screen_volume(screen_volume),
        .pc_gain_valid(1'b0),.pc_gain(7'd64),
        .screen_gain_valid(screen_gain_valid),.screen_gain(screen_gain),
        .volume(volume_target),.gain(display_gain),.gain_valid(display_gain_valid));

    wire ready,fault,active;
    wire [1:0] timbre,controls;
    wire [15:0] pcm_right,pcm_left;
    keyboard_audio_core #(
        .BOWED_STRINGS(0),.OUTPUT_OVERSAMPLE(4),.SAMPLED_ORGAN(1),
        .SAMPLED_GUITAR(0),.PACKED_BOWED_MASK(0),.STRING_SAMPLE(0),
        .SPATIAL_STRINGS(0),.MASTER_VOLUME(1),
        .OUTPUT_GAIN_SHIFT(2),
        .STARTUP_CYCLES(STARTUP_CYCLES),.KEY_PRESS_CYCLES(KEY_PRESS_CYCLES),
        .KEY_RELEASE_CYCLES(KEY_RELEASE_CYCLES)
    ) audio_core(
        .clk(sys_clk),.reset_n(reset_n),.key0_n(key0_n),.key1_n(key1_n),
        .keyboard_state({2'b10,held}),.remote_timbre_valid(screen_timbre_valid),
        .remote_timbre(screen_timbre),
        .bck(i2s_bck),.ws(i2s_lrck),.din(i2s_din),.pa_en(),
        .ready(ready),.underrun_seen(fault),.amp_active(active),
        .timbre(timbre),.controls(controls),
        .tx_pcm(pcm_right),.tx_pcm_left(pcm_left),
        .volume_target(volume_target),.volume_applied(volume_applied));

    wire [1023:0] wave_history;
    keyboard_status_uart #(.NOTE_ECHO(1),.SOURCE_ID(2),.VOLUME_CONTROL(1)) status(
        .clk(sys_clk),.reset_n(reset_n),.rx(pc_rx),.tx(pc_tx),.held(held),
        .timbre(timbre),.audio_ready(ready),.audio_fault(fault),
        .octave(controls[1]),.keyboard_ready(1'b1),.invalid_report(1'b0),
        .pcm_left(pcm_left),.pcm_right(pcm_right),
        .note_snapshot(note_on || note_off || merged_changed),
        .volume_target(volume_target),.volume_applied(volume_applied),
        .hmi_wave_history(wave_history));

    tjc_hmi_uart_tx screen_link(.clk(sys_clk),.reset_n(reset_n),.tx(hmi_tx),
        .resync_request(resync_request),.pcm_left(pcm_left),.pcm_right(pcm_right),
        .timbre(timbre),.notes(held),.volume_target(volume_target),
        .volume_applied(volume_applied),.wave_history(wave_history),
        .wave_gain(display_gain),.wave_gain_valid(display_gain_valid));
endmodule
