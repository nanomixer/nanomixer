// Copyright (c) 2013 Kenneth Arnold, Martin Segado
// All rights reserved (until we choose a license)

module top #(
   SAMPLE_WIDTH = 36,   SAMPLE_ADDR_WIDTH = 10,
   PARAM_WIDTH  = 36,   PARAM_ADDR_WIDTH  = 10,
   IO_WIDTH     = 24,

   DSP_CLK_KHZ  = 98304, // must be 2^N times sample rate, where N is integer
   SAMPLE_RATE_KHZ = 48,

   INSTR_WIDTH = 26,
   PC_WIDTH = $bits(DSP_CLK_KHZ/SAMPLE_RATE_KHZ - 1)
) (
   input  logic dsp_clk,
                adat_in_clk,   // 98.304 MHz (assuming 48 kHz sample rate)
                adat_out_clk,  // 12.288 MHz (assuming 48 kHz sample rate)
                reset_n,

   input  logic adat_async_in,
   output logic adat_bitstream_out,

    // SPI port
    input wire spi_SCLK, // spi clock
    input wire spi_SSEL, // spi slave select
    input wire spi_MOSI, // data in
    output logic spi_MISO // data out
);
localparam PACKET_WIDTH = 40, WORD_WIDTH=36, ADDR_WIDTH=10;

/***** VARIABLE DECLARATIONS: *****/

logic [SAMPLE_WIDTH-1:0]      sample_rd_data;
logic [SAMPLE_ADDR_WIDTH-1:0] sample_rd_addr;
logic                         sample_rd_en;

logic [SAMPLE_WIDTH-1:0]      sample_wr_data;
logic [SAMPLE_ADDR_WIDTH-1:0] sample_wr_addr;
logic                         sample_wr_en;

logic [PARAM_WIDTH-1:0]      param_rd_data, param_wr_data;
logic [PARAM_ADDR_WIDTH-1:0] param_rd_addr, param_wr_addr;
logic                        param_rd_en, param_wr_en;

logic [IO_WIDTH-1:0] audio_inputs  [0:7];
logic [IO_WIDTH-1:0] audio_outputs [0:7];

logic [SAMPLE_WIDTH-1:0] meter_rd_data, meter_wr_data;
logic [7:0]          meter_rd_addr, meter_wr_addr;
logic                meter_wr_en;

logic [PC_WIDTH-1:0] pc;
logic [INSTR_WIDTH-1:0] instruction;


/***** MODULE INSTANTIATION & CONNECTIONS: *****/

dsp_mem_interface my_dsp_bus(.clk(dsp_clk), .*);

dsp_core my_dsp(.clk(dsp_clk),
                .reset_n,
                .sample_mem(my_dsp_bus.dsp_sample_bus),
                .param_mem(my_dsp_bus.dsp_param_bus),
                .io_mem(my_dsp_bus.dsp_io_bus),
                .aux_out_addr(meter_wr_addr),
                .aux_out_data(meter_wr_data),
                .aux_out_en(meter_wr_en),
                .instruction);

metering_buffer my_meter(.clock(dsp_clk),
                         .address(meter_wr_addr),
                         .data   (meter_wr_data),
                         .wren   (meter_wr_en));

meter_mem meter_mem_inst (
    .clock ( dsp_clk ),
    .wraddress ( meter_wr_addr ),
    .wren ( meter_wr_en ),
    .data ( meter_wr_data ),
    .rdaddress ( meter_rd_addr ),
    .q ( meter_rd_data )
);

adat_in my_adat_in(.clk(adat_in_clk),
                   .adat_async(adat_async_in),
                   .audio_bus(audio_inputs));

adat_out my_adat_out(.clk(adat_out_clk),
                     .reset_n,
                     .timecode(1'b0), .midi(1'b0), .smux(1'b0),
                     .audio_in(audio_outputs),
                     .bitstream_out(adat_bitstream_out));

sample_mem_00 my_sample_mem(.clock(dsp_clk),
                            .rdaddress(sample_rd_addr),
                            .rden     (sample_rd_en),
                            .q        (sample_rd_data),
                            .wraddress(sample_wr_addr),
                            .wren     (sample_wr_en),
                            .data     (sample_wr_data));

param_mem param_mem_inst (
    .clock ( dsp_clk),
    .rdaddress ( param_rd_addr ),
    .q ( param_rd_data ),
    .wraddress ( param_wr_addr ),
    .data ( param_wr_data),
    .wren ( param_wr_en )
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
    .wr_addr(param_wr_addr), .wr_data(param_wr_data), .wr_enable(param_wr_en),
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
