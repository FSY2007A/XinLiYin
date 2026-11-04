// Fixed damped room; Q16.8 feedback reduces coarse 16-bit tail quantization.
module string_room #(parameter D0=1499, D1=1759, D2=1999)(
    input wire clk, reset_n, sample_valid, enable,
    input wire signed [15:0] sample_in,
    output reg signed [15:0] sample_out,
    output reg valid
);
    reg signed [23:0] ram0[0:D0-1],ram1[0:D1-1],ram2[0:D2-1];
    reg signed [23:0] q0,q1,q2,f0,f1,f2;
    reg signed [15:0] dry;
    reg [10:0] p0,p1,p2;
    reg [11:0] filled;
    reg warm0,warm1,warm2,active,mode_active,state;
    wire signed [25:0] x = $signed({{10{dry[15]}},dry}) <<< 8;
    wire signed [25:0] w0 = warm0 ? {{2{q0[23]}},q0} : 26'sd0;
    wire signed [25:0] w1 = warm1 ? {{2{q1[23]}},q1} : 26'sd0;
    wire signed [25:0] w2 = warm2 ? {{2{q2[23]}},q2} : 26'sd0;
    // Fractional drops round toward zero so silence has a finite tail.
    function signed [25:0] half;
        input signed [25:0] value;
        begin half = (value < 0 ? value + 26'sd1 : value) >>> 1; end
    endfunction
    function signed [25:0] quarter;
        input signed [25:0] value;
        begin quarter = (value < 0 ? value + 26'sd3 : value) >>> 2; end
    endfunction
    function signed [25:0] sixteenth;
        input signed [25:0] value;
        begin sixteenth = (value < 0 ? value + 26'sd15 : value) >>> 4; end
    endfunction
    function signed [25:0] decay;
        input signed [25:0] value;
        begin decay = value - ((value >= 0 ? value+26'sd3 : value) >>> 2); end
    endfunction
    wire signed [25:0] a0=half(w0+$signed({{2{f0[23]}},f0}));
    wire signed [25:0] a1=half(w1+$signed({{2{f1[23]}},f1}));
    wire signed [25:0] a2=half(w2+$signed({{2{f2[23]}},f2}));
    wire signed [25:0] write0=quarter(x)+decay(a0);
    wire signed [25:0] write1=quarter(x)+decay(a1);
    wire signed [25:0] write2=quarter(x)+decay(a2);
    wire signed [25:0] mix=x-quarter(x)+sixteenth(w0)+sixteenth(w1)+sixteenth(w2);
    wire signed [25:0] rounded=(mix < 0 ? mix+26'sd255 : mix) >>> 8;
    always @(posedge clk) begin
        if (sample_valid && !state) begin q0<=ram0[p0];q1<=ram1[p1];q2<=ram2[p2]; end
        if (state && active) begin ram0[p0]<=write0[23:0];ram1[p1]<=write1[23:0];ram2[p2]<=write2[23:0]; end
    end
    always @(posedge clk) begin
        if (!reset_n) begin
            p0<=0;p1<=0;p2<=0;filled<=0;f0<=0;f1<=0;f2<=0;
            warm0<=0;warm1<=0;warm2<=0;active<=0;mode_active<=0;
            state<=0;dry<=0;sample_out<=0;valid<=0;
        end else begin
            valid<=0;
            if (!state && sample_valid) begin
                dry<=sample_in;active<=enable;mode_active<=enable;state<=1;
                warm0<=enable && mode_active && filled>=D0;
                warm1<=enable && mode_active && filled>=D1;
                warm2<=enable && mode_active && filled>=D2;
                if (!enable || !mode_active) begin p0<=0;p1<=0;p2<=0;filled<=0;f0<=0;f1<=0;f2<=0; end
            end else if (state) begin
                sample_out<=active ? rounded[15:0] : dry;
                valid<=1;state<=0;
                if (active) begin
                    f0<=a0[23:0];f1<=a1[23:0];f2<=a2[23:0];
                    p0<=p0==D0-1 ? 11'd0 : p0+1'b1;
                    p1<=p1==D1-1 ? 11'd0 : p1+1'b1;
                    p2<=p2==D2-1 ? 11'd0 : p2+1'b1;
                    if (filled<2048) filled<=filled+1'b1;
                end
            end
        end
    end
endmodule
