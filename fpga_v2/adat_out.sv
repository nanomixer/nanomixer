// Copyright (c) 2013 Martin Segado
// All rights reserved (until we choose a license)

module adat_out (
   input logic clk, reset_n,                 // 256x8x oversample clock & asyncronous reset
   input logic start,
   input logic timecode, midi, smux,         // user bits per ADAT specification
   input logic signed [23:0] audio_in [0:7], // 8 channels @ 24 bits
   output logic bitstream_out                // ADAT bitstream output
);

logic [255:0] shift_reg, next_shift_reg; // contains entire data frame (unencoded, with sync bits)
logic [9:0] current_tic, next_tic; // loops around every 256 clocks (x8)
logic [255:0] input_as_packet;
logic next_bitstream_out;

always_comb begin
   input_as_packet[255:245] <= {1'b1, 10'b0};                      // sync pattern
   input_as_packet[244:240] <= {1'b1, timecode, midi, smux, 1'b0}; // user bits (4th = 0)
   for (int c = 0; c < 8; c++)
      input_as_packet[239-30*c -: 30] <= {1'b1, audio_in[c][23:20], // audio data
         1'b1, audio_in[c][19:16],
         1'b1, audio_in[c][15:12],
         1'b1, audio_in[c][11:8],
         1'b1, audio_in[c][ 7:4],
         1'b1, audio_in[c][ 3:0]};

   if (start) begin
      next_tic = 0;
      next_shift_reg = input_as_packet;
      next_bitstream_out = 1'b0;
   end else begin
      next_tic = current_tic + 1;
      if (current_tic[2:0] == 3'b0) begin
         next_shift_reg = {shift_reg[254:0], 1'b0}; // shift data to the left
         next_bitstream_out = bitstream_out ^ shift_reg[255]; // output NZRI-encoded data (MSB first)
      end else begin
         next_shift_reg = shift_reg;
         next_bitstream_out = bitstream_out;
      end
    end
end

always_ff @(posedge clk or negedge reset_n) begin
   if (~reset_n) begin
      shift_reg     <= '0;
      current_tic   <= '0;
      bitstream_out <= '0;
   end
   else begin
      shift_reg <= next_shift_reg;
      current_tic <= next_tic;
      bitstream_out <= next_bitstream_out;
   end
end

endmodule
