module register_file #(
    parameter REGADDR_WIDTH = 5,
    parameter DATA_WIDTH = 32,
    parameter NUM_REGS = 1<<REGADDR_WIDTH)
(
	input wire clk,
	input wire [REGADDR_WIDTH-1:0] readAddr, writeAddr,
	output logic [DATA_WIDTH-1:0] readData,
	input wire [DATA_WIDTH-1:0] writeData,
	input wire writeEnable
);

bit[DATA_WIDTH-1:0] r[NUM_REGS];

always @(posedge clk) begin
    readData <= r[readAddr];
	if (writeEnable) begin
		r[writeAddr] <= writeData;
	end
end

endmodule
 