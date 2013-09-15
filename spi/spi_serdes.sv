module spi_serdes #(
    PACKET_WIDTH = 40
) (
    input wire clk,

    output logic dataReady,
    input logic [PACKET_WIDTH-1:0] outPacket,
    output logic [PACKET_WIDTH-1:0] inPacket,

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

logic startOfFrame;
logic [COUNT_WIDTH-1:0] bitsRemaining, bitsRemaining_next;
logic [PACKET_WIDTH-1:0] rxShiftReg_next, rxShiftReg, txShiftReg_next, txShiftReg;
logic dataReady_next;
assign inPacket = rxShiftReg;
always_comb begin
    spi_MISO = txShiftReg[PACKET_WIDTH-1];

    // defaults (no latches!)
    dataReady_next = '0;
    bitsRemaining_next = bitsRemaining;
    rxShiftReg_next = rxShiftReg;
    txShiftReg_next = txShiftReg;

    if (sclk_posedge) begin
        // sample on posedge
        rxShiftReg_next = {rxShiftReg[PACKET_WIDTH-2:0], mosi};
    end else if (sclk_negedge) begin
        // shift on nededge
        if (bitsRemaining) begin
            bitsRemaining_next = bitsRemaining - 1;
            txShiftReg_next = txShiftReg << 1;
        end else begin
            // End of packet.
            bitsRemaining_next = PACKET_WIDTH-1;
            dataReady_next = '1;
        end
    end

    if (startOfFrame || dataReady) begin
        txShiftReg_next = outPacket;
    end
end

always_ff@(posedge clk or posedge ssel) begin
    if (ssel) begin
        // reset.
        prev_sclk <= '0;
        bitsRemaining <= PACKET_WIDTH-1;
        rxShiftReg <= '0;
        dataReady <= '0;
        startOfFrame <= '1;
    end else begin
        prev_sclk <= sclk;
        bitsRemaining <= bitsRemaining_next;
        rxShiftReg <= rxShiftReg_next;
        txShiftReg <= txShiftReg_next;
        dataReady <= dataReady_next;
        startOfFrame <= '0;
    end
end

endmodule
