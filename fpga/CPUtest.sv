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

int i;
logic[9:0] addrA = 0, addrB = 0; 
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

    for (i=0; i<15; i++) begin
        @(posedge clk);
        $display("%2d: %x | %x %x %d | %x %x %d | %x %x %d",
            i, u1.addrI,
            u1.dsp.PC_RD, u1.dsp.Inst_RD, u1.dsp.opcode_RD,
            u1.dsp.PC_EX, u1.dsp.Inst_EX, u1.dsp.opcode_EX,
            u1.dsp.PC_WB, u1.dsp.Inst_WB, u1.dsp.opcode_WB);
        $display("  : a:(%x)=%x b:(%x)=%x", addrA, u1.dsp.dataA, addrB, u1.dsp.dataB);
        if(u1.dsp.writeEn)
            $display("  : w: %x <= %x", u1.dsp.addrW, u1.dsp.dataW);
        addrA <= u1.dsp.addrA;
        addrB <= u1.dsp.addrB;
    end
    $stop;
end
endmodule
