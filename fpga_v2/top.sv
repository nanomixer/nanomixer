// Copyright (c) 2013 Kenneth Arnold, Martin Segado
// All rights reserved (until we choose a license)

module top #(
   SAMPLE_WIDTH = 36,   SAMPLE_ADDR_WIDTH = 10,
   PARAM_WIDTH  = 36,   PARAM_ADDR_WIDTH  = 10,
   IO_WIDTH     = 24,

   DSP_CLK_KHZ  = 98304, // must be 2^N times sample rate, where N is integer
   SAMPLE_RATE_KHZ = 48,

   INSTR_WIDTH = 26,
   PC_WIDTH = $bits(DSP_CLK_KHZ/SAMPLE_RATE_KHZ - 1),
	NUM_CORES = 16
) (
   input  logic dsp_clk,
                adat_in_clk,   // 98.304 MHz (assuming 48 kHz sample rate)
                adat_out_clk,  // 12.288 MHz (assuming 48 kHz sample rate)
                reset_n,

   input  logic adat_async_in0,
                adat_async_in1,
                adat_async_in2,
                adat_async_in3,

   output logic adat_bitstream_out0,
                adat_bitstream_out1,
                adat_bitstream_out2,
                adat_bitstream_out3,

    // SPI port
    input wire spi_SCLK, // spi clock
    input wire spi_SSEL, // spi slave select
    input wire spi_MOSI, // data in
    output logic spi_MISO // data out
);
localparam PACKET_WIDTH = 40, WORD_WIDTH=36, ADDR_WIDTH=10;
localparam PHYSICAL_IO_PER_CORE = 32 / NUM_CORES;

/***** VARIABLE DECLARATIONS: *****/

logic [SAMPLE_WIDTH-1:0]      sample_rd_data [0:NUM_CORES-1];
logic [SAMPLE_ADDR_WIDTH-1:0] sample_rd_addr [0:NUM_CORES-1];
logic                         sample_rd_en [0:NUM_CORES-1];

logic [SAMPLE_WIDTH-1:0]      sample_wr_data [0:NUM_CORES-1];
logic [SAMPLE_ADDR_WIDTH-1:0] sample_wr_addr [0:NUM_CORES-1];
logic                         sample_wr_en [0:NUM_CORES-1];

logic [PARAM_WIDTH-1:0]      param_rd_data [0:NUM_CORES-1], param_wr_data; // TODO: map param mem inputs
logic [PARAM_ADDR_WIDTH-1:0] param_rd_addr [0:NUM_CORES-1], param_wr_addr;
logic                        param_rd_en [0:NUM_CORES-1], param_wr_en;

logic [IO_WIDTH-1:0] physical_inputs  [0:31], core_inputs [0:NUM_CORES-1][0:PHYSICAL_IO_PER_CORE-1];
logic [IO_WIDTH-1:0] physical_outputs [0:31], core_outputs [0:NUM_CORES-1][0:PHYSICAL_IO_PER_CORE-1];

logic [SAMPLE_WIDTH-1:0] meter_rd_data, meter_wr_data [0:NUM_CORES-1]; // TODO: map meter mem properly
logic [7:0]          meter_rd_addr, meter_wr_addr [0:NUM_CORES-1];
logic                meter_wr_en [0:NUM_CORES-1];

logic [PC_WIDTH-1:0] pc;
logic [INSTR_WIDTH-1:0] instruction;

logic adat_bitclock [0:3];

logic adat_async_in [0:3];
assign adat_async_in[0] = adat_async_in0;
assign adat_async_in[1] = adat_async_in1;
assign adat_async_in[2] = adat_async_in2;
assign adat_async_in[3] = adat_async_in3;

logic adat_bitstream_out [0:3];
assign adat_bitstream_out0 = adat_bitstream_out[0];
assign adat_bitstream_out1 = adat_bitstream_out[1];
assign adat_bitstream_out2 = adat_bitstream_out[2];
assign adat_bitstream_out3 = adat_bitstream_out[3];


/***** MODULE INSTANTIATION & CONNECTIONS: *****/

