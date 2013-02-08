// Copyright (c) 2012 Martin Segado
// All rights reserved (until we choose a license)

`timescale 10ns/1ns

module adat_in (
	input bit clk, rst, // Requires a 98.304 MHz clock & syncronous reset
	input bit adat_async, // Raw asynchronous ADAT input
	output bit data_valid, data_ready,
	output bit timecode, midi, smux, // User bits per ADAT specification
	output bit signed [23:0] audio_bus [0:7] // 8 channels @ 24 bits
);

bit adat_s1, adat_s2, adat_synced, last_sample;
enum bit [2:0] {IDLE, SYNC_WAIT, SYNC, BIT_WAIT, BIT_SAMPLE, PARSE} state, next;
bit [5:0] sync_counter;
bit [2:0] tic_counter;
bit [7:0] current_bit;
bit [0:245] adat_deser;

// State-independent sequential logic:
always_ff @(posedge clk) begin
	adat_s1 <= adat_async;
	adat_s2 <= adat_s1;
	adat_synced <= adat_s2; // Synchronize raw ADAT bitstream 
	
	if (adat_synced != adat_s2)
		sync_counter <= '0; // Reset sync-detect counter whenever input changes
	else
		sync_counter <= sync_counter + 2'b1; // Otherwise, increment sync-detect counter
end

initial begin
		state = IDLE;
		data_valid = 0;
		data_ready = 0;
end

// State machine operations:
always_ff @(posedge clk) begin
	if (rst) begin // Synchronous reset
		state <= IDLE;
		data_valid = 0;
		data_ready = 0;
	end
	else state <= next; // Increment state if not in reset

	tic_counter = tic_counter + 2'b1; // Increment tic counter
	
	unique case (state)
		SYNC_WAIT: last_sample <= adat_synced; // Set "last sample" to current value
	
		SYNC: begin
			tic_counter = 0; // Reset tic counter
			current_bit <= 0; // Reset bit counter
			data_ready = 0; // Clear data ready strobe
		end
		
		BIT_WAIT: begin
		
		end

		BIT_SAMPLE: begin
			adat_deser <= {adat_deser[1:245], adat_synced^last_sample}; // Shift in decoded bit
			last_sample <= adat_synced; // Save sample value
			current_bit <= current_bit + 2'b1; // Increment bit counter
		end
			
		PARSE: begin
			data_valid = 1;
			for (int i = 0; i <= 245; i = i + 5) begin
				data_valid = data_valid & adat_deser[i]; // Make sure all "1" bits are actually "1"
			end
			
			{timecode, midi, smux} = adat_deser[1:3]; // Collect ADAT user bits 0-2 (3 is reserved)
			
			for (int c = 0; c <= 7; c++) begin // Loop through all channels and collect data
				audio_bus[c] = { adat_deser[(6 + 30*c + 0) +: 4],
									  adat_deser[(6 + 30*c + 5) +: 4],
									  adat_deser[(6 + 30*c + 10) +: 4],
									  adat_deser[(6 + 30*c + 15) +: 4],
									  adat_deser[(6 + 30*c + 20) +: 4],
									  adat_deser[(6 + 30*c + 25) +: 4] };
			end
			
			data_ready = 1; // Set data ready strobe
		end
	endcase
end 

// State machine logic (combinatorial)
always_comb begin
	next = state;
	unique case (state)
		IDLE			: if (sync_counter > 60)		next = SYNC_WAIT; // Detect sync pattern
		SYNC_WAIT	: if (adat_synced != adat_s2)	next = SYNC; // Detect first transition
		SYNC			: 										next = BIT_WAIT;
		BIT_WAIT		: if (tic_counter == 3)			next = BIT_SAMPLE; // Samples center of bits
		BIT_SAMPLE	: if (current_bit == 245)	next = PARSE;
						  else 							next = BIT_WAIT;
		PARSE			: 									next = IDLE;
	endcase
end

endmodule 