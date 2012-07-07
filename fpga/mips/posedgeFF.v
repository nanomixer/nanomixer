/**************************************************************************
 *
 *  EE/CS 314
 *  Cornell University, Ithaca, NY 14853
 *
 **************************************************************************
 */

// positive-edge flip-flop with ASYNCHRONOUS active-high reset
module posedgeFF(clk,reset,d,q);

   input wire clk;
   input wire reset;
   input wire d;
   output reg q;
 
  always @(posedge clk or posedge reset)
    begin    
     	if(reset == 1) q <= 0;
	else q <= d;
     end

`ifdef FUNCTIONAL
   integer last_change = -1;
   always @(clk or reset) begin
      if ($time == last_change) begin
	 $display("Warning: potential glitch in posedgeFF at real time %d", $time);
      end
      last_change = $time;
      
   end
`endif
   
endmodule // posedgeFF
