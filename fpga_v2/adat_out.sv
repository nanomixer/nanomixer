// Copyright (c) 2013 Martin Segado
// All rights reserved (until we choose a license)

module adat_out (
   input logic clk, reset_n,                 // 256x oversample clock & asyncronous reset
   input logic timecode, midi, smux,         // user bits per ADAT specification
   input logic signed [23:0] audio_in [0:7], // 8 channels @ 24 bits
   output logic bitstream_out                // ADAT bitstream output
);

logic [255:0] shift_reg; // contains entire data frame (unencoded, with sync bits)
logic [7:0] current_bit; // loops around every 256 clocks

always_ff @(posedge clk or negedge reset_n) begin
   if (~reset_n) begin
      shift_reg     <= '0;
      current_bit   <= '0;
      bitstream_out <= '0;
   end
   else begin
      if (current_bit == 0) begin // load new data into shift register
         shift_reg[255:245] <= {1'b1, 10'b0};                      // sync pattern
         shift_reg[244:240] <= {1'b1, timecode, midi, smux, 1'b0}; // user bits (4th = 0)
         for (int c = 0; c < 8; c++)
            shift_reg[239-30*c -: 30] <= {1'b1, audio_in[c][23:20], // audio data
                                          1'b1, audio_in[c][19:16],
                                          1'b1, audio_in[c][15:12],
                                          1'b1, audio_in[c][11:8],
                                          1'b1, audio_in[c][ 7:4],
                                          1'b1, audio_in[c][ 3:0]};
      end
   else shift_reg <= {shift_reg[254:0], 1'b0}; // shift data to the left

   current_bit   <= current_bit + 8'b1;             // increment bit counter
   bitstream_out <= bitstream_out ^ shift_reg[255]; // output NZRI-encoded data (MSB first)
   end
end

endmodule
