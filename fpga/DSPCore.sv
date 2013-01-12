module DSPCore #(
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
    input wire reset_n,
    input wire start,
    input wire[DWW-1:0] inputs[8],
    output logic[DWW-1:0] outputs[8]
    );

    // Instruction memory
    wire[IAW-1:0] addrI;
    wire[IWW-1:0] dataI;
    instruction_rom instruction_rom_inst(
        .clock(clk),
        .address(addrI),
        .q(dataI));
        
    // Data memory ports
    wire[DAW-1:0] addrA, addrB, addrW;
    wire[DWW-1:0] dataA, dataB, dataW;
    wire writeEn;

    uDSP #(.IAW(IAW), .IWW(IWW), .DAW(DAW), .DWW(DWW)) dsp (
        .clk, .reset_n, .start,
        .addrI, .dataI,
        .addrA, .dataA,
        .addrB, .dataB,
        .addrW, .dataW, .writeEn);


    wire[OffsetWidth-1:0] readAddresses[nSegments];
    wire[DWW-1:0] readDatas[nSegments];
    wire[OffsetWidth-1:0] writeAddress;
    wire[DWW-1:0] writeData;
    wire[nSegments-1:0] writeEnables;

    // Sample memory is a circular buffer
    logic[OffsetWidth-1:0] sampleMemoryOffset;
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) sampleMemoryOffset <= 0;
        else begin
            if (start)
                sampleMemoryOffset <= sampleMemoryOffset + 1;
        end
    end

    // Register file (segment 0)
    register_file #(.REGADDR_WIDTH(OffsetWidth), .DATA_WIDTH(DWW)) rf0(
        .clk,
        .readAddr(readAddresses[0] + sampleMemoryOffset), .writeAddr(writeAddress + sampleMemoryOffset),
        .readData(readDatas[0]), .writeData(writeData),
        .writeEnable(writeEnables[0]));

    // Input memory (segment 1)
    logic[DWW-1:0] inputData;
    always @(posedge clk) begin
        inputData <= inputs[readAddresses[1][2:0]];
        if (writeEnables[1]) outputs[writeAddress] <= writeData;
    end
    assign readDatas[1] = inputData;

    // Parameter memory (segment 2)
    parameter_memory pmem(
        .clk(clk),
        .addr(readAddresses[2]),
        .data(readDatas[2]));

    memCtl #(.IAW(IAW), .IWW(IWW), .DAW(DAW), .DWW(DWW)) mem (
        .clk,
        .addrA, .dataA,
        .addrB, .dataB,
        .addrW, .dataW, .writeEn,
        .readAddresses, .readDatas,
        .writeAddress, .writeData, .writeEnables);

endmodule
    