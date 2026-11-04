// 50 MHz 时扫描 4×4 低有效二极管矩阵，held 为高表示对应键稳定按下。
// row_pull_low 是开漏拉低使能；顶层必须将未选行释放为高阻态。
module matrix_keyscan16 #(
    parameter integer ROW_SCAN_CYCLES = 6250
)(
    input wire clk,
    input wire reset_n,
    input wire [3:0] col_n,
    output reg [3:0] row_pull_low,
    output reg [15:0] held,
    output reg [15:0] note_on,
    output reg [15:0] note_off
);
    localparam integer SCAN_COUNT_WIDTH = (ROW_SCAN_CYCLES <= 1) ? 1 : $clog2(ROW_SCAN_CYCLES);
    reg [SCAN_COUNT_WIDTH-1:0] scan_count;
    reg [1:0] row_index;
    reg [3:0] col_sync1, col_sync2;
    reg [2:0] debounce_count [0:15];
    wire row_sample = (scan_count == ROW_SCAN_CYCLES - 1);
    integer i;

    always @* begin
        row_pull_low = 4'b0000;
        if (reset_n) row_pull_low[row_index] = 1'b1;
    end

    always @(posedge clk) begin
        if (!reset_n) begin
            scan_count <= 0;
            row_index <= 0;
            col_sync1 <= 4'hf;
            col_sync2 <= 4'hf;
        end else begin
            col_sync1 <= col_n;
            col_sync2 <= col_sync1;
            if (row_sample) begin
                scan_count <= 0;
                row_index <= row_index + 1'b1;
            end else begin
                scan_count <= scan_count + 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!reset_n) begin
            held <= 0;
            note_on <= 0;
            note_off <= 0;
            for (i = 0; i < 16; i = i + 1) debounce_count[i] <= 0;
        end else begin
            note_on <= 0;
            note_off <= 0;
            if (row_sample) begin
                for (i = 0; i < 16; i = i + 1) begin
                    if (row_index == i / 4) begin
                        if (!col_sync2[i % 4]) begin
                            if (held[i]) begin
                                debounce_count[i] <= 0;
                            end else if (debounce_count[i] == 3'd1) begin
                                debounce_count[i] <= 0;
                                held[i] <= 1'b1;
                                note_on[i] <= 1'b1;
                            end else begin
                                debounce_count[i] <= debounce_count[i] + 1'b1;
                            end
                        end else if (held[i]) begin
                            if (debounce_count[i] == 3'd5) begin
                                debounce_count[i] <= 0;
                                held[i] <= 1'b0;
                                note_off[i] <= 1'b1;
                            end else begin
                                debounce_count[i] <= debounce_count[i] + 1'b1;
                            end
                        end else begin
                            debounce_count[i] <= 0;
                        end
                    end
                end
            end
        end
    end
endmodule
