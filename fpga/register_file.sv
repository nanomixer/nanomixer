module register_file(
	input wire clk, reset,
	input wire [REGADDR_WIDTH-1:0] readAddrA, readAddrB, writeAddr,
	output wire [DATA_WIDTH-1:0] dataA, dataB,
	input wire [DATA_WIDTH-1:0] dataW,
	input wire writeEnable
);

parameter REGADDR_WIDTH = 5;
parameter DATA_WIDTH = 32;
parameter NUM_REGS = 1<<(REGADDR_WIDTH-1);

bit[DATA_WIDTH-1:0] r[NUM_REGS];
bit[DATA_WIDTH-1:0] dataA_, dataB_;

assign dataA = (readAddrA == 'b0) ? 'b0 :
	(writeEnable && readAddrA == writeAddr) ? dataW : dataA_;
assign dataB = (readAddrB == 'b0) ? 'b0 :
	(writeEnable && readAddrB == writeAddr) ? dataW : dataB_;

always @(posedge clk or posedge reset) begin
	if (reset) begin
		integer i;
		for (i=0; i<NUM_REGS; i++)
			r[i] <= 0;
	end else begin
		dataA_ <= r[readAddrA];
		dataB_ <= r[readAddrB];
	end
end

always @(negedge clk) begin
	if (!reset && writeEnable) begin
		r[writeAddr] = dataW;
	end
end

endmodule
 