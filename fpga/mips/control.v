`include "mips.h"
module Control
  (
   input [31:0] INS_RD,
   
   // RD
   output wire 	SignExtend_RD,
   output wire [1:0] 	RegDestCtl_RD,
   
   // EX
   output wire 	Jump_RD,
   output wire [1:0] 	ShiftSrc_RD,
   output wire [1:0] 	Bsrc_RD,
   output wire [10:0] 	ALUop_RD,
   output wire [3:0] 	BranchOp_RD,
   output wire 	JumpSrc_RD,

   // MEM
   output reg MemRead_RD,
   output wire  MemSigned_RD,
   output wire [1:0] 	LoadMode_RD,
   output wire [1:0] 	DMC_RD,

   // WB
   output wire 	WBsrc_RD,
   output wire 	WBenable_RD
   );

   wire [5:0] op = INS_RD[`op];
   wire [5:0] func = INS_RD[`funct];
   wire [4:0] rt = INS_RD[`rt];

   // Interactive control logic
   always @(INS_RD) begin
      $get_value(INS_RD, MemRead_RD);
   end

   // BEGIN AUTOMATICALLY GENERATED CODE
`include "hw/control.vchunk"
   // END AUTOMATICALLY GENERATED CODE
   
endmodule // Control
