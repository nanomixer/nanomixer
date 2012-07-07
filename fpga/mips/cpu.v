`default_nettype none

module CPU
  (
   input wire clk,
   input wire reset,
   output wire [31:0] Iaddr, // instruction address
   input wire [31:0] Iin,
   output wire [31:0] Daddr, // data address
   input wire [31:0] Din,
   output wire [31:0] Dout,
   output wire [1:0] DMC,
   output wire Dread
   );

   // Other ALERTs:
   // * Make sure it's #(16), not #16.
   // * A missing 'endmodule' in one file can cause a strange syntax
   //   error on the first line of another file.

   ////
   //// Signals
   ////
   
   // PC
   wire [31:0] 	PC_IF, PC_RD, PC_EX, PC_MEM, PC_WB;
   wire [31:0] 	nextPC_IF;
   wire [31:0] 	PC4_IF, PC4_RD;
   assign 	PC_IF[1:0] = 0;
   assign 	PC_RD[1:0] = 0;
   assign 	PC_EX[1:0] = 0;
   assign 	PC_MEM[1:0] = 0;
   assign 	PC_WB[1:0] = 0;
   
   
   // Instruction
   wire [31:0] 	INS_IF, INS_RD, INS_EX, INS_MEM, INS_WB;
   
   // Control signals
   // IF
   wire 	BranchTaken_EX;
   wire [31:0] 	jumpTgt_EX;
   wire [31:0] 	branchOffset_EX;
   
   // RD
   wire 	SignExtend_RD;
   wire [1:0] 	RegDestCtl_RD;
   
   // EX
   wire 	Jump_RD, Jump_EX;
   wire [1:0] 	ForwardRs_RD, ForwardRs_EX;
   wire [1:0] 	ForwardRt_RD, ForwardRt_EX;
   wire [1:0] 	ShiftSrc_RD, ShiftSrc_EX;
   wire [1:0] 	Bsrc_RD, Bsrc_EX;
   wire [10:0] 	ALUop_RD, ALUop_EX;
   wire [3:0] 	BranchOp_RD, BranchOp_EX;
   wire 	JumpSrc_RD, JumpSrc_EX;

   // MEM
   wire 	MemRead_RD, MemRead_EX, MemRead_MEM;
   wire 	MemSigned_RD, MemSigned_EX, MemSigned_MEM;
   wire [1:0] 	LoadMode_RD, LoadMode_EX, LoadMode_MEM;
   wire [1:0] 	DMC_RD, DMC_EX, DMC_MEM;

   // WB
   wire 	WBsrc_RD, WBsrc_EX, WBsrc_MEM, WBsrc_WB;
   wire 	WBenable_RD, WBenable_EX, WBenable_MEM, WBenable_WB;
   wire [31:0] 	rd_WB;

   // Register file I/Os:
   wire 	rfWE;
   wire [4:0] 	rfRA, rfRB, rfRW;
   wire [31:0] 	rfA, rfB, rfW;
   
   // Signals to EX
   wire [4:0] 	sa_RD, sa_EX;
   wire [31:0] 	rs_EX;
   wire [31:0] 	rt_EX;
   wire [31:0] 	imm_RD, imm_EX;
   wire [4:0] 	regDest_RD, regDest_EX, regDest_MEM, regDest_WB;
   wire [31:0] 	tgt_RD, tgt_EX;

   // Signals to MEM
   wire [31:0] 	aluOut_EX, aluOut_MEM, aluOut_WB;
   wire [31:0] 	sWord_EX, sWord_MEM;

   // Signals to WB
   wire [31:0] 	memOut_MEM, memOut_WB;
   
   
   ////
   //// IF Stage
   ////
   
   // Register to hold the PC.
   negReg #(30) PCreg(clk, reset, nextPC_IF[31:2], PC_IF[31:2]);

   
   // IF stage control
   IF _if // avoid name collision with if keyword. ALERT.
     (
      .PC	(PC_IF[31:2]),
      .Jump(Jump_EX),
      .BranchTaken(BranchTaken_EX),
      .jumpTgt(jumpTgt_EX[31:2]),
      .branchOffset(branchOffset_EX[31:2]),
      .nextPC	(nextPC_IF[31:2]),
      .PC4(PC4_IF[31:2])
      );

   // Always request the address of the PC in IF.
   assign 	Iaddr = PC_IF;
   
   // The instruction from the IF stage is simply the data read from
   // instruction memory.
   assign 	INS_IF = Iin;
   

   ////
   //// IF-RD Pipeline Registers
   ////

   posReg #(30) PC_IFRD(clk, reset, PC_IF[31:2], PC_RD[31:2]);
   posReg INS_IFRD(clk, reset, INS_IF, INS_RD);

   // PC+4
   posReg #(30) PC4_IFRD(clk, reset, PC4_IF[31:2], PC4_RD[31:2]);
   

   ////
   //// RD Stage
   ////

   // Control unit
   Control control
     (
      .INS_RD(INS_RD),
      
      // RD
      .SignExtend_RD(SignExtend_RD),
      .RegDestCtl_RD(RegDestCtl_RD),
      
      // EX
      .Jump_RD(Jump_RD),
      .ShiftSrc_RD(ShiftSrc_RD),
      .Bsrc_RD(Bsrc_RD),
      .ALUop_RD(ALUop_RD),
      .BranchOp_RD(BranchOp_RD),
      .JumpSrc_RD(JumpSrc_RD),
      
      // MEM
      .MemRead_RD(MemRead_RD),
      .MemSigned_RD(MemSigned_RD),
      .LoadMode_RD(LoadMode_RD),
      .DMC_RD(DMC_RD),
      
      // WB
      .WBsrc_RD(WBsrc_RD),
      .WBenable_RD(WBenable_RD)
      );
   
   
   // Register file. Some testbench functionality relies on this name, so
   // don't change it.
   RF r
     (
      .clk(clk),
      .reset(reset),
      .RA(rfRA),
      .A(rfA),
      .RB(rfRB),
      .B(rfB),
      .RW(rfRW),
      .W(rfW),
      .WE(rfWE)
      );

   RD rd
     (
      .INS(INS_RD),
      .PC4(PC4_RD[31:2]),
      .SignExtend(SignExtend_RD),
      .RegDestCtl(RegDestCtl_RD),
      .rs(rfRA),
      .rt(rfRB),
      .regDest(regDest_RD),
      .sa(sa_RD),
      .tgt(tgt_RD[31:2]),
      .imm(imm_RD)
      );

   // Forwarding control
   ForwardControl fwdRs
     (
      .readReg(rfRA),
      .exReg(regDest_EX),
      .memReg(regDest_MEM),
      .WBenable_EX(WBenable_EX),
      .WBenable_MEM(WBenable_MEM),
      .FwdCtrl(ForwardRs_RD)
      );

   ForwardControl fwdRt
     (
      .readReg(rfRB),
      .exReg(regDest_EX),
      .memReg(regDest_MEM),
      .WBenable_EX(WBenable_EX),
      .WBenable_MEM(WBenable_MEM),
      .FwdCtrl(ForwardRt_RD)
      );

   ////
   //// RD-EX Pipeline Registers
   ////
   posReg #(30) PC_RDEX(clk, reset, PC_RD[31:2], PC_EX[31:2]);
   posReg INS_RDEX(clk, reset, INS_RD, INS_EX);
   posReg #(5) sa_RDEX(clk, reset, sa_RD, sa_EX);
   posReg rs_RDEX(clk, reset, rfA, rs_EX);
   posReg rt_RDEX(clk, reset, rfB, rt_EX);
   posReg imm_RDEX(clk, reset, imm_RD, imm_EX);
   posReg #(5) regDest_RDEX(clk, reset, regDest_RD, regDest_EX);
   posReg #(30) tgt_RDEX(clk, reset, tgt_RD[31:2], tgt_EX[31:2]);
   
   /// EX Control Registers
   // (to control IF)
   posedgeFF Jump_RDEX(clk, reset, Jump_RD, Jump_EX);
   // (to control EX)
   posReg #(2) ForwardRs_RDEX(clk, reset, ForwardRs_RD, ForwardRs_EX);
   posReg #(2) ForwardRt_RDEX(clk, reset, ForwardRt_RD, ForwardRt_EX);
   posReg #(2) ShiftSrc_RDEX(clk, reset, ShiftSrc_RD, ShiftSrc_EX);
   posReg #(2) Bsrc_RDEX(clk, reset, Bsrc_RD, Bsrc_EX);
   posReg #(11) ALUop_RDEX(clk, reset, ALUop_RD, ALUop_EX);
   posReg #(4) BranchOp_RDEX(clk, reset, BranchOp_RD, BranchOp_EX);
   posedgeFF JumpSrc_RDEX(clk, reset, JumpSrc_RD, JumpSrc_EX);

   /// MEM Control Registers
   posedgeFF MemRead_RDEX(clk, reset, MemRead_RD, MemRead_EX);
   posedgeFF MemSigned_RDEX(clk, reset, MemSigned_RD, MemSigned_EX);
   posReg #(2) LoadMode_RDEX(clk, reset, LoadMode_RD, LoadMode_EX);
   posReg #(2) DMC_RDEX(clk, reset, DMC_RD, DMC_EX);

   /// WB Control Registers
   posedgeFF WBsrc_RDEX(clk, reset, WBsrc_RD, WBsrc_EX);
   posedgeFF WBenable_RDEX(clk, reset, WBenable_RD, WBenable_EX);
   
   

   ////
   //// EX Stage
   ////

   EX ex
     (
      // Control inputs:
      .ForwardRs(ForwardRs_EX),
      .ForwardRt(ForwardRt_EX),
      .ShiftSrc(ShiftSrc_EX),
      .Bsrc(Bsrc_EX),
      .ALUop(ALUop_EX),
      .BranchOp(BranchOp_EX),
      .JumpSrc(JumpSrc_EX),
   
      // Pipeline inputs:
      .sa(sa_EX),
      .rs_pipeline(rs_EX),
      .rt_pipeline(rt_EX),
      .imm(imm_EX),
      .tgt(tgt_EX[31:2]),
      
      // Non-pipeline inputs:
      .pc8(PC4_RD[31:2]), // PC+8 for this ins is PC+4 for the one in RD.
      .memForward(aluOut_MEM),
      .wbForward(rd_WB),
      
      // Pipeline outputs:
      .aluOut(aluOut_EX),
      .sWord(sWord_EX),
      
      // Non-pipeline outputs (connections to IF):
      .branchTaken(BranchTaken_EX),
      .jumpTgt(jumpTgt_EX[31:2]),
      .branchOffset(branchOffset_EX[31:2])
      );

   ////
   //// EX-MEM Pipeline Registers
   ////

   posReg #(30) PC_EXMEM(clk, reset, PC_EX[31:2], PC_MEM[31:2]);
   posReg INS_EXMEM(clk, reset, INS_EX, INS_MEM);
   
   posReg aluOut_EXMEM(clk, reset, aluOut_EX, aluOut_MEM);
   posReg sWord_EXMEM(clk, reset, sWord_EX, sWord_MEM);
   posReg #(5) regDest_EXMEM(clk, reset, regDest_EX, regDest_MEM);

   /// MEM Control Registers
   posedgeFF MemRead_EXMEM(clk, reset, MemRead_EX, MemRead_MEM);
   posedgeFF MemSigned_EXMEM(clk, reset, MemSigned_EX, MemSigned_MEM);
   posReg #(2) LoadMode_EXMEM(clk, reset, LoadMode_EX, LoadMode_MEM);
   posReg #(2) DMC_EXMEM(clk, reset, DMC_EX, DMC_MEM);

   /// WB Control Registers
   posedgeFF WBsrc_EXMEM(clk, reset, WBsrc_EX, WBsrc_MEM);
   posedgeFF WBenable_EXMEM(clk, reset, WBenable_EX, WBenable_MEM);
   
   ////
   //// MEM Stage
   ////
   MEM mem
     (
      .MemSigned(MemSigned_MEM),
      .LoadMode(LoadMode_MEM),
      .dataAddr(aluOut_MEM),
      .dataIn(Din),
      .memOut(memOut_MEM)
      );

   // Connection to the memory.
   assign 	Daddr = aluOut_MEM;
   assign 	Dout = sWord_MEM;
   assign 	Dread = MemRead_MEM;
   assign 	DMC = DMC_MEM; // Data Memory Control.

   ////
   //// MEM-WB Pipeline Registers
   ////
   posReg #(30) PC_MEMWB(clk, reset, PC_MEM[31:2], PC_WB[31:2]);
   posReg INS_MEMWB(clk, reset, INS_MEM, INS_WB);
   
   posReg aluOut_MEMWB(clk, reset, aluOut_MEM, aluOut_WB);
   posReg memOut_MEMWB(clk, reset, memOut_MEM, memOut_WB);
   posReg #(5) regDest_MEMWB(clk, reset, regDest_MEM, regDest_WB);

   /// WB Control Registers
   posedgeFF WBsrc_MEMWB(clk, reset, WBsrc_MEM, WBsrc_WB);
   posedgeFF WBenable_MEMWB(clk, reset, WBenable_MEM, WBenable_WB);

   ////
   //// WB Stage
   ////

   // Connect the correct data to the register file input.
   mux2to1 wbMux
     (
      .a(aluOut_WB),
      .b(memOut_WB),
      .ctrl(WBsrc_WB),
      .out(rd_WB)
      );

   // Connect the data to the register file.
   assign 	rfW = rd_WB;
   // Select the register destination, as has been passed to us.
   assign 	rfRW = regDest_WB;
   // Connect the writeback enable to the register file.
   assign 	rfWE = WBenable_WB;
   

endmodule // cpu
