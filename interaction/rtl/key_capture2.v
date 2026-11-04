// 同步并消抖两个低有效板载控制键；按住时 held 对应位为高。
// 50 MHz 默认按下/松开滤波时间分别为 1 ms / 3 ms。
module key_capture2 #(
    parameter integer PRESS_CYCLES = 50000,
    parameter integer RELEASE_CYCLES = 150000
)(
    input wire clk, reset_n,
    input wire [1:0] key_n,
    output reg [1:0] held
);
    reg [1:0] sync1, sync2;
    reg [17:0] stable_count [0:1];
    integer i;

    always @(posedge clk) begin
        if (!reset_n) begin
            sync1 <= 2'b11;
            sync2 <= 2'b11;
            held <= 2'b00;
            for (i = 0; i < 2; i = i + 1) stable_count[i] <= 0;
        end else begin
            sync1 <= key_n;
            sync2 <= sync1;
            for (i = 0; i < 2; i = i + 1) begin
                if (sync2[i] != held[i]) begin
                    stable_count[i] <= 0;
                end else if (stable_count[i] ==
                             (held[i] ? RELEASE_CYCLES-1 : PRESS_CYCLES-1)) begin
                    stable_count[i] <= 0;
                    held[i] <= !held[i];
                end else stable_count[i] <= stable_count[i] + 1'b1;
            end
        end
    end
endmodule
