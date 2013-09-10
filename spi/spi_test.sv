module spi_test #(
    parameter real CLK_FREQ = 100.0e6,
    parameter int PACKET_WIDTH = 8);

localparam time CLK_PERIOD = (1.0e9/CLK_FREQ)*1ns;
localparam time SPI_PERIOD = 10*CLK_PERIOD;

logic clk;

initial clk=0;
always #(CLK_PERIOD/2) clk = ~clk;

logic spi_SCLK = 0; // spi clock
logic spi_SSEL = 0; // spi slave select
logic spi_MOSI = 0; // data in
logic spi_MISO; // data out

logic [PACKET_WIDTH-1:0] txData;
logic load;
logic [PACKET_WIDTH-1:0] rxShiftReg;
logic dataReady;

spi_serdes #(.PACKET_WIDTH(PACKET_WIDTH)) u1 
    (.clk, .spi_SCLK, .spi_SSEL, .spi_MOSI, .spi_MISO,
     .txData, .load, .rxShiftReg, .dataReady);

logic [PACKET_WIDTH-1:0] dataReceived;
always @(posedge clk) if (dataReady) dataReceived <= rxShiftReg;

// clock is active high and the first sampling happens on the first falling edge.

task spi_xfer(logic [PACKET_WIDTH-1:0] x);
begin
    int bitIdx;
    
    // Let's try to mimic how McSPI is configured: master data output begins a half-clock
    // before the first posedge.
    spi_SCLK = 0;
    #(SPI_PERIOD);
    $display("spi_xfer %x", x);
    dataReceived = 'x;
    
    // now start ticking. Advance at negedge.
    for (bitIdx=PACKET_WIDTH-1; bitIdx>=0; bitIdx--) begin
        assert (dataReady == '0) else $error("Premature dataReady");
        spi_MOSI = x[bitIdx];
        #(SPI_PERIOD/2) spi_SCLK = 1;
        #(SPI_PERIOD/2) spi_SCLK = 0;
    end
    assert (rxShiftReg == x) else $error("Sent %x but %x got received.", x, rxShiftReg);
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
    
    spi_xfer(8'hab);
    spi_xfer(8'h15);
    
    spi_SSEL = 1;
    #(SPI_PERIOD);
    
    $stop;
end
endmodule
