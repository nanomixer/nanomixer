module posedgeFF #(parameter width = 1) (
    input wire clk,
    input wire reset,
    input wire[width-1:0] d,
    output logic[width-1:0] q);
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) q <= 0;
        else q <= d;
    end
    
endmodule
