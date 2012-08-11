module memCtl #(
    // Current instruction ROM is 512 words => 9 bit address
    parameter IAW = 9,
    parameter IWW = 36,

    parameter SegmentWidth = 2,
    parameter OffsetWidth = 8,
    parameter nSegments = 1 << SegmentWidth,
    parameter DAW = SegmentWidth + OffsetWidth,
    parameter DWW = 36)
(
    input wire clk,
    
    /// Interface to the CPU
    // Data memory port A
    input wire[DAW-1:0] addrA,
    output logic[DWW-1:0] dataA,
    
    // Data memory port B
    input wire[DAW-1:0] addrB,
    output logic[DWW-1:0] dataB,
    
    // Data memory port W
    input wire[DAW-1:0] addrW,
    input wire[DWW-1:0] dataW,
    input wire writeEn,

    /// Interface to memories
    output wire[OffsetWidth-1:0] readAddresses[nSegments],
    input wire[DWW-1:0] readDatas[nSegments],
    output wire[OffsetWidth-1:0] writeAddress,
    output wire[DWW-1:0] writeData,
    output wire[nSegments-1:0] writeEnables
    );
    
    // Unpack segmented addresses into segment and offset
    wire [SegmentWidth-1:0] segmentA, segmentB, segmentW;
    wire [OffsetWidth-1:0] offsetA, offsetB, offsetW;
    assign
      {segmentA, offsetA} = addrA,
      {segmentB, offsetB} = addrB,
      {segmentW, offsetW} = addrW;

    // Assign read addresses
    genvar i;
    generate for (i=0; i<nSegments; i++) begin:readAddrs
        assign readAddresses[i] = (segmentA == i) ? offsetA : offsetB;
    end endgenerate

    // Assign write
    assign writeAddress = offsetW;
    assign writeData = dataW;
    assign writeEnables = writeEn ? (1 << segmentW) : 'b0;

    // Read results are available the cycle after they are requested.
    // But we select combinatorially between the sources.
    // So register the segment addresses.
    logic[SegmentWidth-1:0] segmentA_out, segmentB_out;
    always @(posedge clk) begin
        segmentA_out <= segmentA;
        segmentB_out <= segmentB;
    end
    
    // Read results
    assign dataA = readDatas[segmentA_out], dataB = readDatas[segmentB_out];
   
endmodule
