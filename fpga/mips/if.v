// Instruction fetch module.
module IF
  (
   input wire [29:0] PC,
   input wire Jump,
   input wire BranchTaken,
   input wire [29:0] jumpTgt,
   input wire [29:0] branchOffset,
   output wire [29:0] nextPC,
   output wire [29:0] PC4
   );

   //// Branch adder.
   // FIXME: using Verilog's adder.
   wire [29:0] branchTgt;
   assign      branchTgt = PC + branchOffset;

   //// PC+4 adder. (adds 1 because PC is stored >>2.)
   // FIXME: using Verilog's adder.
   assign      PC4 = PC + 1;

   //// Compute the relative address (either incremented by one address or
   //// branched by branchOffset).
   wire [29:0] relAddr;
   
   // Decide to increment or branch.
   mux2to1 #(30) incOrBranch(PC4, branchTgt, BranchTaken, relAddr);

   //// Compute the next PC as either a jump or a relative address.
   mux2to1 #(30) nextPCmux(relAddr, jumpTgt, Jump, nextPC);
   
endmodule // IF
