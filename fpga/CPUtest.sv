module CPUtest #(
    parameter real CLK_FREQ = 100.0e6);

localparam time CLK_PERIOD = (1.0e9/CLK_FREQ)*1ns;

logic clk;

initial clk=0;
always #(CLK_PERIOD/2) clk = ~clk;

logic reset = 0;
logic start;
logic[36-1:0] inputs[8];
wire[36-1:0] outputs[8];

DSPCore u1 (.clk, .reset, .start, .inputs, .outputs);

`define op 35:30
`define rw 29:20
`define ra 19:10
`define rb  9:0

int i;
initial begin
    for (i=0; i<8; i++) inputs[i] = (i+1)<<10;
    
    $display("Asserting reset");
    reset = 1;
    @(posedge clk);
    @(posedge clk);
    reset = 0;

    // Start of sample
    $display("Asserting start of sample.");
    @(posedge clk) start <= 1;
    @(posedge clk) start <= 0;

    for (i=0; i<25; i++) begin
        @(posedge clk);
        $display("%2d: %x | %x %x %d | %x %x %d | %x %x %d",
            i, u1.addrI,
            u1.dsp.PC_RD, u1.dsp.Inst_RD, u1.dsp.opcode_RD,
            u1.dsp.PC_EX, u1.dsp.Inst_EX, u1.dsp.opcode_EX,
            u1.dsp.PC_WB, u1.dsp.Inst_WB, u1.dsp.opcode_WB);
        $display(" EX a:(%x)=%x b:(%x)=%x",
            u1.dsp.Inst_EX[`ra], u1.dsp.dataA_EXfwd, u1.dsp.Inst_EX[`rb], u1.dsp.dataB_EXfwd);
        if(u1.dsp.writeEn)
            $display(" WB w: %x <= %x",
                u1.dsp.addrW, u1.dsp.dataW);
    end
    $stop;
end
endmodule
