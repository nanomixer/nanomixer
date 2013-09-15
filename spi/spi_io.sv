module spi_io #(
    WORD_WIDTH = 36,
    ADDR_WIDTH = 10
) (
    input wire clk,

    // SPI port
    input wire spi_SCLK, // spi clock
    input wire spi_SSEL, // spi slave select
    input wire spi_MOSI, // data in
    output logic spi_MISO // data out
);
localparam PACKET_WIDTH = WORD_WIDTH + 4;

logic dataReady;
logic [PACKET_WIDTH-1:0] inPacket;
logic [PACKET_WIDTH-1:0] outPacket;

logic[ADDR_WIDTH-1:0] rd_addr;
logic[WORD_WIDTH-1:0] rd_data;

logic[ADDR_WIDTH-1:0] wr_addr;
logic[WORD_WIDTH-1:0] wr_data;
logic wr_enable;

logic inPacketIsValid;

spi_serdes #(.PACKET_WIDTH(PACKET_WIDTH)) serdes (
    .clk, .dataReady, .outPacket, .inPacket,
    .spi_SSEL, .spi_SCLK, .spi_MISO, .spi_MOSI);

memif #(.WORD_WIDTH(WORD_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) memif_inst (
    .reset(spi_SSEL),
    .clk,
    .dataReady, .inPacket, .outPacket,
    .rd_addr, .rd_data,
    .wr_addr, .wr_data, .wr_enable,
    .inPacketIsValid);

test_meter test_meter_inst (
    .address ( rd_addr ),
    .clock ( clk ),
    .data ( '0 ),
    .wren ( '0 ),
    .q ( rd_data ));

test_coeff test_coeff_inst (
    .clock(clk),
    .address(wr_addr),
    .data(wr_data),
    .wren(wr_enable));

endmodule
