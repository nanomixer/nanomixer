module spi_test #(
    parameter real CLK_FREQ = 100.0e6,
    parameter int WORD_WIDTH = 8);

localparam time CLK_PERIOD = (1.0e9/CLK_FREQ)*1ns;
localparam time SPI_PERIOD = 10*CLK_PERIOD;

logic clk;

initial clk=0;
always #(CLK_PERIOD/2) clk = ~clk;

logic spi_SCLK = 0; // spi clock
logic spi_SSEL = 0; // spi slave select
logic spi_MOSI = 0; // data in
logic spi_MISO; // data out

spi_slave u1 (.clk, .spi_SCLK, .spi_SSEL, .spi_MOSI, .spi_MISO);

// spies
wire [WORD_WIDTH-1:0] inputReg = u1.inputReg, outputReg = u1.outputReg;
wire sclk_posedge = u1.sclk_posedge, sclk_negedge=u1.sclk_negedge;

logic [WORD_WIDTH-1:0] miso_buf;

// clock is active high and the first sampling happens on the first falling edge.

task spi_xfer(logic [WORD_WIDTH-1:0] x);
begin
    int bitIdx;
    logic [WORD_WIDTH-1:0] mosi_buf;
    miso_buf = 'bx;
    
    // Let's try to mimic how McSPI is configured: master data output begins a half-clock
    // before the first posedge.
    spi_SCLK = 0;
    #(SPI_PERIOD);
    $display("spi_xfer %x", x);
    mosi_buf = x;
    spi_MOSI = mosi_buf[WORD_WIDTH-1];
    $display("spi_MOSI = %x", mosi_buf);
    
    // now start ticking. Sample and advance both at negedge.
    for (bitIdx=0; bitIdx<WORD_WIDTH; bitIdx++) begin
        #(SPI_PERIOD/2) spi_SCLK = 1;
        miso_buf <<= 1;
        mosi_buf <<= 1;
        #(SPI_PERIOD/2) spi_SCLK = 0;
        spi_MOSI = mosi_buf[WORD_WIDTH-1];
        miso_buf[0] = spi_MISO;
    end
    $display("sent: %x, recevied: %x", x, miso_buf);
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
    
    spi_xfer(8'hff);
    spi_xfer(8'h00);
    
    spi_SSEL = 1;
    #(SPI_PERIOD);
    
    $stop;
end
endmodule
