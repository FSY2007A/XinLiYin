// PCM5102A standard I2S transmitter. The frozen audio core keeps using
// pt8211_stream for its native-rate interpolation and frame timing.
module i2s_pcm5102_stream #(
    parameter integer STARTUP_CYCLES = 5000000,
    parameter integer STEREO = 1,
    parameter integer BCK_HALF_CYCLES = 16,
    parameter integer INTERPOLATE_4X = 0
)(
    input wire clk, reset_n,
    input wire signed [15:0] pcm, pcm_left,
    input wire pcm_valid, pause_when_zero,
    output reg bck, ws, din,
    output wire frame_tick, underrun, ready,
    output wire [15:0] sample, sample_left
);
    wire legacy_bck, legacy_ws, legacy_din;
    pt8211_stream #(
        .STARTUP_CYCLES(STARTUP_CYCLES),
        .STEREO(STEREO),
        .BCK_HALF_CYCLES(BCK_HALF_CYCLES),
        .INTERPOLATE_4X(INTERPOLATE_4X)
    ) source(
        .clk(clk), .reset_n(reset_n),
        .pcm(pcm), .pcm_left(pcm_left), .pcm_valid(pcm_valid),
        .pause_when_zero(pause_when_zero),
        .bck(legacy_bck), .ws(legacy_ws), .din(legacy_din),
        .frame_tick(frame_tick), .underrun(underrun), .ready(ready),
        .sample(sample), .sample_left(sample_left)
    );

    // 50 MHz / (2 * 8) = 3.125 MHz BCLK and 48.828 kHz LRCLK.
    // Match the I2S timing already exercised by the WM8978 build:
    // LRCLK changes, one zero bit is sent, then 16 sample bits MSB first.
    localparam integer HALF_CYCLES = 8;
    reg [2:0] half_count;
    reg [5:0] bit_pos;
    reg [15:0] left_hold;
    reg [15:0] right_hold;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            half_count <= 0;
            bit_pos <= 0;
            left_hold <= 0;
            right_hold <= 0;
            bck <= 0;
            ws <= 0;
            din <= 0;
        end else begin
            half_count <= half_count == HALF_CYCLES-1 ? 0 : half_count + 1'b1;
            if (half_count == HALF_CYCLES-1) begin
                bck <= ~bck;
                if (bck) begin
                    bit_pos <= bit_pos + 1'b1;
                    if (bit_pos == 6'd0) begin
                        ws <= 0;
                        din <= 0;
                        left_hold <= sample_left;
                        right_hold <= sample;
                    end else if (bit_pos == 6'd32) begin
                        ws <= 1;
                        din <= 0;
                    end else if (bit_pos >= 6'd1 && bit_pos <= 6'd16)
                        din <= left_hold[16-bit_pos];
                    else if (bit_pos >= 6'd33 && bit_pos <= 6'd48)
                        din <= right_hold[48-bit_pos];
                    else din <= 1'b0;
                end
            end
        end
    end
endmodule
