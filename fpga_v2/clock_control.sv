module clock_control (
  input logic activeClock,
  input logic slaveClockBad,
  input logic allowSlave,
  output logic clockSwitch);
  
// clocks: 0 = master, 1 = slave


// activeClock    0 0 0 0 1 1 1 1
// slaveClockGood 1 1 0 0 1 1 0 0
// allowSlave     0 1 0 1 0 1 0 1
// clockSwitch    0 1 0 0 1 0 0 0

logic slaveClockGood = !slaveClockBad;
logic preventSlave = !allowSlave;
logic onMaster = (activeClock == 0);
logic onSlave = (activeClock == 1);

always_comb begin
    clockSwitch = 0;
    if (slaveClockGood) begin
        if (allowSlave && onMaster) begin
            clockSwitch = 1;
        end else if (preventSlave && onSlave) begin
            clockSwitch = 1;
        end
    end
end

endmodule