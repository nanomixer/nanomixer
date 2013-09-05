module memif #(
    WORD_WIDTH = 36,
    ADDR_WIDTH = 10
) (
    input logic reset,

    // serdes port
    output logic [WORD_WIDTH-1:0] toOutput,
    output logic loadOutput,
    input logic [WORD_WIDTH-1:0] inputReg,
    input logic dataReady,

    // Memory read port
    output logic[ADDR_WIDTH-1:0] rd_addr,
    input logic[PARAM_WIDTH-1:0] rd_data,

    // Memory write port
    output logic[ADDR_WIDTH-1:0] wr_addr,
    output logic[PARAM_WIDTH-1:0] wr_data,
    output logic wr_enable,

    // Status
    output wire valid
);

localparam NIBBLE_WIDTH = WORD_WIDTH / 2;
localparam PACKET_SIZE = WORD_WIDTH + 4;

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

    toOutput_next = {
        2'b01, rd_data[2*NIBBLE_WIDTH+1:NIBBLE_WIDTH+2], // NIBBLE_WIDTH bits
        2'b10, rd_data[NIBBLE_WIDTH-1:0]}; // also NIBBLE_WIDTH bits!

    if (reset) begin
        // Reset write address to 0.
        wr_addr_next = '0;
        // Prepare to read from address 0, so it's ready as soon as reset is deasserted.
        rd_addr_next = '0;
        loadOutput_next = '1;
    end else if (dataReady) begin
        // Read from memory.
        rd_addr_next = rd_addr + '1;
        loadOutput_next = '1;

        // Write to memory.
        valid_next = (
            inputReg[39:38] == 2'b01 &&
            inputReg[19:18] == 2'b10);
        if (valid_next) begin
            wr_data_next = {inputReg[37:20], inputReg[17:0]};
            wr_enable_next = '1;
        end
    end else if (wr_enable) begin
        // We wrote to memory last cycle; now advance the address.
        wr_addr_next = wr_addr + '1;
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
