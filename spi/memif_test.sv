module memif_test #(
    parameter real CLK_FREQ = 100.0e6,
    parameter int WORD_WIDTH = 8,
    parameter int ADDR_WIDTH = 8);

localparam time CLK_PERIOD = (1.0e9/CLK_FREQ)*1ns;
localparam PACKET_WIDTH = WORD_WIDTH + 4;
localparam NIBBLE_WIDTH = WORD_WIDTH / 2;

logic clk;
initial clk=0;
always #(CLK_PERIOD/2) clk = ~clk;

logic reset;

// serdes port
logic dataReady;
logic [PACKET_WIDTH-1:0] inPacket;
logic [PACKET_WIDTH-1:0] outPacket;

// Memory read port
logic[ADDR_WIDTH-1:0] rd_addr;
logic[WORD_WIDTH-1:0] rd_data;

// Memory write port
logic[ADDR_WIDTH-1:0] wr_addr;
logic[WORD_WIDTH-1:0] wr_data;
logic wr_enable;

// Status
logic inPacketIsValid;

memif #(.WORD_WIDTH(WORD_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u1 (.clk, .reset, .dataReady, .inPacket, .outPacket,
    .rd_addr, .rd_data, .wr_addr, .wr_data, .wr_enable, .inPacketIsValid);

function logic [PACKET_WIDTH-1:0] packPacket(logic [WORD_WIDTH-1:0] word);
    packPacket = {
        2'b01, word[WORD_WIDTH-1:NIBBLE_WIDTH], // NIBBLE_WIDTH bits
        2'b10, word[NIBBLE_WIDTH-1:0]};
endfunction

// Fake memory.
always_ff @(posedge clk) begin
    rd_data <= rd_addr;
end

initial begin
    reset = '1;
    #(CLK_PERIOD * 2)
    reset = '0;
    dataReady = '0;

    #(CLK_PERIOD);
    // Read addr.
    inPacket = packPacket('h5);
    #(CLK_PERIOD);
    dataReady = '1;
    #(CLK_PERIOD);
    dataReady = '0;

    // Write addr.
    inPacket = packPacket('hd);
    #(CLK_PERIOD);
    dataReady = '1;
    #(CLK_PERIOD);
    dataReady = '0;

    // First write data.
    inPacket = packPacket('h5f);
    #(CLK_PERIOD);
    dataReady = '1;
    #(CLK_PERIOD);
    dataReady = '0;
    $stop;
end

endmodule
