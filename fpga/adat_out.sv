// Copyright (c) 2012 Martin Segado
// All rights reserved (until we choose a license)

`timescale 10ns/1ns

module adat_out (
	input bit clk, rst, // Requires a 12.288 MHz clock & syncronous reset
	input bit timecode, midi, smux, // User bits per ADAT specification
	input bit signed [23:0] audio_bus [0:7], // 8 channels @ 24 bits
	output bit adat_bitstream, // ADAT bitstream output
	output bit data_request // Asserted as soon as previous data has been loaded.
);

bit [7:0] current_bit = 0;
bit [0:255] adat_piso = 0;

assign data_request = (current_bit == 0);

always @(posedge clk) begin

	if (current_bit == 0) begin // assemble ADAT stream
	
		// ADAT sync pattern
		adat_piso[0] = ~adat_bitstream;
		adat_piso[1:10] = {10{adat_piso[0]}};
		
		// User bits
		adat_piso[11] = ~adat_piso[10]; // Sync bit
		adat_piso[12] = adat_piso[11] ^ timecode;
		adat_piso[13] = adat_piso[12] ^ midi;
		adat_piso[14] = adat_piso[13] ^ smux;
		adat_piso[15] = adat_piso[14]; // Reserved, always equals zero
		
		// Audio data
		for (int c = 0; c <= 7; c++) begin	// Loop through 8 channels
			for (int s = 0; s <= 5; s++) begin // Loop through 6 nibbles in each channel
				adat_piso[16 + 30*c + 5*s] = ~adat_piso[15 + 30*c + 5*s]; // Sync bit
				adat_piso[17 + 30*c + 5*s] = adat_piso[16 + 30*c + 5*s] ^ audio_bus[c][23 - 4*s];
				adat_piso[18 + 30*c + 5*s] = adat_piso[17 + 30*c + 5*s] ^ audio_bus[c][22 - 4*s];
				adat_piso[19 + 30*c + 5*s] = adat_piso[18 + 30*c + 5*s] ^ audio_bus[c][21 - 4*s];
				adat_piso[20 + 30*c + 5*s] = adat_piso[19 + 30*c + 5*s] ^ audio_bus[c][20 - 4*s];
			end
		end
	end

	// Shift data out
	adat_bitstream = adat_piso[0];
	adat_piso = {adat_piso[1:255], 1'b0};
	
	current_bit = current_bit + 1; // Loops around every 256 clocks

	if (rst) begin // Synchronous reset mechanism
		adat_bitstream = 0;
		adat_piso = '0;
		current_bit = 0;
	end
end

endmodule 