module mixer(
	input wire adat_bitclock, // ~12.288 MHz
	input wire oversampling_bitclock, // ~98.304 MHz
	input wire adat_in,
	output wire adat_out,
    output wire spdif_out,
	output wire[7:0] LED
);

logic slow_clk = 0;
always @(posedge oversampling_bitclock) slow_clk <= ~slow_clk;

wire data_request;

logic signed [23:0] audio_out [0:7];
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
        
        spdif_out spdif_out_0(
            .clk(adat_bitclock),
            .ldatain(audio_out[0]), .rdatain(audio_out[1]),
            .serialout(spdif_out));

wire signed [35:0] dsp_in[8];
wire signed [35:0] dsp_out[8];
wire [7:0] clip;
genvar i;
generate
    for (i=0; i<8; i++) begin:channel
        assign dsp_in[i] = {{6{audio_in[i][23]}}, audio_in[i][23:0], {6{1'b0}}};
        saturate sat(.in(dsp_out[i]), .overflow(clip[i]), .out(audio_out[i]));
    end
endgenerate

DSPCore dsp0(
    .clk(slow_clk),
    .reset(0),
    .start(data_request),
    .inputs(dsp_in),
    .outputs(dsp_out));

wire [23:0] meter_src = audio_in[0];
wire [23:0] abs_val;
assign abs_val = meter_src[23] ? -meter_src : meter_src;

assign LED = abs_val[23:16];

endmodule
