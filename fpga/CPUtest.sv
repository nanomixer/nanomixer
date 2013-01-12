module CPUtest #(
    parameter real CLK_FREQ = 100.0e6);

localparam time CLK_PERIOD = (1.0e9/CLK_FREQ)*1ns;

logic clk;

initial clk=0;
always #(CLK_PERIOD/2) clk = ~clk;

logic reset_n = 1;
logic start = 0;
logic[36-1:0] inputs[8];
wire[36-1:0] outputs[8];

DSPCore u1 (.clk, .reset_n, .start, .inputs, .outputs);

`define op 35:30
`define rw 29:20
`define ra 19:10
`define rb  9:0

bit [35:0] lastHI, lastLO;
int i;
int sample;
real curInput;
initial begin
    $display("Asserting reset");
    reset_n = 0;
    @(posedge clk);
    @(posedge clk);
    reset_n = 1;

    for (sample=0; sample<3; sample++) begin
        curInput = $sin(2*3.1415926535*sample*4800/48000);
        for (i=0; i<8; i++) inputs[i] = curInput*(1<<29);

        // Start of sample
        //$display("Asserting start of sample %d.", sample);
        @(posedge clk) start <= 1;
        @(posedge clk) start <= 0;

        for (i=0; i<50; i++) begin
            @(posedge clk);
            if (u1.dsp.HI_next != lastHI) begin
                lastHI = u1.dsp.HI_next;
                $display("%2d: HI=%x", i, lastHI);
                $display(" EX a:(%x)=%x b:(%x)=%x",
                    u1.dsp.Inst_EX[`ra], u1.dsp.dataA_EXfwd, u1.dsp.Inst_EX[`rb], u1.dsp.dataB_EXfwd);
            end
            /*$display("%2d: %x | %x %x %d | %x %x %d | %x %x %d",
                i, u1.addrI,
                u1.dsp.PC_RD, u1.dsp.Inst_RD, u1.dsp.opcode_RD,
                u1.dsp.PC_EX, u1.dsp.Inst_EX, u1.dsp.opcode_EX,
                u1.dsp.PC_WB, u1.dsp.Inst_WB, u1.dsp.opcode_WB);
            $display(" EX a:(%x)=%x b:(%x)=%x",
                u1.dsp.Inst_EX[`ra], u1.dsp.dataA_EXfwd, u1.dsp.Inst_EX[`rb], u1.dsp.dataB_EXfwd);
            if(u1.dsp.writeEn)
                $display(" WB w: %x <= %x",
                    u1.dsp.addrW, u1.dsp.dataW);
            $display("%x", outputs[0]);*/
        end
        //$display("%2d: %d, %d, %f", sample, inputs[0], outputs[0], real'(outputs[0])/real'(1<<29));
        $display("  xn=%x xn1=%x xn2=%x yn=%x yn1=%x yn2=%x",
            u1.rf0.r[1],
            u1.rf0.r[2],
            u1.rf0.r[3],
            u1.rf0.r[4],
            u1.rf0.r[5],
            u1.rf0.r[6]);
    end
    $stop;
end
endmodule
