
interface placeholder_interface;
   logic signed [35:0] rd_data, wr_data;
   logic [9:0]         rd_addr, wr_addr;
   logic               rd_en,   wr_en;
endinterface


module top (
   input clk, reset_n,
   input  logic signed [35:0] test_in, 
   output logic signed [35:0] test_out
);

placeholder_interface my_bus();
dsp_core my_dsp(.clk, 
                .reset_n,
                .sample_mem(my_bus),
                .param_mem(my_bus),
                .io_mem(my_bus),
                .test_out);
endmodule
