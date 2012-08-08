module saturate (
    input wire [35:0] in,
    output logic overflow,
    output logic [23:0] out);
    
    // in (36-24 bit example):
    // 35 ... 30 29 ... 6 5 ... 0
    //  ^------^  ^-----^  ^----^
    //  headroom    num     precision
    always_comb begin
        if ({6{in[35]}} != in[34:29]) begin
            // uh oh, clipped!
            overflow <= 1'b1;
            if (in[35] == 0) begin
                out <= {1'b0, {23{1'b1}}}; // largest positive number
            end else begin
                out <= {1'b1, {23{1'b0}}}; // largest negative number
            end
        end else begin
            overflow <= 1'b0;
            out <= in[29:6];
        end
    end
    
endmodule
