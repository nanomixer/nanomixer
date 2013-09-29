module synchronizer (input wire clk, input wire in, output logic out);

logic mid;
always @(posedge clk) begin
	out <= mid;
	mid <= in;
end

endmodule