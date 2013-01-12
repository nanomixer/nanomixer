`default_nettype none
module uDSP #(
    // Current instruction ROM is 512 words => 9 bit address
    parameter IAW = 9,
    parameter IWW = 36,
    // Current data memories are 128 words + 3-bit segment => 10 bit addresses
    parameter DAW = 10,
    parameter DWW = 36)
(
    input wire clk,
    input wire reset_n,
    input wire start,
    
    // Instruction memory port
    output wire[IAW-1:0] addrI,
    input wire[IWW-1:0] dataI,
    
    // Data memory port A
    output wire[DAW-1:0] addrA,
    input wire[DWW-1:0] dataA,
    
    // Data memory port B
    output wire[DAW-1:0] addrB,
    input wire[DWW-1:0] dataB,
    
    // Data memory port W
    output wire[DAW-1:0] addrW,
    output wire[DWW-1:0] dataW,
    output wire writeEn
    );

    // Opcodes
    const bit[5:0] Nop=0, Mul=1, MulAcc=2, MulToW=3,
        AToHi=4, AToLo=5, HiToW=6, LoToW=7, AToW=8;

    wire rst; // global async reset.
    assign rst = ~reset_n | start;
    
    // Program Counter
    wire [IAW-1:0] PC_IF;
    posedgeFF #(IAW) pc (clk, rst, PC_IF + 1'b1, PC_IF);
    assign addrI = PC_IF;
    
    // Unpack address
    `define op 35:30
    `define rw 29:20
    `define ra 19:10
    `define rb  9:0
    
    //
    // FETCH - READ pipeline registers
    //
    
    // The fetch->read pipeline register is the data memory output register.
    wire[IAW-1:0] PC_RD;
    wire [35:0] Inst_RD;
    posedgeFF #(IAW) pc_ifrd(clk, rst, PC_IF, PC_RD);
    posedgeFF #(36) inst_ifrd(clk, rst, dataI, Inst_RD);
    wire[5:0] opcode_RD;
    assign opcode_RD = Inst_RD[`op];
    
    //
    // READ
    //
    assign addrA = dataI[`ra];
    assign addrB = dataI[`rb];
    
    //
    // READ - EXECUTE pipeline registers
    //
    wire [IAW-1:0] PC_EX;
    wire [35:0] Inst_EX;
    wire [35:0] dataA_EX, dataB_EX;
    posedgeFF #(IAW) pc_rdex(clk, rst, PC_RD, PC_EX);
    posedgeFF #(36) inst_rdex(clk, rst, Inst_RD, Inst_EX);
    posedgeFF #(36) dataA_rdex(clk, rst, dataA, dataA_EX);
    posedgeFF #(36) dataB_rdex(clk, rst, dataB, dataB_EX);

    // advance declarations for forwarding data
    wire[35:0] Inst_WB;
    wire[35:0] wbData_WB;
    wire wren_WB;

    
    //
    // EXECUTE
    //
    wire [5:0] opcode_EX;
    wire [35:0] dataA_EXfwd, dataB_EXfwd;
    assign opcode_EX = Inst_EX[`op];
    assign dataA_EXfwd = (wren_WB && Inst_EX[`ra] == Inst_WB[`rw]) ? wbData_WB : dataA_EX;
    assign dataB_EXfwd = (wren_WB && Inst_EX[`rb] == Inst_WB[`rw]) ? wbData_WB : dataB_EX;
    
    // The Multiplier!
    wire signed [35:0] mulOutHi;
    wire[35:0] mulOutLo;
    assign {mulOutHi, mulOutLo} = signed'(dataA_EXfwd) * signed'(dataB_EXfwd);
    
    // The Accumulator!
    logic signed [35:0] HI_next;
    logic[35:0] LO_next;
    wire signed [35:0] HI;
    wire [35:0] LO;
    posedgeFF #(36) hi_ex(clk, rst, HI_next, HI);
    posedgeFF #(36) lo_ex(clk, rst, LO_next, LO);
    always_comb begin
        case (opcode_EX)
        MulAcc: {HI_next, LO_next} <= {mulOutHi, mulOutLo} + signed'({HI, LO});
        Mul: {HI_next, LO_next} <= {mulOutHi, mulOutLo};
        // NOTE HACK GOTCHA: both AToHi and AToLo actually zero the accumulator.
        // The commented version would do what the instruction name suggests.
        AToHi: {HI_next, LO_next} <= 0;//{HI_next, LO_next} <= {dataA_EXfwd, LO};
        AToLo: {HI_next, LO_next} <= 0;//{HI_next, LO_next} <= {HI, dataA_EXfwd};
        default: begin
            HI_next <= HI;
            LO_next <= LO;
        end
        endcase
    end

    // Compute writeback
    logic[35:0] wbData_EX;
    logic wren_EX;
    
    // Saturator: we multiplied a Q5.30 by a Q1.34 coefficient,
    // giving a Q7.64 multiplicand. We want a Q5.30 output.
    wire[35:0] accAsWord, mulAsWord;
    saturate #(.IN_WIDTH(72), .HEADROOM(2), .OUT_WIDTH(36)) accSaturator(
        .in({HI, LO}), .out(accAsWord));
    saturate #(.IN_WIDTH(72), .HEADROOM(2), .OUT_WIDTH(36)) mulSaturator(
        .in({mulOutHi, mulOutLo}), .out(mulAsWord));
    always_comb begin
        case (opcode_EX)
        MulToW: begin
            wbData_EX = mulAsWord;
            wren_EX = 1;
        end
        HiToW: begin
            wbData_EX = accAsWord;
            wren_EX = 1;
        end
        LoToW: begin
            wbData_EX = LO;
            wren_EX = 1;
        end
        AToW: begin
            wbData_EX = dataA_EX;
            wren_EX = 1;
        end
        default: begin 
            wbData_EX = 'x;
            wren_EX = 0;
        end
        endcase
    end
    
    //
    // EXECUTE - WRITEBACK pipeline registers
    //
    wire [IAW-1:0] PC_WB;
    posedgeFF #(IAW) pc_exwb(clk, rst, PC_EX, PC_WB);
    posedgeFF #(36) inst_exwb(clk, rst, Inst_EX, Inst_WB);
    posedgeFF #(36) wbdata_exwb(clk, rst, wbData_EX, wbData_WB);
    posedgeFF #(1) wren_exwb(clk, rst, wren_EX, wren_WB);
    
    //
    // WRITEBACK
    //
    wire[5:0] opcode_WB;
    assign opcode_WB = Inst_WB[`op];
    assign addrW = Inst_WB[`rw];
    assign dataW = wbData_WB;
    assign writeEn = wren_WB;
    
endmodule