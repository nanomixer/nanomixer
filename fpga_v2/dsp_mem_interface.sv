// Copyright (c) 2013 Kenneth Arnold, Martin Segado
// All rights reserved (until we choose a license)

interface dsp_mem_interface #(
   SAMPLE_WIDTH = 36,   SAMPLE_ADDR_WIDTH = 10,
   PARAM_WIDTH  = 36,   PARAM_ADDR_WIDTH  = 10,
   IO_WIDTH     = 24
) (
   input  logic clk, reset_n, // CPU clock & asyncronous reset

   input  logic [SAMPLE_WIDTH-1:0]      sample_rd_data, 
   output logic [SAMPLE_ADDR_WIDTH-1:0] sample_rd_addr,
   output logic                         sample_rd_en,
   
   output logic [SAMPLE_WIDTH-1:0]      sample_wr_data, 
   output logic [SAMPLE_ADDR_WIDTH-1:0] sample_wr_addr,
   output logic                         sample_wr_en,
   
   input  logic [PARAM_WIDTH-1:0]      param_rd_data, 
   output logic [PARAM_ADDR_WIDTH-1:0] param_rd_addr,
   output logic                        param_rd_en,
   
   input  logic [IO_WIDTH-1:0] audio_inputs[8],
   output logic [IO_WIDTH-1:0] audio_outputs[8],
);


/***** VARIABLE DECLARATIONS: *****/

logic [IO_WIDTH-1:0]         io_rd_data, io_wr_data;
logic [PARAM_ADDR_WIDTH-1:0] io_rd_addr, io_wr_addr;
logic                        io_rd_en,   io_wr_en;                        


/***** MODPORT DECLARATIONS: *****/
   
modport dsp_sample_bus (
   input  .rd_data(sample_rd_data),
   output .rd_addr(sample_rd_addr),
   output .rd_en(sample_rd_en),
   output .wr_data(sample_wr_data),
   output .wr_addr(sample_wr_addr),
   output .wr_en(sample_wr_en)
   );
   
modport dsp_param_bus (
   input  .rd_data(param_rd_data),
   output .rd_addr(param_rd_addr),
   output .rd_en(param_rd_en),
   );

modport dsp_io_bus (
   input  .rd_data(io_rd_data),
   output .rd_addr(io_rd_addr),
   output .rd_en(io_rd_en),
   output .wr_data(io_wr_data),
   output .wr_addr(io_wr_addr),
   output .wr_en(io_wr_en)
   );

   
/***** IO ADDRESSING LOGIC: *****/

always_ff @(posedge clk) begin
   if (io_rd_en) io_rd_data <= audio_inputs[io_rd_addr[2:0]];
   if (io_wr_en) audio_outputs[io_wr_addr[2:0]] <= io_wr_data;
end

endinterface
