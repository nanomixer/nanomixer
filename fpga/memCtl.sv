module memCtl(
    // Instruction memory port
    input wire[IAW-1:0] AddrI,
    output wire[IWW-1:0] DataI,
    
    // Data memory port A
    input wire[DAW-1:0] AddrA,
    output wire[DWW-1:0] DataA,
    
    // Data memory port B
    input wire[DAW-1:0] AddrB,
    output wire[DWW-1:0] DataB,
    
    // Data memory port W
    input wire[DAW-1:0] AddrW,
    input wire[DWW-1:0] DataW,
    input wire WriteEn,
    
    input wire[DWW-1:0] inputs[8],
    output logic[DWW-1:0] outputs[8]
    
    );
    
    parameter uDAW = DAW-SW; // unpacked data word width
    // Unpack segmented addresses into segment and data address
    wire[SW-1:0] segmentA = AddrA[DAW-1:DAW-SW]; wire[uDAW-1:0] daA = AddrA[uDAW-1:0];
    wire[SW-1:0] segmentB = AddrB[DAW-1:DAW-SW]; wire[uDAW-1:0] daB = AddrB[uDAW-1:0];
    wire[SW-1:0] segmentW = AddrW[DAW-1:DAW-SW]; wire[uDAW-1:0] daW = AddrW[uDAW-1:0];
    
    // Instruction memory
    instruction_rom instruction_rom_inst(
        .clock(clk),
        .address(AddrI),
        .q(DataI));

    wire[uDWW-1:0] rfDataA, rfDataB;

    // Register file
    register_file #(.REGADDR_WIDTH(uDAW), .DATA_WIDTH(36)) rf0(
        .readAddrA(daA), .readAddrB(daB), .writeAddr(daW),
        .dataA(rfDataA), .dataB(rfDataB), .dataW(DataW),
        .writeEnable(segmentW == 0));

    // Parameter memory
    wire[7:0] pmemData;
    parameter_memory pmem(
        .clk(clk),
        .addr(segmentA == 0 ? daA : daB),
        .data(pmemData));
    
    // Reads are combinatorial here.
    // FIXME: maybe buffer the inputs bus.

    // Data memory A and B controller
    always_comb begin
        unique case (segmentA)
        0: // register file
            DataA = rfDataA;
        1: // IO
            DataA = inputs[daA[2:0]];
        2: // params
            DataA = pmemData;
        endcase
        unique case (segmentB)
        0: // rf
            DataB = rfDataB;
        1: // IO
            DataB = inputs[daB[2:0]];
        2: // params, note that port A address has priority
            DataB = pmemData;
        endcase
    end
    
    // IO write controller
    always @(posedge clk) begin
        if (segmentW == 1) outputs[daW[2:0]] <= DataW;
    end
    
endmodule
