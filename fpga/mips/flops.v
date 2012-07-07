/**
 * a positive-edge register (an array of posedgeFFs)
 * 
 * Paramters:
 *  w: width of the register
 * Inputs:
 *  clk: clock
 *  rst: asynchronous reset
 *  in: D
 * Output:
 *  out: Q
 * 
 * Example instantiation:
 *  posReg #(32) reg(clk, rst, in, out);
 */
module posReg(clk, rst, in, out);
   // not declaring ports until after parameters... is this necessary?
   parameter w = 32;

   input     wire clk;
   input     wire rst;
   input     wire [w-1:0] in;
   output    wire [w-1:0] out;

   
   genvar i;
   generate for(i=0; i<w; i=i+1) begin:posreg
      posedgeFF f(clk, rst, in[i], out[i]);
   end
   endgenerate

endmodule // posReg


/**
 * a negative-edge register (an array of negedgeFFs)
 * 
 * Paramters:
 *  w: width of the register
 * Inputs:
 *  clk: clock
 *  rst: asynchronous reset
 *  in: D
 * Output:
 *  out: Q
 * 
 * Example instantiation:
 *  negReg #(32) reg(clk, rst, in, out);
 */
module negReg(clk, rst, in, out);
   // FIXME: not declaring ports until after parameters... is this necessary?
   parameter w = 32;

   input     wire clk;
   input     wire rst;
   input     wire [w-1:0] in;
   output    wire [w-1:0] out;

   genvar i;
   generate for(i=0; i<w; i=i+1) begin:negreg
      negedgeFF f(clk, rst, in[i], out[i]);
   end
   endgenerate

endmodule // negReg
