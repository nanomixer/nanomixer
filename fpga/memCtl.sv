module memCtl #(
    // Current instruction ROM is 512 words => 9 bit address
    parameter IAW = 9,
    parameter IWW = 36,
    // Current data memories are 128 words + 3-bit segment => 10 bit addresses
    parameter DAW = 10,
    parameter DWW = 36)
(
    input wire clk,

    // Instruction memory port
    input wire[IAW-1:0] addrI,
    output wire[IWW-1:0] dataI,
    
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
    
    input wire[DWW-1:0] inputs[8],
    output logic[DWW-1:0] outputs[8]
    
    );
    
    localparam uDAW = 7; // unpacked data word width
    localparam SW = DAW-uDAW; // segment address width
    // Unpack segmented addresses into segment and data address
    wire[SW-1:0] segmentA = addrA[DAW-1:DAW-SW]; wire[uDAW-1:0] daA = addrA[uDAW-1:0];
    wire[SW-1:0] segmentB = addrB[DAW-1:DAW-SW]; wire[uDAW-1:0] daB = addrB[uDAW-1:0];
    wire[SW-1:0] segmentW = addrW[DAW-1:DAW-SW]; wire[uDAW-1:0] daW = addrW[uDAW-1:0];
    
    // Instruction memory
    instruction_rom instruction_rom_inst(
        .clock(clk),
        .address(addrI),
        .q(dataI));

    wire[DWW-1:0] rfDataA, rfDataB;

    // Register file
    register_file #(.REGADDR_WIDTH(uDAW), .DATA_WIDTH(36)) rf0(
        .clk,
        .readAddrA(daA), .readAddrB(daB), .writeAddr(daW),
        .dataA(rfDataA), .dataB(rfDataB), .dataW(dataW),
        .writeEnable(writeEn && (segmentW == 0)));

    // Parameter memory
    wire[DWW-1:0] pmemData;
    parameter_memory pmem(
        .clk(clk),
        .addr({1'b0, (segmentA == 0 ? daA : daB)}),
        .data(pmemData));
    
    // Input reading
    logic[DWW-1:0] inputDataA, inputDataB;
    always @(posedge clk) begin
        inputDataA <= inputs[daA[2:0]];
        inputDataB <= inputs[daB[2:0]];
    end

    // Read results are available the cycle after they are requested.
    logic[SW-1:0] segmentA_out, segmentB_out;
    always @(posedge clk) begin
        segmentA_out <= segmentA;
        segmentB_out <= segmentB;
    end

    // Data memory A and B controller
    always_comb begin
        unique case (segmentA_out)
        0: // register file
            dataA = rfDataA;
        1: // IO
            dataA = inputDataA;
        2: // params
            dataA = pmemData;
        endcase
        unique case (segmentB_out)
        0: // rf
            dataB = rfDataB;
        1: // IO
            dataB = inputDataB;
        2: // params, note that port A address has priority
            dataB = pmemData;
        endcase
    end
    
    // IO write controller
    always @(posedge clk) begin
        if ((segmentW == 1) && writeEn) outputs[daW[2:0]] <= dataW;
    end
    
endmodule
