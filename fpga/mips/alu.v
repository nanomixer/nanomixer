// Define control signals.
`define a_ADD  11'b00000000001
`define a_AND  11'b00000000010
`define a_XOR  11'b00000000100
`define a_OR   11'b00000001000
`define a_NOR  11'b00000010000
`define a_SUB  11'b00000100000
`define a_SLTU 11'b00001000000
`define a_SLT  11'b00010000000
`define a_SRA  11'b00100000000
`define a_SRL  11'b01000000000
`define a_SLL  11'b10000000000

// Reference ALU, using high-level RTL Verilog.
module ALU (
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [10:0] op,
    input wire [4:0] sa,
    output reg [31:0] out
);

    // The always @(*) syntax is a Verilog 2001 addition. It automatically
    // puts every variable referenced inside in the sensitivity list.
    always @(*) begin
        case(op)
            `a_ADD: out = a + b;
            `a_AND: out = a & b;
            `a_XOR: out = a ^ b;
            `a_OR:  out = a | b;
            `a_NOR: out = ~(a | b);
            `a_SUB: out = a - b;
            `a_SLTU: out = a < b;
            `a_SLT: out = slt(a, b);
            `a_SRA: out = sra(b, sa);
            `a_SRL: out = b >> sa;
            `a_SLL: out = b << sa;
				default: out = 0;
        endcase
    end

    // Combinational functions for the signed arithmetic:

    // slt: set less than (signed)
    function [31:0] slt;
        input [31:0] a, b;
        reg signed [31:0] aS, bS;
        begin
            aS[31:0] = a[31:0];
            bS[31:0] = b[31:0];
            slt = aS < bS;
        end
    endfunction

    // sra: shift right arithmetic
    function [31:0] sra;
        input [31:0] b, sa;
        reg signed [31:0] bS;
        begin
            bS[31:0] = b[31:0];
            sra = bS >>> sa;
        end
    endfunction

endmodule

