module memif #(
    WORD_WIDTH = 36,
    ADDR_WIDTH = 10,
    PACKET_SIZE = WORD_WIDTH + 4
) (
    input logic reset,
    input logic clk,

    // serdes port
    output logic [PACKET_SIZE-1:0] toOutput,
    output logic loadOutput,
    input logic [PACKET_SIZE-1:0] inputReg,
    input logic dataReady,

    // Memory read port
    output logic[ADDR_WIDTH-1:0] rd_addr,
    input logic[WORD_WIDTH-1:0] rd_data,

    // Memory write port
    output logic[ADDR_WIDTH-1:0] wr_addr,
    output logic[WORD_WIDTH-1:0] wr_data,
    output logic wr_enable,

    // Status
    output logic valid
);

localparam NIBBLE_WIDTH = WORD_WIDTH / 2;

// Memory interface
logic loadOutput_next, wr_enable_next, valid_next;
logic [PACKET_SIZE-1:0] toOutput_next;
logic [ADDR_WIDTH-1:0] rd_addr_next, wr_addr_next;
logic [WORD_WIDTH-1:0] wr_data_next;
always_comb begin
    loadOutput_next = '0;
    rd_addr_next = rd_addr;
    wr_addr_next = wr_addr;
    wr_data_next = '0;
    wr_enable_next = '0;
    valid_next = valid;

    // Pack the word read from memory into a packet, at the moment by adding
    // two extra bits to the beginning of each nibble.
    //
    // This will only be valid (the output to load in) at the end of a packet,
    // but we might as well compute it unconditionally.
    toOutput_next = {
        2'b01, rd_data[WORD_WIDTH-1:NIBBLE_WIDTH], // NIBBLE_WIDTH bits
        2'b10, rd_data[NIBBLE_WIDTH-1:0]};

    if (reset) begin
        // Reset write address to 0.
        wr_addr_next = '0;
        // Prepare to read from address 0, so it's ready as soon as reset is deasserted.
        rd_addr_next = '0;
        // Since reset is asserted for many clocks, there will be enough time
        // for the memory to finish reading from address 0, so we can go ahead
        // and load the output we're receiving from it.
        loadOutput_next = '1;
    end else if (dataReady) begin
        // End of a packet. This means (1) we're ready to output the next thing
        // we got from memory and (2) we just received a packet, which we should
        // write to memory.

        // (1) Output the word we read from memory.
        loadOutput_next = '1;

        // (2) Write what we just received to memory, if it's valid.
        valid_next = (
            inputReg[PACKET_SIZE-1:PACKET_SIZE-2] == 2'b01 &&
            inputReg[PACKET_SIZE/2-1:PACKET_SIZE/2-2] == 2'b10);
        wr_data_next = {
            inputReg[PACKET_SIZE-3:PACKET_SIZE/2],
            inputReg[PACKET_SIZE/2-3:0]};
        if (valid_next) begin
            wr_enable_next = '1;
        end
    end else if (wr_enable) begin
        // Last clock was the end of a packet, so the current packet is dealing
        // with the subsequent addresses.
        wr_addr_next = wr_addr + '1;
        rd_addr_next = rd_addr + '1;
    end
end

initial rd_addr = '0;
initial wr_enable = '0;
always_ff @(posedge clk) begin : proc_memif
    rd_addr <= rd_addr_next;
    wr_enable <= wr_enable_next;
    wr_addr <= wr_addr_next;
    wr_data <= wr_data_next;
    loadOutput <= loadOutput_next;
    toOutput <= toOutput_next;
    valid <= valid_next;
end


endmodule
