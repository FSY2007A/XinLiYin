// Sample-derived harmonic wavetable; source and processing in assets/README.md.
module string_sample_rom(
    input wire clk,
    input wire [14:0] address,
    output reg signed [15:0] sample
);
    reg signed [15:0] memory [0:32767];
    initial $readmemh("violin_loop.mem", memory);
    always @(posedge clk) sample <= memory[address];
endmodule

// Two small periodic banks share the original voice position and fractional phase.
module string_pair_rom(
    input wire clk,
    input wire [7:0] address,
    output reg signed [15:0] lower_sample, higher_sample
);
    reg signed [15:0] lower_memory [0:255];
    reg signed [15:0] higher_memory [0:255];
    initial begin
        $readmemh("violin_pair_low.mem", lower_memory);
        $readmemh("violin_pair_high.mem", higher_memory);
    end
    always @(posedge clk) begin
        lower_sample <= lower_memory[address];
        higher_sample <= higher_memory[address];
    end
endmodule
