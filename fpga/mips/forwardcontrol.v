/** Forward control unit: sets inputs to forwarding mux
 * Inputs:
 *  readReg: the register that the current instruction reads
 *  exReg: the register that the previous instruction writes (currently in EX)
 *  memReg: the register that the instruction before previous writes (currently in MEM)
 *  wbEn_EX: writeback enable of previous instruction (in EX)
 *  wbEn_MEM: writeback enable of instruction before previous (in MEM)
 * Outputs:
 *  FwdCtrl: control for the forward mux in the EX stage
 *   bit 1: 0 if forwarding, 1 if not
 *   bit 0: 1 if forward will be from MEM stage, 0 if from WB
 * So:
 *  00: forward from WB
 *  01: forward from MEM
 *  1-: use input from RD stage (no forwarding)
 */

module ForwardControl
  (
   input wire [4:0] readReg,
   input wire [4:0] exReg,
   input wire [4:0] memReg,
   input wire WBenable_EX,
   input wire WBenable_MEM,

   output wire [1:0] FwdCtrl
   );
   
   // forward from ex = (readReg == exReg) && (exReg != 0) && (wbEn_EX == 1)
   wire   fwdFromEx = (readReg == exReg) && (exReg != 0) && (WBenable_EX == 1);
   
   // same logic, s/ex/mem/g
   wire   fwdFromMem = (readReg == memReg) && (memReg != 0) && (WBenable_MEM == 1);

   // ctrl[1]=0 iff we could forward from either stage
   assign FwdCtrl[1] = ~(fwdFromEx | fwdFromMem);
   
   // If the instructions in both EX and MEM write to reg, favor the instruction
   // in EX, since it is later in program order. By design, ctrl[1]==1 indicates
   // that we forward from the instruction currently in EX, so ctrl[0] is just
   // whether we forward from EX. If neither forwards, this will be 0, but it
   // doesn't matter because the 3-input MUX will ignore the LSB if the MSB is 1.
   assign FwdCtrl[0] = fwdFromEx;

endmodule // ForwardControl
