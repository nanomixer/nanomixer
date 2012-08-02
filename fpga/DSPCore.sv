module DSPCore #(
    // Current instruction ROM is 512 words => 9 bit address
    parameter IAW = 9,
    parameter IWW = 36,
    // Current data memories are 128 words + 3-bit segment => 10 bit addresses
    parameter DAW = 10,
    parameter DWW = 36)
(
    input wire clk,
    input wire reset,
    input wire start,
    input wire[DWW-1:0] inputs[8],
    output wire[DWW-1:0] outputs[8]
    );

    // Instruction memory port
    wire[IAW-1:0] addrI;
    wire[IWW-1:0] dataI;
        
    // Data memory ports
    wire[DAW-1:0] addrA, addrB, addrW;
    wire[DWW-1:0] dataA, dataB, dataW;
    wire writeEn;

    uDSP #(.IAW(IAW), .IWW(IWW), .DAW(DAW), .DWW(DWW)) dsp (
        .clk, .reset, .start, 
        .addrI, .dataI,
        .addrA, .dataA,
        .addrB, .dataB,
        .addrW, .dataW, .writeEn);
        
    memCtl #(.IAW(IAW), .IWW(IWW), .DAW(DAW), .DWW(DWW)) mem (
        .clk,
        .addrI, .dataI,
        .addrA, .dataA,
        .addrB, .dataB,
        .addrW, .dataW, .writeEn,
        .inputs, .outputs);
endmodule
    