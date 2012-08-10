
`timescale 10ns/1ns

module spdif_out (
	input logic clk, // Requires a 12.288 MHz bit clock
	input bit [23:0] ldatain, rdatain, // Signed, 24 bits (LSB zero-padded)
	output logic datareq, // Asserted one clock tic before data is needed
	output bit serialout // S/PDIF bitstream
);

bit [0:127] piso;
bit [0:27] ldata;
bit [0:27] rdata;

bit[0:23] ldata_rev, rdata_rev;

always_comb begin
    for (int i=0; i<24; i++) begin
        ldata_rev[i] = ldatain[i];
        rdata_rev[i] = rdatain[i];
    end
end

bit [7:0] clockcount;
bit [7:0] framecount;

wire [6:0] bitclock_count = clockcount[7:1];

initial begin // TODO: Add a proper reset mechanism...
	clockcount = 0;
	framecount = 0;
end

always @(posedge clk) begin

	if (bitclock_count == 127)
		datareq = 1'b1; // Assert data request

	if (clockcount == 0) begin // Assemble new frame
	
		// Add validity, user, control, and parity bits to audio data
		ldata = {ldata_rev, 3'b100, ~(^ldata_rev)};
		rdata = {rdata_rev, 3'b100, ~(^rdata_rev)};
		
		// Left channel
		if (framecount == 0)
			piso[0:7] = 8'b11101000 ^ {8{serialout}}; // Start-of-packet left preamble ("B")
		else
			piso[0:7] = 8'b11100010 ^ {8{serialout}}; // Mid-packet left preamble ("M")
		for (int i = 0; i <= 27; i++) begin	
			piso[2*i+8] = ~piso[2*i+7]; // Adds 1st transition
			piso[2*i+9] = ldata[i] ^ piso[2*i+8]; // Adds 2nd transition if input bit is 1
		end
		
		// Right channel
		piso[64:71] = 8'b11100100 ^ {8{piso[63]}}; // Right preamble ("W")
		for (int i = 0; i <= 27; i++) begin
			piso[2*i+72] = ~piso[2*i+71]; // Adds 1st transition
			piso[2*i+73] = rdata[i] ^ piso[2*i+72]; // Adds 2nd transition if input bit is 1
		end
		
		// Deassert data request
		datareq = 1'b0; 
	end

	// Shift data out
    if (clockcount[0] == 0) begin
        serialout = piso[0];
        piso = {piso[1:127], 1'b0};
    end
	
	// Increment counters
	clockcount = clockcount + 1; // Loops around every 128 clocks (1 frame)
	
	if (clockcount == 0) // Increment frame count every new frame
		framecount = framecount + 1;
	
	if (framecount == 192) // Loop around every 192 frames (1 packet)
		framecount = 0;

end

endmodule


