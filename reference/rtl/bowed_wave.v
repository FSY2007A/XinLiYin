// STK-derived coefficients; see project/usb-pt8211/pc-audio/STK_LICENSE.txt.
// Greedy cross-note spectral assignment runs only when the held set changes.
module bowed_mask #(parameter integer PACKED=0)(
    input wire clk, reset_n,
    input wire [31:0] gate,
    output reg [767:0] attenuate,
    output reg busy
);
    wire [20:0] entry;
    wire [767:0] conflicts;
    reg [767:0] kept, shadow;
    reg [31:0] snapshot;
    reg [9:0] pointer;
    reg pass;
    reg [2:0] state;
    reg [7:0] conflict_groups;
    reg candidate, eligible;
    reg [9:0] partial_id;
    wire [4:0] note = entry[20:16];
    wire [4:0] harmonic = entry[15:11];
    wire [31:0] lower = (snapshot << 1) | (snapshot << 2);
    wire mandatory = (harmonic == 0 && !lower[note]) ||
                     (lower[note] && (harmonic == 1 || harmonic == 2));
    integer i;
    generate if(PACKED!=0) begin: packed_table
        reg [212:0] priority_rom[0:767];
        // Keep the encoded boundary: otherwise Gowin unfolds the two ROM stages.
        reg [212:0] packed_entry /* synthesis syn_preserve=1 */;
        wire [191:0] packed_codes /* synthesis syn_keep=1 */;
        reg [767:0] registered_conflicts;
        wire [767:0] decoded_conflicts;
        assign packed_codes=packed_entry[212:21];
        bowed_conflict_decode decode(packed_codes,decoded_conflicts);
        assign entry=packed_entry[20:0];
        assign conflicts=registered_conflicts;
        initial $readmemh("bowed_priority_packed.mem",priority_rom);
        always @(posedge clk) begin
            packed_entry<=priority_rom[pointer];
            registered_conflicts<=decoded_conflicts;
        end
    end else begin: original_table
        reg [20:0] priority_rom[0:767];
        reg [767:0] conflict_rom[0:767];
        reg [20:0] original_entry;
        reg [767:0] original_conflicts;
        assign entry=original_entry;assign conflicts=original_conflicts;
        initial begin
            $readmemh("bowed_priority.mem",priority_rom);
            $readmemh("bowed_conflicts.mem",conflict_rom);
        end
        always @(posedge clk) begin
            original_entry<=priority_rom[pointer];
            original_conflicts<=conflict_rom[original_entry[10:1]];
        end
    end endgenerate
    always @(posedge clk) begin
        if (!reset_n) begin
            attenuate<=0; busy<=0; snapshot<=0; pointer<=0; pass<=0;
            state<=0; kept<=0; shadow<=0; conflict_groups<=0;
            candidate<=0; eligible<=0; partial_id<=0;
        end else case(state)
            0: if (gate != snapshot) begin
                snapshot<=gate; pointer<=0; pass<=0; kept<=0; shadow<=0;
                busy<=1; state<=1;
            end
            1: state<=2; // Synchronous priority ROM read.
            2: begin
                partial_id<=entry[10:1]; eligible<=entry[0];
                candidate<=snapshot[note] && (mandatory != pass);
                state<=3;
            end
            3: begin
                for(i=0;i<8;i=i+1)
                    conflict_groups[i]<=|(conflicts[i*96+:96] & kept[i*96+:96]);
                state<=4;
            end
            4: begin
                if(candidate) begin
                    shadow[partial_id]<=|conflict_groups;
                    if (!(|conflict_groups) && eligible) kept[partial_id]<=1;
                end
                if(pointer==767) begin
                    pointer<=0;
                    if(pass) state<=5;
                    else begin pass<=1; state<=1; end
                end else begin pointer<=pointer+1'b1; state<=1; end
            end
            5: begin attenuate<=shadow; busy<=0; state<=0; end
            default: state<=0;
        endcase
    end
endmodule

