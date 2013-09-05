module spi_serdes #(
    PACKET_WIDTH = 40
) (
    input wire clk,

    input logic [PACKET_WIDTH-1:0] toOutput,
    input logic loadOutput,
    output logic [PACKET_WIDTH-1:0] inputReg,
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
logic [PACKET_WIDTH-1:0] inputReg_next, outputReg, outputReg_next;
logic dataReady_next;
always_comb begin
    spi_MISO = outputReg[PACKET_WIDTH-1];

    // defaults (no latches!)
    dataReady_next = '0;
    bitsRemaining_next = bitsRemaining;
    inputReg_next = inputReg;
    outputReg_next = outputReg;

    if (sclk_posedge) begin
        // shift out.
        inputReg_next = {inputReg[PACKET_WIDTH-2:0], mosi};
        outputReg_next = outputReg << 1;
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

    if (loadOutput) begin
        outputReg_next = toOutput;
    end
end

always_ff@(posedge clk or posedge ssel) begin
    prev_sclk <= sclk;
    if (ssel) begin
        // reset.
        bitsRemaining_next = PACKET_WIDTH-1;
        inputReg_next = '0;
        outputReg_next = '0;
        dataReady_next = '0;
    end else begin
        bitsRemaining <= bitsRemaining_next;
        inputReg <= inputReg_next;
        outputReg <= outputReg_next;
        dataReady <= dataReady_next;
    end
end

endmodule
