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
    input wire reset,
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

    // Program Counter
    logic [IAW-1:0] PC = 0;
    assign addrI = PC;
    always @(posedge clk or posedge reset) begin
        if (reset) PC <= 0;
        else begin
            if (start)
                PC <= 0;
            else 
                PC <= PC + 1;
        end
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
    assign addrA = dataI[`ra];
    assign addrB = dataI[`rb];

    //
    // READ - EXECUTE pipeline registers
    //
    logic [35:0] Inst_EX;
    logic [35:0] dataA_EX, dataB_EX;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            Inst_EX <= 0;
            dataA_EX <= 0;
            dataB_EX <= 0;
        end else begin
            if (start) begin
                Inst_EX <= 0;
                dataA_EX <= 0;
                dataB_EX <= 0;
            end else begin
                Inst_EX <= dataI;
                dataA_EX <= dataA;
                dataB_EX <= dataB;
            end
        end
    end
    
    //
    // EXECUTE
    //
    wire [35:0] dataA_EXfwd, dataB_EXfwd;
    assign dataA_EXfwd = (wren_EX && addrA == Inst_EX[`rw]) ? wbData_WB : dataA_EX;
    assign dataB_EXfwd = (wren_EX && addrB == Inst_EX[`rw]) ? wbData_WB : dataB_EX;
    
    // The Multiplier!
    wire[35:0] mulOutHi, mulOutLo;
    assign {mulOutHi, mulOutLo} = signed'(dataA_EXfwd) * signed'(dataB_EXfwd);
    
    // The Accumulator!
    logic[35:0] HI, LO;
    always @(posedge clk or posedge reset or posedge start) begin
        if (reset || start) begin
            HI <= 0;
            LO <= 0;
        end else begin
            case (Inst_EX[`op])
            MulAcc: {HI, LO} <= {mulOutHi, mulOutLo} + {HI, LO};
            Mul: {HI, LO} <= {mulOutHi, mulOutLo};
            AToHi: HI <= dataA_EXfwd;
            AToLo: LO <= dataA_EXfwd;
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
            wbData_EX = dataA_EX;
            wren_EX = 1;
        end
        default: begin 
            wbData_EX = 'x;
            wren_EX <= 0;
        end
        endcase
    end
    
    //
    // EXECUTE - WRITEBACK pipeline registers
    //
    logic[35:0] Inst_WB;
    logic[35:0] wbData_WB;
    logic wren_WB;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            Inst_WB <= 0;
            wbData_WB <= 0;
            wren_WB <= 0;
        end else begin
            if (start) begin
                Inst_WB <= 0;
                wbData_WB <= 0;
                wren_WB <= 0;
            end else begin
                Inst_WB <= Inst_EX;
                wbData_WB <= wbData_EX;
                wren_WB <= wren_EX;
            end
        end
    end

    //
    // WRITEBACK
    //
    assign addrW = Inst_WB[`rw];
    assign dataW = wbData_WB;
    assign writeEn = wren_WB;
    
endmodule