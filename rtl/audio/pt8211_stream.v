// Default 50 MHz -> BCK 1.5625 MHz / WS 48.828125 kHz; 16-bit LSBJ, WS low=right.
module pt8211_stream #(
    parameter integer STARTUP_CYCLES = 5000000,
    parameter integer STEREO = 0,
    parameter integer BCK_HALF_CYCLES = 16,
    parameter integer INTERPOLATE_4X = 0
)(
    input wire clk, reset_n,
    input wire signed [15:0] pcm,
    input wire signed [15:0] pcm_left,
    input wire pcm_valid, pause_when_zero,
    output reg bck, ws, din, frame_tick, underrun, ready,
    output reg [15:0] sample, sample_left
);
    reg [22:0] startup_count;
    localparam integer DIV_WIDTH = BCK_HALF_CYCLES > 1 ? $clog2(BCK_HALF_CYCLES) : 1;
    reg [DIV_WIDTH-1:0] half_count;
    reg [3:0] bit_index;
    reg [15:0] shift_word;
    reg started, paused;
    wire [15:0] source_word = ready && pcm_valid ? pcm : 16'd0;
    wire [15:0] source_left = ready && pcm_valid ? (STEREO != 0 ? pcm_left : pcm) : 16'd0;
    reg [1:0] subframe;
    reg signed [15:0] from_right, to_right, from_left, to_left;
    function signed [15:0] interpolate;
        input signed [15:0] from_pcm, to_pcm;
        input [1:0] fraction;
        reg signed [17:0] a, b, sum;
        begin
            a={{2{from_pcm[15]}},from_pcm}; b={{2{to_pcm[15]}},to_pcm};
            case(fraction)
                1:begin sum=(a<<<1)+a+b;interpolate=sum>>>2;end
                2:begin sum=a+b;interpolate=sum>>>1;end
                3:begin sum=a+(b<<<1)+b;interpolate=sum>>>2;end
                default:interpolate=to_pcm;
            endcase
        end
    endfunction
    wire [15:0] next_word = INTERPOLATE_4X != 0 ? interpolate(from_right,to_right,subframe) : source_word;
    wire [15:0] next_left = INTERPOLATE_4X != 0 ? interpolate(from_left,to_left,subframe) : source_left;
    wire source_boundary = INTERPOLATE_4X == 0 || subframe == 0;
    wire stop_at_zero = ws && pause_when_zero && sample == 0 && sample_left == 0 && next_word == 0 && next_left == 0 && source_boundary;
    wire frame_load = paused ? !pause_when_zero : half_count == BCK_HALF_CYCLES-1 && bck && bit_index == 15 && ws && !stop_at_zero;
    // Render at the original rate; freeze each source pair, then send its four
    // convex interpolation steps. No pitch/envelope/room clocks are accelerated.
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin subframe<=0;from_right<=0;to_right<=0;from_left<=0;to_left<=0;end
        else if(INTERPOLATE_4X != 0 && frame_load) begin
            subframe<=subframe+1'b1;
            if(subframe==0) begin
                from_right<=to_right;to_right<=source_word;
                from_left<=to_left;to_left<=source_left;
            end
        end
    end
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            startup_count <= 0; ready <= 0;
            half_count <= 0; bit_index <= 15; shift_word <= 0;
            bck <= 0; ws <= 1; din <= 0; frame_tick <= 0;
            underrun <= 0; started <= 0; paused <= 0; sample <= 0;
            sample_left <= 0;
        end else begin
            frame_tick <= 0; underrun <= 0;
            if (!ready) begin
                if (startup_count == STARTUP_CYCLES - 1) ready <= 1;
                else startup_count <= startup_count + 1'b1;
            end
            if (paused) begin
                if (!pause_when_zero) begin
                    // Resume with right MSB while BCK is low, then wait a full
                    // half cycle before the first rising edge. No extra LSB.
                    paused <= 0; half_count <= 0; bit_index <= 0; ws <= 0;
                    frame_tick <= source_boundary; sample <= next_word; sample_left <= next_left;
                    din <= next_word[15]; shift_word <= {next_word[14:0], 1'b0};
                end
            end else begin
              half_count <= half_count == BCK_HALF_CYCLES-1 ? 0 : half_count + 1'b1;
              if (half_count == BCK_HALF_CYCLES-1) begin
                bck <= ~bck;
                if (bck) begin
                    if (bit_index == 15) begin
                        // Finish both zero words before stopping at a falling
                        // edge. The DAC retains zero without an analog shutdown.
                        if (stop_at_zero) begin
                            paused <= 1; half_count <= 0;
                        end else if (ws) begin
                            ws <= 0; bit_index <= 0;
                            frame_tick <= source_boundary;
                            sample <= next_word;
                            sample_left <= next_left;
                            din <= next_word[15];
                            shift_word <= {next_word[14:0], 1'b0};
                            underrun <= ready && started && !pcm_valid && source_boundary;
                            started <= 1;
                        end else begin
                            ws <= 1; bit_index <= 0;
                            din <= sample_left[15];
                            shift_word <= {sample_left[14:0], 1'b0};
                        end
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        din <= shift_word[15];
                        shift_word <= {shift_word[14:0], 1'b0};
                    end
                end
              end
            end
        end
    end
endmodule
