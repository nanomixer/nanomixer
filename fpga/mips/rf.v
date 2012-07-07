// Originally based on, but almost completely rewritten from, the
// ECE 475 register file.

module RF
  (
   input wire clk,
   input wire reset,
   input wire [4:0] RA,
   output wire [31:0] A,
   input wire [4:0] RB,
   output wire [31:0] B,
   input wire [4:0] RW,
   input wire [31:0] W,
   input wire WE
   );
   
   // A 32 x 32 bit memory array
   reg [31:0] r [0:31];
   
   // Writes occur on clock negedge.
   always @(negedge clk) begin
      // Register r0 is read-only
      if (WE && RW != 5'b0) begin
	 // Write W data to cell addressed by RW.
	 r[RW] <= W;
      end
   end
   
   // Reads are combinational.
   assign A = r[RA];
   assign B = r[RB];
   
endmodule
