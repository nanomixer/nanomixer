// Copyright (c) 2013 Kenneth Arnold, Martin Segado
// All rights reserved (until we choose a license)

module top #(
   SAMPLE_WIDTH = 36,   SAMPLE_ADDR_WIDTH = 10,
   PARAM_WIDTH  = 36,   PARAM_ADDR_WIDTH  = 10,
   IO_WIDTH     = 24,
   
   DSP_CLK_KHZ  = 98304, // must be 2^N times sample rate, where N is integer
   SAMPLE_RATE_KHZ = 48,
   
   INSTR_WIDTH = 26,
   PC_WIDTH = $bits(DSP_CLK_KHZ/SAMPLE_RATE_KHZ - 1)
) (
   input  logic dsp_clk,
                adat_in_clk,   // 98.304 MHz (assuming 48 kHz sample rate)
                adat_out_clk,  // 12.288 MHz (assuming 48 kHz sample rate)
                reset_n,

   input  logic adat_async_in,
   output logic adat_bitstream_out
);


/***** VARIABLE DECLARATIONS: *****/

logic [SAMPLE_WIDTH-1:0]      sample_rd_data;
logic [SAMPLE_ADDR_WIDTH-1:0] sample_rd_addr;
logic                         sample_rd_en;

logic [SAMPLE_WIDTH-1:0]      sample_wr_data;
logic [SAMPLE_ADDR_WIDTH-1:0] sample_wr_addr;
logic                         sample_wr_en;

logic [PARAM_WIDTH-1:0]      param_rd_data; 
logic [PARAM_ADDR_WIDTH-1:0] param_rd_addr;
logic                        param_rd_en;

logic [IO_WIDTH-1:0] audio_inputs  [0:7];
logic [IO_WIDTH-1:0] audio_outputs [0:7];

logic [IO_WIDTH-1:0] meter_wr_data;
logic [7:0]          meter_wr_addr;
logic                meter_wr_en;

logic [PC_WIDTH-1:0] pc;
logic [INSTR_WIDTH-1:0] instruction;


/***** MODULE INSTANTIATION & CONNECTIONS: *****/

dsp_mem_interface my_dsp_bus(.clk(dsp_clk), .*);

dsp_core my_dsp(.clk(dsp_clk), 
                .reset_n,
                .sample_mem(my_dsp_bus.dsp_sample_bus),
                .param_mem(my_dsp_bus.dsp_param_bus),
                .io_mem(my_dsp_bus.dsp_io_bus),
                .instruction);

metering_buffer my_meter(.clock(dsp_clk),
                         .address(meter_wr_addr), 
                         .data   (meter_wr_data),
                         .wren   (meter_wr_en));
                
adat_in my_adat_in(.clk(adat_in_clk),
                   .adat_async(adat_async_in),
                   .audio_bus(audio_inputs));
                
adat_out my_adat_out(.clk(adat_out_clk),
                     .reset_n,
                     .timecode(1'b0), .midi(1'b0), .smux(1'b0),
                     .audio_in(audio_outputs),
                     .bitstream_out(adat_bitstream_out));

sample_mem_00 my_sample_mem(.clock(dsp_clk),
                            .rdaddress(sample_rd_addr), 
                            .rden     (sample_rd_en),
                            .q        (sample_rd_data), 
                            .wraddress(sample_wr_addr), 
                            .wren     (sample_wr_en),
                            .data     (sample_wr_data));

param_mem_00 my_param_mem(.clock(dsp_clk), 
                          .address(param_rd_addr),
                          .rden   (param_rd_en),
                          .q      (param_rd_data),
                          .wren(1'b0));
                          
instr_mem my_instr_mem(.clock(dsp_clk), 
                       .address(pc),
                       .rden(1'b1),
                       .q(instruction),
                       .wren(1'b0));


/***** REGISTER LOGIC: *****/

always_ff @(posedge dsp_clk or negedge reset_n) begin
   if (!reset_n) begin 
      pc <= '0;
   end
   else begin
      pc <= pc + 1'b1; /* WARNING: Currently relies on overflow to wrap around, which
                          assumes that dsp_clk is *exactly* (2^PC_WIDTH) times sample rate */
   end
end

endmodule
