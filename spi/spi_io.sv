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

logic [PACKET_WIDTH-1:0] toOutput;
logic loadOutput;
logic [PACKET_WIDTH-1:0] inputReg;
logic dataReady;

logic[ADDR_WIDTH-1:0] rd_addr;
logic[WORD_WIDTH-1:0] rd_data;

logic valid;

spi_serdes #(.PACKET_WIDTH(PACKET_WIDTH)) serdes (
    .clk, .txData(toOutput), .load(loadOutput),
    .rxShiftReg(), .dataReady(),
    .spi_SSEL, .spi_SCLK, .spi_MISO, .spi_MOSI);

memif #(.WORD_WIDTH(WORD_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) memif_inst (
    .reset(spi_SSEL),
    .clk,
    .toOutput, .loadOutput, .inputReg, .dataReady,
    .rd_addr, .rd_data,
    .wr_addr(), .wr_data(), .wr_enable(),
    .valid);

test_meter test_meter_inst (
    .address ( rd_addr ),
    .clock ( clk ),
    .data ( '0 ),
    .wren ( '0 ),
    .q ( rd_data ));



endmodule
