module spi_serdes #(
    PACKET_WIDTH = 40
) (
    input wire clk,

    input logic [PACKET_WIDTH-1:0] txData,
    input logic load,
    output logic [PACKET_WIDTH-1:0] rxShiftReg,
    output logic dataReady,
    
    // SPI port
    input wire spi_SCLK, // spi clock
    input wire spi_SSEL, // spi slave select
    input wire spi_MOSI, // data in
    output logic spi_MISO // data out
);
localparam COUNT_WIDTH = $clog2(PACKET_WIDTH + 1);

// Synchronize signals
logic sclk, ssel, mosi;
synchronizer sclk_sync(clk, spi_SCLK, sclk);
synchronizer ssel_sync(clk, spi_SSEL, ssel);
synchronizer mosi_sync(clk, spi_MOSI, mosi);

logic prev_sclk;

logic sclk_posedge, sclk_negedge;

always_comb begin : proc_clkedges
    sclk_posedge = sclk & ~prev_sclk;
    sclk_negedge = ~sclk & prev_sclk;
end

logic [COUNT_WIDTH-1:0] bitsRemaining, bitsRemaining_next;
logic [PACKET_WIDTH-1:0] rxShiftReg_next, txShiftReg, txShiftReg_next;
logic dataReady_next;
always_comb begin
    spi_MISO = txShiftReg[PACKET_WIDTH-1];

    // defaults (no latches!)
    dataReady_next = '0;
    bitsRemaining_next = bitsRemaining;
    rxShiftReg_next = rxShiftReg;
    txShiftReg_next = txShiftReg;

    if (sclk_posedge) begin
        // shift out.
        rxShiftReg_next = {rxShiftReg[PACKET_WIDTH-2:0], mosi};
        txShiftReg_next = txShiftReg << 1;
        dataReady_next = '0;
    end else if (sclk_negedge) begin
        // read in.
        if (bitsRemaining) begin
            bitsRemaining_next = bitsRemaining_next - 1;
        end else begin
            bitsRemaining_next = PACKET_WIDTH-1;
            dataReady_next = '1;
        end
    end

    if (load) begin
        txShiftReg_next = txData;
    end
end

always_ff@(posedge clk or posedge ssel) begin
    prev_sclk <= sclk;
    if (ssel) begin
        // reset.
        bitsRemaining_next = PACKET_WIDTH-1;
        rxShiftReg_next = '0;
        txShiftReg_next = '0;
        dataReady_next = '0;
    end else begin
        bitsRemaining <= bitsRemaining_next;
        rxShiftReg <= rxShiftReg_next;
        txShiftReg <= txShiftReg_next;
        dataReady <= dataReady_next;
    end
end

endmodule
