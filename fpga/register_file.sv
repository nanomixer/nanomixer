module register_file #(
    parameter REGADDR_WIDTH = 5,
    parameter DATA_WIDTH = 32,
    parameter NUM_REGS = 1<<REGADDR_WIDTH)
(
	input wire clk,
	input wire [REGADDR_WIDTH-1:0] readAddrA, readAddrB, writeAddr,
	output logic [DATA_WIDTH-1:0] dataA, dataB,
	input wire [DATA_WIDTH-1:0] dataW,
	input wire writeEnable
);

bit[DATA_WIDTH-1:0] r[NUM_REGS];

always @(posedge clk) begin
    dataA <= (readAddrA == 'b0) ? 'b0 : r[readAddrA];
    dataB <= (readAddrB == 'b0) ? 'b0 : r[readAddrB];
end

always @(negedge clk) begin
	if (writeEnable) begin
		r[writeAddr] <= dataW;
	end
end

endmodule
 