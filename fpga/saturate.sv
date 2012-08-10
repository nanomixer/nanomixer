module saturate #(
    parameter IN_WIDTH = 36,
    parameter OUT_WIDTH = 24,
    parameter HEADROOM = 6
    )(
    input wire [IN_WIDTH-1:0] in,
    output logic overflow,
    output logic [OUT_WIDTH-1:0] out);
    
    // in (36->24 bit example):
    // 35 ... 30 29 ... 6 5 ... 0
    //  ^------^  ^-----^  ^----^
    //  headroom    num     precision
    always_comb begin
        if ({HEADROOM{in[IN_WIDTH-1]}} != in[IN_WIDTH-2:IN_WIDTH-HEADROOM-1]) begin
            // uh oh, clipped!
            overflow <= 1'b1;
            if (in[IN_WIDTH-1] == 0) begin
                out <= {1'b0, {(OUT_WIDTH-1){1'b1}}}; // largest positive number
            end else begin
                out <= {1'b1, {(OUT_WIDTH-1){1'b0}}}; // largest negative number
            end
        end else begin
            overflow <= 1'b0;
            out <= in[IN_WIDTH-HEADROOM-1:IN_WIDTH-HEADROOM-OUT_WIDTH];
        end
    end
    
endmodule
