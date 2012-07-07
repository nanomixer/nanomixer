/**
 * BranchCompare: quick branch comparison logic
 * 
 * Inputs:
 *  rs: (forwarded) data in rs register
 *  rt: (forwarded) data in rt register
 *  BranchOp: control for the quick compare operations:
 *   BranchOp[3] = CompareTwo: compare rs to rt
 *   BranchOp[2] = InvertOut:  invert the output
 *   BranchOp[1] = Or0:        'or-equal-to' 0
 *   BranchOp[0] = Branch:     1 to actually branch
 * 
 * Output:
 *  branchTaken: 1 if the branch should be taken.
 */
`define CompareTwo 3
`define InvertOut  2
`define Or0        1
`define Branch     0

module BranchCompare
  (
   input [31:0] rs,
   input [31:0] rt,
   input [3:0] BranchOp,

   output branchTaken
   );

   // rs == 0?
   wire   zero;
   assign zero = (rs == 0);

   // rs < 0?
   wire   lessZero;
   assign lessZero = rs[31];

   // rs <= 0?
   wire   eqOrLess;
   assign eqOrLess = lessZero | (zero & BranchOp[`Or0]);
   
   // rs != rt
   wire   notEqualRt;
   assign notEqualRt = (rs != rt);
   
   // compare one or two?
   wire   doBranch;
   mux2to1 #(1) branchCompare
     (
      .a(eqOrLess),
      .b(notEqualRt),
      .ctrl(BranchOp[`CompareTwo]),
      .out(doBranch)
      );
   
   assign branchTaken = (doBranch ^ BranchOp[`InvertOut]) & BranchOp[`Branch];

endmodule // BranchCompare
