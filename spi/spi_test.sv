module spi_test #(
    parameter real CLK_FREQ = 100.0e6,
    parameter int WORD_WIDTH = 8,
    parameter int ADDR_WIDTH = 2);

localparam time CLK_PERIOD = (1.0e9/CLK_FREQ)*1ns;
localparam time SPI_PERIOD = 10*CLK_PERIOD;
localparam int PACKET_WIDTH = WORD_WIDTH + 4;
localparam int NIBBLE_WIDTH = WORD_WIDTH / 2;
localparam int NUM_ADDRS = 1 << ADDR_WIDTH;

logic clk;

initial clk=0;
always #(CLK_PERIOD/2) clk = ~clk;

logic spi_SCLK = 0; // spi clock
logic spi_SSEL = 0; // spi slave select
logic spi_MOSI = 0; // data in
logic spi_MISO; // data out

logic dataReady;
logic [PACKET_WIDTH-1:0] outPacket;
logic [PACKET_WIDTH-1:0] inPacket;

spi_serdes #(.PACKET_WIDTH(PACKET_WIDTH)) serdes_inst
    (.clk, .spi_SCLK, .spi_SSEL, .spi_MOSI, .spi_MISO,
     .dataReady, .inPacket, .outPacket);

logic[ADDR_WIDTH-1:0] rd_addr;
logic[WORD_WIDTH-1:0] rd_data;
logic[ADDR_WIDTH-1:0] wr_addr;
logic[WORD_WIDTH-1:0] wr_data;
logic wr_enable;

logic inPacketIsValid;

memif #(.WORD_WIDTH(WORD_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) memif_inst (
    .reset(spi_SSEL),
    .clk,
    .dataReady, .inPacket, .outPacket,
    .rd_addr, .rd_data,
    .wr_addr, .wr_data, .wr_enable,
    .inPacketIsValid);

// Cheap RAM module.
logic [WORD_WIDTH-1:0] mem[NUM_ADDRS];
initial begin
    int i;
    for (i = 0; i<NUM_ADDRS; i++) mem[i] = '0;
end
always @(posedge clk) begin
    rd_data <= mem[rd_addr];
    if (wr_enable) begin
        mem[wr_addr] <= wr_data;
        $display("Wrote %x at %x", wr_data, wr_addr);
    end
end

logic [PACKET_WIDTH-1:0] dataReceived;
logic [WORD_WIDTH-1:0] wordReceived;
assign wordReceived = {
    dataReceived[PACKET_WIDTH-3:PACKET_WIDTH/2],
    dataReceived[PACKET_WIDTH/2-3:0]};

// clock is active high and the first sampling happens on the first falling edge.

function logic [PACKET_WIDTH-1:0] packPacket(logic [WORD_WIDTH-1:0] word);
    packPacket = {
        2'b01, word[WORD_WIDTH-1:NIBBLE_WIDTH], // NIBBLE_WIDTH bits
        2'b10, word[NIBBLE_WIDTH-1:0]};
endfunction

task spi_xfer(logic [PACKET_WIDTH-1:0] masterToSlave);
begin
    int bitIdx;

    // Let's try to mimic how McSPI is configured: master data output begins a half-clock
    // before the first posedge.
    spi_SCLK = 0;
    #(SPI_PERIOD);
    $display("spi_xfer %x", masterToSlave);
    dataReceived = 'x;

    // now start ticking. Advance at negedge.
    for (bitIdx=PACKET_WIDTH-1; bitIdx>=0; bitIdx--) begin
        assert (dataReady == '0) else $error("Premature dataReady");
        spi_MOSI = masterToSlave[bitIdx];
        #(SPI_PERIOD/2) spi_SCLK = 1;
        dataReceived[bitIdx] = spi_MISO;
        #(SPI_PERIOD/2) spi_SCLK = 0;
    end
end
endtask : spi_xfer

int i;
initial begin
    spi_SSEL = 0;
    @(posedge clk);
    @(posedge clk);
    spi_SSEL = 1;
    spi_SCLK = 0;

    for (i=0; i<5; i++) @(posedge clk);

    // Start SPI transmission
    spi_SSEL = 0;

    // Read address
    spi_xfer(packPacket(8'h00));
    // Write address
    spi_xfer(packPacket(8'h01));
    // Some data
    for (i=0; i<5; i++) begin
        spi_xfer(packPacket(i+1));
    end

    spi_SSEL = 1;
    #(SPI_PERIOD);

    $stop;
end
endmodule
