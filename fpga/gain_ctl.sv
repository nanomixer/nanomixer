module gain_ctl(
	input wire clk, data_request,
	output bit signed [23:0] audio_out [0:7],
	input wire signed [23:0] audio_in [0:7]
);

logic go = 0;
logic[2:0] cur_channel;

wire[23:0] cur_gain;
wire signed [23:0] cur_sample;
wire signed [47:0] mul_out;

assign cur_sample = audio_in[cur_channel];
assign mul_out = cur_sample * cur_gain;

//config_mem	config_mem_inst (
//	.clock(clk),
//	// write port
//	//.data(config_data),
//	//.wraddress (config_addr),
//	//.wren(config_wren),
//	.rdaddress(cur_channel),
//	.rden(1),
//	.q(cur_gain)
//	);

instruction_rom instruction_rom_inst(
	.clock(clk),
	.address(cur_channel),
	.q(cur_gain));
	
always @(posedge clk) begin
	if (data_request) begin
		cur_channel <= 0;
		go <= 1;
	end else if (go) begin
		audio_out[cur_channel] <= mul_out[47:24];
		go <= cur_channel == 3'b111;
		cur_channel <= cur_channel + 1;
	end
end
endmodule
