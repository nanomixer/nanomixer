`default_nettype none
module uDSP(
    input wire clk,
    input wire reset,
    input wire start,
    
    // Instruction memory port
    output wire[IAW-1:0] InstructionAddr,
    input wire[IWW-1:0] InstructionData,
    
    // Data memory port A
    output wire[DAW-1:0] AddrA,
    input wire[DWW-1:0] DataA,
    
    // Data memory port B
    output wire[DAW-1:0] AddrB,
    input wire[DWW-1:0] DataB,
    
    // Data memory port W
    output wire[DAW-1:0] AddrW,
    output wire[DWW-1:0] DataW,
    output wire WriteEn
    );
    
    // Current instruction ROM is 512 words => 9 bit address
    parameter IAW = 9;
    parameter IWW = 36;
    // Current data memories are 128 words + 3-bit segment => 10 bit addresses
    parameter DAW = 10;
    parameter DWW = 36;

    // Opcodes
    const bit[5:0] Nop=0, Mul=1, MulAcc=2, MulToW=3,
        AToHi=4, AToLo=5, HiToW=6, LoToW=7, Move=8;

    // Program Counter
    logic [IAW-1:0] PC = 0;
    assign InstructionAddr = PC;
    always @(posedge clk or posedge reset) begin
        if (reset || start) begin
            PC <= 0;
        end else PC <= PC + 1;
    end
    
    // Unpack address
    `define op 35:30
    `define rw 29:20
    `define ra 19:10
    `define rb  9:0
    
    // The fetch->read pipeline register is the data memory output register.
    
    //
    // READ
    //
    assign AddrA = InstructionData[`ra];
    assign AddrB = InstructionData[`rb];

    //
    // READ - EXECUTE pipeline registers
    //
    logic [35:0] Inst_EX;
    logic [35:0] DataA_EX, DataB_EX;
    always @(posedge clk or posedge rst) begin
        if (rst || start) begin
            Inst_EX <= 0;
            DataA_EX <= 0;
            DataB_EX <= 0;
        end else begin
            Inst_EX <= InstructionData;
            DataA_EX <= DataA;
            DataB_EX <= DataB;
        end
    end
    
    //
    // EXECUTE
    //
    wire [35:0] DataA_EXfwd, DataB_EXfwd;
    assign DataA_EXfwd = DataA_EX; // TODO: forward control
    assign DataB_EXfwd = DataB_EX;
    
    // The Multiplier!
    wire[35:0] mulOutHi, mulOutLo;
    assign {mulOutHi, mulOutLo} = signed'(DataA_EXfwd) * signed'(DataB_EXfwd);
    
    // The Accumulator!
    logic[35:0] HI, LO;
    always @(posedge clk or posedge rst or posedge start) begin
        if (rst || start) begin
            HI <= 0;
            LO <= 0;
        end else begin
            case (Inst_EX[`op])
            MulAcc: {HI, LO} <= {mulOutHi, mulOutLo} + {HI, LO};
            Mul: {HI, LO} <= {mulOutHi, mulOutLo};
            AToHi: HI <= DataA_EXfwd;
            AToLo: LO <= DataA_EXfwd;
            endcase
        end
    end

    // Compute writeback
    wire[35:0] wbData_EX;
    wire wren_EX;
    
    always_comb begin
        case (Inst_EX[`op])
        MulToW: begin
            wbData_EX = mulOutHi;
            wren_EX = 1;
        end
        HiToW: begin
            wbData_EX = HI;
            wren_EX = 1;
        end
        LoToW: begin
            wbData_EX = LO;
            wren_EX = 1;
        end
        AToW: begin
            wbData_EX = DataA_EX;
            wren_EX = 1;
        end
        default: wren_EX <= 0;
        endcase
    end
    
    //
    // EXECUTE - WRITEBACK pipeline registers
    //
    logic[35:0] Inst_WB;
    logic[35:0] wbData_WB;
    logic wren_WB;
    always @(posedge clk or posedge reset) begin
        if (reset || start) begin
            Inst_WB <= 0;
            wbData_WB <= 0;
            wren_WB <= 0;
        end else begin
            Inst_WB <= Inst_EX;
            wbData_WB <= wbData_EX;
            wren_WB <= wrEn_EX;
        end
    end

    //
    // WRITEBACK
    //
    assign AddrW = Inst_WB[rw];
    assign DataW = wbData_WB;
    assign writeEn = wren_WB;
    
endmodule