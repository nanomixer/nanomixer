module mixer(
	input wire adat_bitclock, // ~12.288 MHz
	input wire oversampling_bitclock, // ~98.304 MHz
	input wire adat_in,
	output wire adat_out,
	output wire[7:0] LED
);

wire data_request;

wire signed [23:0] audio_out [0:7];
adat_out adat_out_0(
        .clk(adat_bitclock),
        .rst(0), .timecode(0), .smux(0),
        .audio_bus(audio_out),
        .adat_bitstream(adat_out),
		  .data_request(data_request)
        );

wire signed [23:0] audio_in [0:7];
wire adat_data_valid;
adat_in adat_in_0(
        .clk(oversampling_bitclock),
        .rst(0),
        .adat_async(adat_in),
        .data_valid(adat_data_valid),
        .audio_bus(audio_in)
        );

gain_ctl gain(
	.clk(oversampling_bitclock),
	.data_request(data_request),
	.audio_out(audio_out),
	.audio_in(audio_in));

bit [23:0] max_level = 0;
wire [23:0] abs_val;
assign abs_val = audio_in[0][23] ? -audio_in[0] : audio_in[0];

always_ff @(posedge data_request) begin
	if (abs_val > max_level) max_level <= abs_val;
end

assign LED = abs_val[23:16];

endmodule
