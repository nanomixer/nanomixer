/**
 * EX pipeline stage
 * 
 * Inputs:
 *  Control inputs:
 *  ForwardRs: forwarded source for rs value (0=WB, 1=MEM, 2=not forwarded)
 *  ForwardRt: forwarded source for rt value (0=WB, 1=MEM, 2=not forwarded)
 *  ShiftSrc: shift amount source (0=sa, 1=rs[4:0], 2=0, 3=16)
 *  Bsrc: source for ALU b input (0=rt, 1=imm, 2=link address)
 *  ALUop: operation for ALU (see alu.v)
 *  BranchOp: quick compare branch operation
 *  JumpSrc: source of jump target (0=tgt, 1=rs)
 *  
 *  Pipeline inputs:
 *  sa: shift amount
 *  rs_pipeline: rs value from the register file
 *  rt_pipeline: rt value from the register file
 *  imm: extended immediate
 *  tgt: jump target
 */
module EX
  (
   // Control inputs:
   input wire [1:0] ForwardRs,
   input wire [1:0] ForwardRt,
   input wire [1:0] ShiftSrc,
   input wire [1:0] Bsrc,
   input wire [10:0] ALUop,
   input wire [3:0] BranchOp,
   input wire JumpSrc,
   
   // Pipeline inputs:
   input wire [4:0] sa,
   input wire [31:0] rs_pipeline,
   input wire [31:0] rt_pipeline,
   input wire [31:0] imm,
   input wire [29:0] tgt,

   // Non-pipeline inputs:
   input wire [29:0] pc8,
   input wire [31:0] memForward,
   input wire [31:0] wbForward,

   // Pipeline outputs:
   output wire [31:0] aluOut,
   output wire [31:0] sWord,
   
   // Non-pipeline outputs:
   output wire branchTaken,
   output wire [29:0] jumpTgt,
   output wire [29:0] branchOffset
   );

   // Forward rs and rt.
   wire [31:0] 	 rs_fwd, rt_fwd;
   mux3to1 rsFwdMux
     (
      .a(wbForward),
      .b(memForward),
      .c(rs_pipeline),
      .ctrl(ForwardRs),
      .out(rs_fwd)
      );

   mux3to1 rtFwdMux
     (
      .a(wbForward),
      .b(memForward),
      .c(rt_pipeline),
      .ctrl(ForwardRt),
      .out(rt_fwd)
      );

   
   // Mux for shift amount.
   wire [4:0] 	 shiftAmt;
   mux4to1 #(5) shiftAmtMux
     (
      .a(sa),
      .b(rs_fwd[4:0]),
      .c(5'd0),   // used to pass through
      .d(5'd16),  // used for lui
      .ctrl(ShiftSrc),
      .out(shiftAmt)
      );
   
   // Link address computation.
   wire [31:0] 	 linkAddr;
   assign 	 linkAddr = pc8 << 2;

   // Mux for ALU B input (rt, immediate, or link address).
   wire [31:0] 	 aluB;
   mux3to1 aluBmux
     (
      .a(rt_fwd),
      .b(imm),
      .c(linkAddr),
      .ctrl(Bsrc),
      .out(aluB)
      );

   // ALU
   ALU alu
     (
      .a(rs_fwd),
      .b(aluB),
      .op(ALUop),
      .sa(shiftAmt),
      .out(aluOut)
      );

   // The word to store in memory is the forwarded rt.
   assign 	 sWord = rt_fwd;

   // Branch comparison logic
   BranchCompare branchCompare
     (
      .rs(rs_fwd),
      .rt(rt_fwd),
      .BranchOp(BranchOp),
      .branchTaken(branchTaken)
      );
   
   // Mux for jump target (tgt or rs).
   mux2to1 #(30) jumpTgtMux
     (
      .a(tgt),
      .b(rs_fwd[31:2]),
      .ctrl(JumpSrc),
      .out(jumpTgt)
      );

   // Connect branch offset = immediate.
   assign 	 branchOffset = imm[29:0];
   
endmodule // EX
