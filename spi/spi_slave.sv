module spi_slave #(
	PARAM_WIDTH = 36,
    ADDR_WIDTH = 8
) (
	input wire clk,

    // SPI port
	input wire spi_SCLK, // spi clock
	input wire spi_SSEL, // spi slave select
	input wire spi_MOSI, // data in
	output logic spi_MISO, // data out

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
localparam PACKET_SIZE = PARAM_WIDTH + 4;
localparam COUNT_WIDTH = $clog2(PACKET_SIZE + 1);

// Synchronize signals
logic sclk, ssel, mosi;
synchronizer sclk_sync(clk, spi_SCLK, sclk);
synchronizer ssel_sync(clk, spi_SSEL, ssel);
synchronizer mosi_sync(clk, spi_MOSI, mosi);

logic prev_sclk;

logic sclk_posedge, sclk_negedge;

always_comb begin : proc_clkedges
	sclk_posedge = sclk & ~prev_sclk;
	sclk_negedge = ~sclk & prev_sclk;
end

logic [COUNT_WIDTH-1:0] bitsRemaining, bitsRemaining_next;
logic [PACKET_SIZE-1:0] inputReg, inputReg_next, outputReg, outputReg_next, toOutput;
logic loadOutput, dataReady, dataReady_next;
always_comb begin : proc_serdes
	spi_MISO = outputReg[PACKET_SIZE-1];

	// defaults (no latches!)
    dataReady_next = '0;
	bitsRemaining_next = bitsRemaining;
	inputReg_next = inputReg;
	outputReg_next = outputReg;

	if (ssel) begin
		// reset.
		bitsRemaining_next = PACKET_SIZE-1;
		inputReg_next = '0;
		outputReg_next = '0;
        dataReady_next = '0;
	end else if (sclk_posedge) begin
		// shift out.
		inputReg_next = {inputReg[PACKET_SIZE-2:0], mosi};
		outputReg_next = outputReg << 1;
        dataReady_next = '0;
	end else if (sclk_negedge) begin
		// read in.
		if (bitsRemaining) begin
			bitsRemaining_next = bitsRemaining_next - 1;
		end else begin
			bitsRemaining_next = PACKET_SIZE-1;
            dataReady_next = '1;
		end
	end else if (loadOutput) begin
        outputReg_next = toOutput;
    end
end

always_ff@(posedge clk) begin : proc_ff
	prev_sclk <= sclk;
	bitsRemaining <= bitsRemaining_next;
	inputReg <= inputReg_next;
	outputReg <= outputReg_next;
    dataReady <= dataReady_next;
end


// Memory interface
logic loadOutput_next, wr_enable_next, valid_next;
logic [PACKET_SIZE-1:0] toOutput_next;
logic [ADDR_WIDTH-1:0] rd_addr_next, wr_addr_next;
logic [PARAM_WIDTH-1:0] wr_data_next;
always_comb begin
    loadOutput_next = '0;
    toOutput_next = toOutput;
    rd_addr_next = rd_addr;
    wr_addr_next = wr_addr;
    wr_data_next = '0;
    wr_enable_next = '0;
    valid_next = valid;

    if (ssel) begin
        // Reset
        rd_addr_next = '0;
        wr_enable_next = '0;
        wr_addr_next = '0;
        // Prepare to read from address 0.
        loadOutput_next = '1;
        toOutput_next = {2'b01, rd_data[35:18], 2'b10, rd_data[17:0]}; // FIXME: hardcoded.
    end else if (dataReady) begin
        // Read from memory.
        rd_addr_next = rd_addr + '1;
        loadOutput_next = '1;
        toOutput_next = {2'b01, rd_data[35:18], 2'b10, rd_data[17:0]}; // FIXME: hardcoded.

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
