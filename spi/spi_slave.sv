module spi_slave #(
	PARAM_WIDTH = 8,
	COUNT_WIDTH = 3
) (
	input wire clk,
	input wire spi_SCLK, // spi clock
	input wire spi_SSEL, // spi slave select
	input wire spi_MOSI, // data in
	output logic spi_MISO // data out
);

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
logic [PARAM_WIDTH-1:0] inputReg, inputReg_next, outputReg, outputReg_next;
always_comb begin : proc_serdes
	spi_MISO = outputReg[PARAM_WIDTH-1];

	// defaults (no latches!)
	bitsRemaining_next = bitsRemaining;
	inputReg_next = inputReg;
	outputReg_next = outputReg;

	if (spi_SSEL) begin
		// reset.
		bitsRemaining_next = PARAM_WIDTH-1;
		inputReg_next = '0;
		outputReg_next = '0;
	end else if (sclk_posedge) begin
		// shift out.
		inputReg_next = {inputReg[PARAM_WIDTH-2:0], mosi};
		outputReg_next = outputReg << 1;
	end else if (sclk_negedge) begin
		// read in.
		if (bitsRemaining) begin
			bitsRemaining_next = bitsRemaining_next - 1;
		end else begin
			// echo!
			outputReg_next = inputReg;
			bitsRemaining_next = PARAM_WIDTH-1;
		end
	end
end

always_ff@(posedge clk) begin : proc_ff
	prev_sclk <= sclk;
	bitsRemaining <= bitsRemaining_next;
	inputReg <= inputReg_next;
	outputReg <= outputReg_next;
end

endmodule
