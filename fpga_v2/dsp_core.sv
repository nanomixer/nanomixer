// Copyright (c) 2013 Martin Segado
// All rights reserved (until we choose a license)

module dsp_core #(
   LFSR_POLYNOMIAL = 36'h80000003B,

   SAMPLE_WIDTH = 36,   SAMPLE_FRACTIONAL_PART_WIDTH = 30, 
   PARAM_WIDTH  = 36,   PARAM_FRACTIONAL_PART_WIDTH  = 30,
   IO_WIDTH     = 24,   IO_FRACTIONAL_PART_WIDTH     = 20,

   SAMPLE_ADDR_WIDTH = 10,
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
   NOP    = 6'h00,
   MUL    = 6'h01,
   MAC    = 6'h02,
   ROTMAC = 6'h03,
   STORE  = 6'h04,
   IN     = 6'h05,
   OUT    = 6'h06
} opcode_t;

typedef struct {
   opcode_t                      opcode;
   logic [SAMPLE_ADDR_WIDTH-1:0] sample_addr;
   logic [PARAM_ADDR_WIDTH-1:0]  param_addr;
} instr_t;


/***** VARIABLE DECLARATIONS: *****/

logic [INSTR_ADDR_WIDTH-1:0] PC;          // program counter
logic signed [ACCUM_WIDTH-1:0] M, next_M, // data registers & next-state variables
                               A, next_A;
logic [LFSR_WIDTH-1:0] lfsr, next_lfsr;   // LFSR register and next-state variable

logic signed [SAMPLE_WIDTH-1:0] saturated_A; // saturator output

instr_t read_instr,
        ex1_instr,
        ex2_instr, 
        writeback_instr;


/***** COMBINATORIAL LOGIC: *****/

always_comb begin
      // Data Request:
      sample_mem.rd_addr = read_instr.sample_addr;
      param_mem.rd_addr  = read_instr.param_addr;
      
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
      
      sample_mem.wr_addr = writeback_instr.sample_addr;
      sample_mem.wr_en   = writeback_instr.sample_wr_en;
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
      
      read_instr <= instr_in;  // register instruction input
      ex1_instr <= read_instr; // propagate control information
      ex2_instr <= ex1_instr;
      writeback_instr <= ex2_instr;
      
      M <= next_M;
      A <= next_A;
      lfsr <= next_lfsr;
   end
end

endmodule