genvar core;
generate
  for (core=0; core<NUM_CORES; core=core+1) begin : core_loop

    assign core_inputs[core] = physical_inputs[PHYSICAL_IO_PER_CORE*core +: PHYSICAL_IO_PER_CORE];
    assign physical_outputs[PHYSICAL_IO_PER_CORE*core +: PHYSICAL_IO_PER_CORE] = core_outputs[core];

    dsp_mem_interface #(.PHYSICAL_IO_PER_CORE(PHYSICAL_IO_PER_CORE)) my_dsp_bus(
      .clk(dsp_clk), .reset_n,
      .sample_rd_data ( sample_rd_data[core] ),
      .sample_rd_addr ( sample_rd_addr[core] ),
      .sample_rd_en   ( sample_rd_en[core]   ),
      .sample_wr_data ( sample_wr_data[core] ),
      .sample_wr_addr ( sample_wr_addr[core] ),
      .sample_wr_en   ( sample_wr_en[core]   ),
      .param_rd_data  ( param_rd_data[core]  ),
      .param_rd_addr  ( param_rd_addr[core]  ),
      .param_rd_en    ( param_rd_en[core]    ),
      .core_inputs    ( core_inputs[core]    ),
      .core_outputs   ( core_outputs[core]   )
      );

    dsp_core my_dsp(.clk(dsp_clk),
                    .reset_n,
                    .sample_mem(my_dsp_bus.dsp_sample_bus),
                    .param_mem(my_dsp_bus.dsp_param_bus),
                    .io_mem(my_dsp_bus.dsp_io_bus),
                    .aux_out_addr(meter_wr_addr[core]), // TODO: map meter mem properly
                    .aux_out_data(meter_wr_data[core]),
                    .aux_out_en(meter_wr_en[core]),
                    .instruction);

    sample_mem_00 my_sample_mem(.clock(dsp_clk),
                                .rdaddress ( sample_rd_addr[core] ),
                                .rden      ( sample_rd_en[core]   ),
                                .q         ( sample_rd_data[core] ),
                                .wraddress ( sample_wr_addr[core] ),
                                .wren      ( sample_wr_en[core]   ),
                                .data      ( sample_wr_data[core] )
                                );

    param_mem param_mem_inst (
        .clock     ( dsp_clk ),
        .rdaddress ( param_rd_addr[core] ),
        .q         ( param_rd_data[core] ),
        .wraddress ( param_wr_addr ), // TODO: map param mem inputs
        .data      ( param_wr_data ),
        .wren      ( param_wr_en   )
    );

  end
endgenerate

genvar adat;
generate
  for (adat=0; adat<4; adat=adat+1) begin : adat_loop

    adat_in adat_in (
        .clk(adat_in_clk),
        .adat_async(adat_async_in[adat]),
        .bit_clock(adat_bitclock[adat]),
        .audio_bus(physical_inputs[8*adat +: 8])
    );

    adat_out adat_out (
        .clk(adat_bitclock[0]), // For now, always slave to adat 0
        .reset_n,
        .timecode(1'b0),
        .midi(1'b0),
        .smux(1'b0),
        .audio_in(physical_outputs[8*adat +: 8]),
        .bitstream_out(adat_bitstream_out[adat])
    );

  end
endgenerate

meter_mem meter_mem_inst (
    .clock ( dsp_clk ),
    .wraddress ( meter_wr_addr[0] ), // TODO: map meter mem properly (currently hooked up to just core 0)
    .wren ( meter_wr_en[0] ),
    .data ( meter_wr_data[0] ),
    .rdaddress ( meter_rd_addr ),
    .q ( meter_rd_data )
);

instr_mem my_instr_mem(.clock(dsp_clk),
                       .address(pc),
                       .rden(1'b1),
                       .q(instruction),
                       .wren(1'b0));


// SPI interface
logic dataReady;
logic [PACKET_WIDTH-1:0] inPacket;
logic [PACKET_WIDTH-1:0] outPacket;

logic inPacketIsValid;

spi_serdes #(.PACKET_WIDTH(PACKET_WIDTH)) serdes (
    .clk(dsp_clk), .dataReady, .outPacket, .inPacket,
    .spi_SSEL, .spi_SCLK, .spi_MISO, .spi_MOSI);

memif #(.WORD_WIDTH(WORD_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) memif_inst (
    .reset(spi_SSEL),
    .clk(dsp_clk),
    .dataReady, .inPacket, .outPacket,
    .rd_addr(meter_rd_addr), .rd_data(meter_rd_data),
    .wr_addr(param_wr_addr), .wr_data(param_wr_data), .wr_enable(param_wr_en), // TODO: map param mem inputs
    .inPacketIsValid);


/***** REGISTER LOGIC: *****/

always_ff @(posedge dsp_clk or negedge reset_n) begin
   if (!reset_n) begin
      pc <= '0;
   end
   else begin
      pc <= pc + 1'b1; /* WARNING: Currently relies on overflow to wrap around, which
                          assumes that dsp_clk is *exactly* (2^PC_WIDTH) times sample rate */
   end
end

endmodule
