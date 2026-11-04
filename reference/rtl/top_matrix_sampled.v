// Frozen real-instrument audio core; replace only the note source with matrix scanning.
module top_matrix_sampled #(
    parameter integer STARTUP_CYCLES=5000000,
    parameter integer KEY_PRESS_CYCLES=50000,
    parameter integer KEY_RELEASE_CYCLES=150000
)(
    input wire sys_clk,rst_n,key0_n,key1_n,
    inout wire [3:0] matrix_row_n,
    input wire [3:0] matrix_col_n,
    output wire hp_bck,hp_ws,hp_din,pa_en
);
    reg [2:0] reset_pipe=0;
    always @(posedge sys_clk or negedge rst_n)
        if(!rst_n) reset_pipe<=0;
        else reset_pipe<={reset_pipe[1:0],1'b1};
    wire reset_n=reset_pipe[2];
    wire [15:0] held,note_on,note_off;
    wire [3:0] row_pull_low;
    genvar row_pin;
    generate for(row_pin=0;row_pin<4;row_pin=row_pin+1) begin:row_driver
        assign matrix_row_n[row_pin]=row_pull_low[row_pin] ? 1'b0 : 1'bz;
    end endgenerate
    matrix_keyscan16 keys(.clk(sys_clk),.reset_n(reset_n),.col_n(matrix_col_n),
        .row_pull_low(row_pull_low),.held(held),.note_on(note_on),.note_off(note_off));
    wire ready,fault,active;
    wire [1:0] timbre,controls;
    wire [15:0] pcm_right,pcm_left;
    wire [8:0] volume_applied;
    keyboard_audio_core #(.BOWED_STRINGS(1),.OUTPUT_OVERSAMPLE(4),.SAMPLED_ORGAN(1),
        .SAMPLED_GUITAR(1),.PACKED_BOWED_MASK(1),.MASTER_VOLUME(1),
        .STARTUP_CYCLES(STARTUP_CYCLES),.KEY_PRESS_CYCLES(KEY_PRESS_CYCLES),
        .KEY_RELEASE_CYCLES(KEY_RELEASE_CYCLES)) audio_core(
        .clk(sys_clk),.reset_n(reset_n),.key0_n(key0_n),.key1_n(key1_n),
        .keyboard_state({2'b10,held}),.bck(hp_bck),.ws(hp_ws),.din(hp_din),.pa_en(pa_en),
        .ready(ready),.underrun_seen(fault),.amp_active(active),.timbre(timbre),
        .controls(controls),.tx_pcm(pcm_right),.tx_pcm_left(pcm_left),
        .volume_target(9'd256),.volume_applied(volume_applied));
endmodule
