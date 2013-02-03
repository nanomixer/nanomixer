// Copyright (c) 2013 Martin Segado
// All rights reserved (until we choose a license)

module dsp_core #(
   LFSR_POLYNOMIAL = 36'h80000003B,

   SAMPLE_WIDTH = 36,   SAMPLE_FRACTIONAL_PART_WIDTH = 30, 
   PARAM_WIDTH  = 36,   PARAM_FRACTIONAL_PART_WIDTH  = 30,
   IO_WIDTH     = 24,   IO_FRACTIONAL_PART_WIDTH     = 20,

   SAMPLE_ADDR_WIDTH = 10,
   OFFSET_WIDTH = 10
   PARAM_ADDR_WIDTH  = 10,
) (
   input logic clk, reset_n, // CPU clock & asyncronous reset
   interface sample_mem,
   interface param_mem,
   interface io_mem,
   
   input  instr_t instr_in,
   input  logic signed [ACCUM_WIDTH-1:0] ring_bus_in,  // intercore communication
   output logic signed [ACCUM_WIDTH-1:0] ring_bus_out, // intercore communication
   
   input  logic signed [35:0] test_in,
   output logic signed [35:0] test_out
);
 
localparam ACCUM_WIDTH = SAMPLE_WIDTH + PARAM_WIDTH;
localparam LFSR_WIDTH = $size(LFSR_POLYNOMIAL);


/***** TYPE DEFINITIONS: *****/

typedef enum logic [5:0] {   // define opcode type with explicit encoding
   NOP = 6'h00,
   MAC = 6'h01  // *TODO*: complete this list
} opcode_t;

typedef struct {
   opcode_t                      opcode;
   logic                         sample_offset_en;
   logic [SAMPLE_ADDR_WIDTH-1:0] sample_addr;
   logic                         coeff_offset_en;
   logic [PARAM_ADDR_WIDTH-1:0]  param_addr;
   logic [7:0]                   filler_bits; // TODO: remove once interface bit widths are set properly =P
} instr_t;

typedef struct {
   opcode_t                      opcode;
   logic                         sample_offset_en;
   logic                         sample_wr_en;
   logic [SAMPLE_ADDR_WIDTH-1:0] sample_addr;
} control_t;                        // TODO: update this (replace opcode)

/***** VARIABLE DECLARATIONS: *****/

logic [INSTR_ADDR_WIDTH-1:0] PC;          // program counter
logic signed [ACCUM_WIDTH-1:0] M, next_M, // data registers & next-state variables
                               A, next_A;
logic [LFSR_WIDTH-1:0] lfsr, next_lfsr;   // LFSR register and next-state variable

logic signed [OFFSET_WIDTH-1:0] offset;

logic signed [SAMPLE_WIDTH-1:0] saturated_A; // saturator output

instr_t   instr;
control_t decoded_control;
control_t ex1_control,
          ex2_control, 
          writeback_control;


/***** COMBINATORIAL LOGIC: *****/

always_comb begin
      // Instruction Request:
      instr_mem.rd_addr = PC;
      
      // Instruction Decode & Data Request:
      instr = instr_t'(instr_mem.rd_data); // TODO: make sure bit widths match!!
      
      decoded_control.opcode = instr.opcode;
      decoded_control.sample_offset_en = instr.sample_offset_en;  // TODO: remove if offset applied here
      decoded_control.sample_addr = instr.sample_addr;            // TODO: rotate (and offset?) logic
      
      sample_mem.rd_addr = instr.sample_addr + (instr.sample_offset_en ? offset : 0);
      param_mem.rd_addr  = instr.param_addr  + (instr.param_offset_en  ? offset : 0);     
      
      // Execute #1:
      next_M = sample_mem.rd_data * param_mem.rd_data; // Multiply! TODO: add other ops
      
      // Execute #2:
      next_A = M + A; // Accumulate! TODO: add other ops
      
      if (lfsr[0] == 1)
         next_lfsr = (lfsr >> 1) ^ LFSR_POLYNOMIAL; // Galois LFSR logic
      else              
         next_lfsr = (lfsr >> 1);
      
      // Saturation & Writeback:
      saturated_A = A[PARAM_FRACTIONAL_PART_WIDTH + SAMPLE_WIDTH-1 -: SAMPLE_WIDTH];  
            // TODO: currently *truncates*; add saturation logic
      
      sample_mem.wr_addr = writeback_control.sample_addr;  // TODO: assumes offset fixed at decode... change?
      sample_mem.wr_en   = writeback_control.sample_wr_en;
end
 
assign test_out = lfsr; // TODO: Remove once testing is complete
 
 
/***** REGISTER LOGIC: *****/

always_ff @(posedge clk or negedge reset_n) begin
   if (~reset_n) begin         // TODO: finish reset logic once registers are all declared
      PC <= '0;
      M <= '0;
      A <= '0;
      lfsr <= LFSR_POLYNOMIAL; // initialize LFSR with non-zero value to prevent lockup
   end
   else begin
      PC <= PC + 1'b1;
      
      ex1_control <= decoded_control;   // propagate control information
      ex2_control <= ex1_control;
      writeback_control <= ex2_control;
      
      M <= next_M;
      A <= next_A;
      lfsr <= next_lfsr;
   end
end

endmodule