// Two partials per clock, registered sine/complex multiply/weight/accumulate.
// Called once per voice per source frame; completion is independent of phase.
module bowed_wave #(parameter integer PACKED_MASK=0)(
    input wire clk, reset_n, start,
    input wire [31:0] gate,
    input wire active, held, onset,
    input wire [4:0] voice,
    input wire [31:0] phase,
    output reg signed [17:0] sample,
    output reg done
);
    wire [767:0] mask;
    wire mask_busy;
    bowed_mask #(.PACKED(PACKED_MASK)) selector(clk,reset_n,gate,mask,mask_busy);
    reg [63:0] coefficient_rom [0:383];
    reg signed [15:0] sine_rom [0:4095];
    reg [215:0] weight_rows [0:31];
    reg [215:0] weights, saved_weights;
    reg [31:0] row_valid;
    reg saved_valid;
    reg [4:0] note;
    reg note_held, note_onset;
    reg [3:0] pair;
    reg loading, sending, running;
    reg [31:0] phase_a, phase_b, phase_step;
    reg [8:0] coefficient_address;
    reg [9:0] partial_address;
    reg [63:0] coefficients;
    reg signed [15:0] sin_a, cos_a, sin_b, cos_b;
    reg [8:0] weight_a0,weight_b0,weight_a1,weight_b1,weight_a2,weight_b2;
    reg signed [31:0] ar,ai,br,bi;
    reg signed [32:0] partial_a,partial_b;
    reg signed [42:0] weighted_a,weighted_b;
    reg signed [39:0] accumulator;
    reg [3:0] valid;
    wire signed [39:0] term_a = weighted_a >>> 8;
    wire signed [39:0] term_b = weighted_b >>> 8;
    wire [11:0] cos_address_a = phase_a[31:20] + 12'd1024;
    wire [11:0] cos_address_b = phase_b[31:20] + 12'd1024;
    wire [215:0] initial_weights = saved_valid ? saved_weights : {24{9'd256}};
    wire [8:0] old_a = weights[8:0];
    wire [8:0] old_b = weights[17:9];
    wire [8:0] target_a = mask[partial_address] ? 9'd16 : 9'd256;
    wire [8:0] target_b = mask[partial_address+10'd1] ? 9'd16 : 9'd256;
    function [8:0] following_weight;
        input [8:0] old_value,target;
        input key_held,key_onset;
        begin
            if(key_onset) following_weight=target;
            else if(!key_held) following_weight=old_value;
            else if(old_value<target) following_weight=old_value+1'b1;
            else if(old_value>target) following_weight=old_value-1'b1;
            else following_weight=old_value;
        end
    endfunction
    wire [8:0] next_a=following_weight(old_a,target_a,note_held,note_onset);
    wire [8:0] next_b=following_weight(old_b,target_b,note_held,note_onset);
    initial begin
        $readmemh("bowed_coeff.mem",coefficient_rom);
        $readmemh("bowed_sine.mem",sine_rom);
    end
    // Synchronous read and independent write infer on-chip RAM. Valid bits hide
    // uninitialised rows after reset without resetting every stored weight.
    always @(posedge clk) begin
        if(start) saved_weights<=weight_rows[voice];
        if(reset_n && running && !loading && !sending && valid==0)
            weight_rows[note]<=weights;
    end
    always @(posedge clk) begin
        coefficients<=coefficient_rom[coefficient_address];
        sin_a<=sine_rom[phase_a[31:20]]; cos_a<=sine_rom[cos_address_a];
        sin_b<=sine_rom[phase_b[31:20]]; cos_b<=sine_rom[cos_address_b];
        if(!reset_n) begin
            sample<=0;done<=0;loading<=0;sending<=0;running<=0;valid<=0;
            phase_a<=0;phase_b<=0;phase_step<=0;pair<=0;note<=0;
            coefficient_address<=0;partial_address<=0;
            weights<={24{9'd256}};note_held<=0;note_onset<=0;
            row_valid<=0;saved_valid<=0;
            weight_a0<=0;weight_b0<=0;weight_a1<=0;weight_b1<=0;
            weight_a2<=0;weight_b2<=0;
            ar<=0;ai<=0;br<=0;bi<=0;partial_a<=0;partial_b<=0;
            weighted_a<=0;weighted_b<=0;accumulator<=0;
        end else begin
            done<=0;
            valid<={valid[2:0],sending};
            if(start) begin
                phase_a<=phase;phase_b<=phase<<1;phase_step<=phase<<1;
                coefficient_address<=(voice<<3)+(voice<<2);
                partial_address<=(voice<<4)+(voice<<3);
                pair<=0;note<=voice;note_held<=held;note_onset<=onset;
                saved_valid<=active && row_valid[voice];
                accumulator<=0;loading<=1;sending<=0;running<=1;
            end else if(loading) begin
                weights<=initial_weights;loading<=0;sending<=1;
            end else if(sending) begin
                weight_a0<=next_a;weight_b0<=next_b;
                // Twelve fixed rotations restore canonical harmonic order at
                // writeback, avoiding a multiply-indexed 216-bit read/write mux.
                weights<={next_b,next_a,weights[215:18]};
                phase_a<=phase_a+phase_step;phase_b<=phase_b+phase_step;
                coefficient_address<=coefficient_address+1'b1;
                partial_address<=partial_address+10'd2;
                if(pair==11) sending<=0;
                else pair<=pair+1'b1;
            end
            if(valid[0]) begin
                ar<=cos_a*$signed(coefficients[63:48]);
                ai<=sin_a*$signed(coefficients[47:32]);
                br<=cos_b*$signed(coefficients[31:16]);
                bi<=sin_b*$signed(coefficients[15:0]);
                weight_a1<=weight_a0;weight_b1<=weight_b0;
            end
            if(valid[1]) begin
                partial_a<=$signed({ar[31],ar})-$signed({ai[31],ai});
                partial_b<=$signed({br[31],br})-$signed({bi[31],bi});
                weight_a2<=weight_a1;weight_b2<=weight_b1;
            end
            if(valid[2]) begin
                weighted_a<=partial_a*$signed({1'b0,weight_a2});
                weighted_b<=partial_b*$signed({1'b0,weight_b2});
            end
            if(valid[3]) accumulator<=accumulator+term_a+term_b;
            if(running && !loading && !sending && valid==0) begin
                sample<=accumulator>>>15;done<=1;running<=0;
                row_valid[note]<=1;
            end
        end
    end
endmodule
