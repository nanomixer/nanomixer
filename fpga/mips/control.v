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

// UGLY starts here
wire _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, _func_5_, _func_4_, _func_3_, _func_2_, _func_1_, _func_0_, _rt_4_, _rt_3_, _rt_2_, _rt_1_, _rt_0_;
wire [36:0] p;
not n_0(_op_5_, op[5]);
not n_1(_op_4_, op[4]);
not n_2(_op_3_, op[3]);
not n_3(_op_2_, op[2]);
not n_4(_op_1_, op[1]);
not n_5(_op_0_, op[0]);
not n_6(_func_5_, func[5]);
not n_7(_func_4_, func[4]);
not n_8(_func_3_, func[3]);
not n_9(_func_2_, func[2]);
not n_10(_func_1_, func[1]);
not n_11(_func_0_, func[0]);
not n_12(_rt_4_, rt[4]);
not n_13(_rt_3_, rt[3]);
not n_14(_rt_2_, rt[2]);
not n_15(_rt_1_, rt[1]);
not n_16(_rt_0_, rt[0]);

nand p0(p[0], _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, _func_5_, _func_4_, func[3], _func_2_, _func_1_);
nand p1(p[1], _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, func[5], _func_4_, func[3], _func_2_, func[1], func[0]);
nand p2(p[2], _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, func[5], _func_4_, func[3], _func_2_, func[1], _func_0_);
nand p3(p[3], _op_5_, _op_4_, _op_3_, _op_0_, func[5], _func_4_, _func_3_, func[2], _func_1_, _func_0_);
nand p4(p[4], _op_5_, _op_4_, _op_3_, _op_0_, func[5], _func_4_, _func_3_, func[2], func[1], _func_0_);
nand p5(p[5], _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, func[5], _func_4_, _func_3_, func[2], _func_1_, func[0]);
nand p6(p[6], _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, _func_5_, _func_4_, func[3], _func_2_, _func_1_, func[0]);
nand p7(p[7], _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, func[5], _func_4_, _func_3_, func[2], func[1], func[0]);
nand p8(p[8], _op_5_, _op_4_, _op_3_, _op_2_, op[0], rt[4], _rt_3_, _rt_2_, _rt_1_);
nand p9(p[9], _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, _func_5_, _func_4_, _func_3_, func[1], func[0]);
nand p10(p[10], _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, _func_5_, _func_4_, _func_3_, func[1], _func_0_);
nand p11(p[11], _op_4_, _op_2_, op[0], _rt_3_, _rt_2_, _rt_1_, rt[0]);
nand p12(p[12], _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, _func_5_, _func_4_, _func_3_, _func_1_, _func_0_);
nand p13(p[13], _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, func[5], _func_4_, _func_3_, _func_2_, func[1]);
nand p14(p[14], _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, func[5], _func_4_, _func_3_, _func_2_, _func_1_);
nand p15(p[15], _op_5_, _op_4_, _op_3_, _op_1_, op[0], _rt_3_, _rt_2_, _rt_1_);
nand p16(p[16], _op_5_, _op_4_, _op_3_, _op_2_, _op_1_, _op_0_, _func_4_, _func_3_, func[2], _func_0_);
nand p17(p[17], _op_5_, _op_4_, _op_0_, _func_4_, _func_3_, func[2], func[1]);
nand p18(p[18], op[5], _op_4_, op[3], _op_2_, op[1], op[0]);
nand p19(p[19], op[5], _op_4_, op[3], _op_2_, op[0]);
nand p20(p[20], _op_5_, _op_4_, op[3], op[2], op[1], _op_0_);
nand p21(p[21], op[5], _op_4_, op[3], _op_2_, _op_1_, _op_0_);
nand p22(p[22], _op_5_, _op_4_, op[3], op[2], _op_1_, op[0]);
nand p23(p[23], _op_4_, _op_3_, op[2], _op_1_, _op_0_);
nand p24(p[24], op[5], _op_4_, _op_2_, _op_1_, _op_0_);
nand p25(p[25], _op_5_, _op_4_, op[3], op[2], op[1], op[0]);
nand p26(p[26], _op_5_, _op_4_, op[3], op[2], _op_1_, _op_0_);
nand p27(p[27], _op_4_, _op_3_, _op_2_, op[1], op[0]);
nand p28(p[28], _op_5_, _op_4_, op[3], _op_2_, op[1], op[0]);
nand p29(p[29], _op_5_, _op_4_, op[1], op[0]);
nand p30(p[30], _op_5_, _op_4_, op[2], _op_1_);
nand p31(p[31], _op_5_, _op_4_, op[3], _op_2_, op[1], _op_0_);
nand p32(p[32], _op_5_, _op_4_, _op_3_, _op_2_, op[1]);
nand p33(p[33], _op_5_, _op_4_, _op_3_, op[2]);
nand p34(p[34], op[5], _op_4_, _op_2_, op[0]);
nand p35(p[35], _op_5_, _op_4_, op[3], _op_2_, _op_1_);
nand p36(p[36], op[5], _op_4_, _op_3_, _op_1_);

nand s0(SignExtend_RD, p[15], p[21], p[25], p[28], p[31], p[33], p[34], p[35], p[36]);
nand s1(RegDestCtl_RD[1], p[8], p[32]);
nand s2(RegDestCtl_RD[0], p[1], p[2], p[5], p[6], p[7], p[9], p[10], p[12], p[13], p[14], p[16]);
nand s3(Jump_RD, p[0], p[32]);
not s4(JumpSrc_RD, p[0]);
nand s5(Bsrc_RD[1], p[6], p[8], p[32]);
nand s6(Bsrc_RD[0], p[20], p[21], p[22], p[25], p[26], p[28], p[31], p[34], p[35], p[36]);
nand s7(ALUop_RD[0], p[14], p[21], p[34], p[35], p[36]);
nand s8(ALUop_RD[1], p[3], p[26]);
nand s9(ALUop_RD[2], p[4], p[20]);
nand s10(ALUop_RD[3], p[5], p[22]);
not s11(ALUop_RD[4], p[7]);
not s12(ALUop_RD[5], p[13]);
nand s13(ALUop_RD[6], p[1], p[28]);
nand s14(ALUop_RD[7], p[2], p[31]);
not s15(ALUop_RD[8], p[9]);
not s16(ALUop_RD[9], p[10]);
nand s17(ALUop_RD[10], p[6], p[8], p[12], p[25], p[32]);
nand s18(ShiftSrc_RD[1], p[6], p[8], p[25], p[32]);
nand s19(ShiftSrc_RD[0], p[16], p[17], p[25]);
nand s20(BranchOp_RD[0], p[15], p[33]);
not s21(BranchOp_RD[3], p[30]);
nand s22(BranchOp_RD[2], p[11], p[23], p[29]);
not s23(BranchOp_RD[1], p[33]);
not s24(DMC_RD[1], p[19]);
nand s25(DMC_RD[0], p[18], p[21]);
nand s26(MemSigned_RD, p[24], p[34]);
nand s27(LoadMode_RD[1], p[23], p[24]);
not s28(LoadMode_RD[0], p[36]);
nand s29(WBenable_RD, p[1], p[2], p[5], p[6], p[7], p[8], p[9], p[10], p[12], p[13], p[14], p[16], p[20], p[22], p[25], p[26], p[27], p[28], p[31], p[35], p[36]);
nand s30(WBsrc_RD, p[34], p[36]);
// UGLY ends here

endmodule // Control
