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
                PC <= PC + 2'b1;
        end
    end
    
    // Unpack address
    `define op 35:30
    `define rw 29:20
    `define ra 19:10
    `define rb  9:0
    
    //
    // FETCH - READ pipeline registers
    //
    
    // The fetch->read pipeline register is the data memory output register.
    logic [35:0] Inst_RD;
    always @(posedge clk or posedge reset) begin
        if (reset) Inst_RD <= 0;
        else begin
            if (start) Inst_RD <= 0;
            else Inst_RD <= dataI;
        end
    end
    
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
                Inst_EX <= Inst_RD;
                dataA_EX <= dataA;
                dataB_EX <= dataB;
            end
        end
    end

    // advance declarations for forwarding data
    logic[35:0] Inst_WB;
    logic[35:0] wbData_WB;
    logic wren_WB;

    
    //
    // EXECUTE
    //
    wire [5:0] opcode_EX;
    wire [35:0] dataA_EXfwd, dataB_EXfwd;
    assign opcode_EX = Inst_EX[`op];
    assign dataA_EXfwd = (wren_WB && addrA == Inst_WB[`rw]) ? wbData_WB : dataA_EX;
    assign dataB_EXfwd = (wren_WB && addrB == Inst_WB[`rw]) ? wbData_WB : dataB_EX;
    
    // The Multiplier!
    wire signed [35:0] mulOutHi;
    wire[35:0] mulOutLo;
    assign {mulOutHi, mulOutLo} = signed'(dataA_EXfwd) * signed'(dataB_EXfwd);
    
    // The Accumulator!
    logic signed [35:0] HI;
    logic[35:0] LO;
    always @(posedge clk or posedge reset) begin
        if (reset) {HI, LO} <= 0;
        else begin
            if (start) {HI, LO} <= 0;
            else begin
                case (opcode_EX)
                MulAcc: {HI, LO} <= {mulOutHi, mulOutLo} + signed'({HI, LO});
                Mul: {HI, LO} <= {mulOutHi, mulOutLo};
                AToHi: {HI, LO} <= {dataA_EXfwd, LO};
                AToLo: {HI, LO} <= {HI, dataA_EXfwd};
                default: begin
                    HI <= HI;
                    LO <= LO;
                end
                endcase
            end
        end
    end

    // Compute writeback
    logic[35:0] wbData_EX;
    logic wren_EX;
    
    always_comb begin
        case (opcode_EX)
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