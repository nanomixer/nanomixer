`include "mips.h"

/**
 * RD: Read and Decode datapath stage (control is separate).
 * 
 * Inputs:
 *  INS: The instruction currently in the RD stage.
 *  PC4: PC+4 of the instruction currently in RD.
 *  SignExtend: 1 iff the immediate field should be sign-extended
 *   (otherwise it is zero-extended).
 *  RegDest: Control signal designating where to get the destination register:
 *   0 => rt field of INS
 *   1 => rd field of INS
 *   2 => r31 (5'b11111)
 * 
 * Outputs:
 *  (connections to the register file)
 *  rs: source register 1
 *  rt: source register 2
 *  regDest: destination register
 *
 *  (outputs to EX stage)
 *  sa: shift amount
 *  tgt: jump target
 *  imm: extended immediate
 */
module RD
  (
   input wire [31:0] INS,
   input wire [29:0] PC4,
   input wire SignExtend,
   input wire [1:0] RegDestCtl,
   output wire [4:0] rs,
   output wire [4:0] rt,
   output wire [4:0] regDest,
   output wire [4:0] sa,
   output wire [29:0] tgt,
   output wire [31:0] imm
   );

   //// Decode the instruction.
   assign 	rs = INS[`rs];
   assign 	rt = INS[`rt];
   assign 	sa = INS[`sa];

   // Jump target is the top 4 bits of PC+4 on top of the given jump target.
   assign 	tgt = {PC4[29:26], INS[`tgt]};
   
   //// Sign- or zero-extend the immediate.
   assign 	imm[15:0] = INS[`imm];
   wire 	highBits = imm[15] & SignExtend;
   assign 	imm[31:16] = {16{highBits}};
	
   mux3to1 #(5) regDestMux
     (
      .a(rt),
      .b(INS[`rd]),
      .c(`r31),
      .ctrl(RegDestCtl),
      .out(regDest)
      );
   
endmodule // RD
