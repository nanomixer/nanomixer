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

initial begin
    for (i=0; i<8; i++) inputs[i] = i<<10;
    
    $display("Asserting reset");
    reset = 1;
    #100ns reset = 0;

    // Start of sample
    $display("Asserting start of sample.");
    @(posedge clk) start <= 1;
    @(posedge clk) start <= 0;

    for (i=0; i<10; i++) begin
        $display("Clock cycle %2d", i);
        $display(" PC = %d", u1.addrI);
        @(posedge clk);
    end
    $stop;
end
endmodule
