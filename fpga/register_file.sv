module register_file #(
    parameter REGADDR_WIDTH = 5,
    parameter DATA_WIDTH = 32,
    parameter NUM_REGS = 1<<REGADDR_WIDTH)
(
	input wire clk,
	input wire [REGADDR_WIDTH-1:0] readAddrA, readAddrB, writeAddr,
	output wire [DATA_WIDTH-1:0] dataA, dataB,
	input wire [DATA_WIDTH-1:0] dataW,
	input wire writeEnable
);

bit[DATA_WIDTH-1:0] r[NUM_REGS];
bit[DATA_WIDTH-1:0] dataA_, dataB_;

assign dataA = (readAddrA == 'b0) ? 'b0 :
	(writeEnable && readAddrA == writeAddr) ? dataW : dataA_;
assign dataB = (readAddrB == 'b0) ? 'b0 :
	(writeEnable && readAddrB == writeAddr) ? dataW : dataB_;

always @(posedge clk) begin
	dataA_ <= r[readAddrA];
	dataB_ <= r[readAddrB];
end

always @(negedge clk) begin
	if (writeEnable) begin
		r[writeAddr] = dataW;
	end
end

endmodule
 