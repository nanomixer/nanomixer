module parameter_memory(
    input wire clk,
    input wire[7:0] addr,
    output wire[35:0] data,
    
    input wire[7:0] addrW,
    input wire[35:0] dataW,
    input wire writeEnable,
    input wire bankSelect);
    
    tmp_params tmp_params_inst (
        .address (addr),
        .clock (clk),
        .q (data)
        );

endmodule
