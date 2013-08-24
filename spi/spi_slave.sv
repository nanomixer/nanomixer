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
    output logic wr_enable
);
localparam PACKET_SIZE = PARAM_WIDTH + 4;
localparam COUNT_WIDTH = $clog2(PACKET_SIZE + 1);

// States:
// START: start of transmission, before the first sclk edge
// WORD: within a word; bitIdx counts down to 0
// INTER: between words.


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
logic loadOutput_next;
logic [PACKET_SIZE-1:0] toOutput_next;
logic [PARAM_WIDTH-1:0] rd_addr_next;
always_comb begin
    loadOutput_next = '0;
    toOutput_next = toOutput;
    rd_addr_next = rd_addr;
    
    if (ssel) begin
        // Reset
        rd_addr_next = 'b0;
    end else if (dataReady) begin
        rd_addr_next = rd_addr + 'b1;
        loadOutput_next = '1;
        toOutput_next = {2'b0, rd_data};
    end
end

initial rd_addr = 0;
always_ff @(posedge clk) begin : proc_memif
    rd_addr <= rd_addr_next;
    loadOutput <= loadOutput_next;
    toOutput <= toOutput_next;
end

endmodule
