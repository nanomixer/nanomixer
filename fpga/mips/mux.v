module mux2to1(a, b, ctrl, out);
   parameter 	  w = 32;
   
   input wire [w-1:0] a;
   input wire [w-1:0] b;
   input wire 	 ctrl;
   output wire [w-1:0] out;

   assign out = ctrl ? b : a;

endmodule // mux2to1

module mux3to1(a, b, c, ctrl, out);

   parameter 	  w = 32;
   
   input wire [w-1:0] a;
   input wire [w-1:0] b;
   input wire [w-1:0] c;
   input wire [1:0]	 ctrl;
   output reg [w-1:0] out;
   
   // FIXME: behavioral.
   always @(*) begin
      if (ctrl == 0)
	out = a;
      else if (ctrl == 1)
	out = b;
      else
	out = c;
   end

endmodule // mux3to1

module mux4to1(a, b, c, d, ctrl, out);

   parameter 	  w = 32;
   
   input wire [w-1:0] a;
   input wire [w-1:0] b;
   input wire [w-1:0] c;
   input wire [w-1:0] d;
   input wire [1:0]	 ctrl;
   output reg [w-1:0] out;
   
   // FIXME: behavioral.
   always @(*) begin
      if (ctrl == 0)
	out = a;
      else if (ctrl == 1)
	out = b;
      else if (ctrl == 2)
	out = c;
      else
	out = d;
      
   end

endmodule // mux3to1
