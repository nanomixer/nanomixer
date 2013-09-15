module memif #(
    WORD_WIDTH = 36,
    ADDR_WIDTH = 10,
    PACKET_WIDTH = WORD_WIDTH + 4
) (
    input logic reset,
    input logic clk,

    // serdes port
    input logic dataReady,
    input logic [PACKET_WIDTH-1:0] inPacket,
    output logic [PACKET_WIDTH-1:0] outPacket,

    // Memory read port
    output logic[ADDR_WIDTH-1:0] rd_addr,
    input logic[WORD_WIDTH-1:0] rd_data,

    // Memory write port
    output logic[ADDR_WIDTH-1:0] wr_addr,
    output logic[WORD_WIDTH-1:0] wr_data,
    output logic wr_enable,

    // Status
    output logic inPacketIsValid
);
/**
 * memif: adapts a sequence of packets (from SPI, e.g.) to read/write requests to RAM.
 *
 * A 'packet' encapsulates a data word (of an even number of bits). It divides the word into two equal-sized 'nibbles',
 * and prepends 'b01 and 'b10 to the first and second nibble, repectively. (I know, this is kinda silly.)
 *
 * The input and output sequences are both clocked by strobes of `dataReady` and delimited by assertions of `reset`.
 *
 * The first packet of the input sequence contains the initial read address, the second contains the write address,
 * and subsequent packets contain words to write to addresses in sequence until the next `reset`.
 *
 * The output sequence is undefined for the first packet, then it contains the words read from memory.
 *
 * A word is only written if its packet is valid, so sending an invalid packet (such as all zeros) can be used to
 * read words than are written.
 *
 * Timings:
 *
 * Memory I/O is all combinatorial.
 *
 * i: x R--
 * o: x x
 * c: x _/-
 * r: 1 0 ...
 */

localparam NIBBLE_WIDTH = WORD_WIDTH / 2;

// Unpack the received packet.
assign inPacketIsValid = (
    inPacket[PACKET_WIDTH-1:PACKET_WIDTH-2] == 2'b01 &&
    inPacket[PACKET_WIDTH/2-1:PACKET_WIDTH/2-2] == 2'b10);
logic [WORD_WIDTH-1:0] inWord;
assign inWord = {
    inPacket[PACKET_WIDTH-3:PACKET_WIDTH/2],
    inPacket[PACKET_WIDTH/2-3:0]};
logic [ADDR_WIDTH-1:0] inWordAsAddr;
assign inWordAsAddr = inWord[ADDR_WIDTH-1:0];

// Pack the word read from memory into a packet, at the moment by adding
// two extra bits to the beginning of each nibble.
assign outPacket = {
    2'b01, rd_data[WORD_WIDTH-1:NIBBLE_WIDTH], // NIBBLE_WIDTH bits
    2'b10, rd_data[NIBBLE_WIDTH-1:0]};

enum {GETTING_READ_ADDR, GETTING_WRITE_ADDR, STREAMING} state, state_next;
logic [ADDR_WIDTH-1:0] curReadAddr, curReadAddr_next, curWriteAddr, curWriteAddr_next;

// Since the memory will only write when we tell it to, might as well:
assign wr_addr = curWriteAddr;
assign wr_data = inWord;

always_comb begin
    unique case (state)
    GETTING_READ_ADDR: begin
        curReadAddr_next = inWordAsAddr;
        curWriteAddr_next = '0;
        rd_addr = inWordAsAddr; // a bit of an optimization, timing-wise.
        wr_enable = '0;
        state_next = GETTING_WRITE_ADDR;
    end
    GETTING_WRITE_ADDR: begin
        curReadAddr_next = curReadAddr + 1;
        curWriteAddr_next = inWordAsAddr;
        rd_addr = curReadAddr;
        wr_enable = '0;
        state_next = STREAMING;
    end
    STREAMING: begin
        curReadAddr_next = curReadAddr + 1;
        curWriteAddr_next = curWriteAddr + 1;
        rd_addr = curReadAddr;
        wr_enable = inPacketIsValid;
        state_next = STREAMING;
    end
    endcase
end

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= GETTING_READ_ADDR;
    end else begin
        if (dataReady) begin
            curReadAddr <= curReadAddr_next;
            curWriteAddr <= curWriteAddr_next;
            state <= state_next;
        end else begin
            // er, well, latch.
            curReadAddr <= curReadAddr;
            curWriteAddr <= curWriteAddr;
            state <= state;
        end
    end
end

endmodule
