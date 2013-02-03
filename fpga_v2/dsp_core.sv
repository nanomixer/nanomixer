// Copyright (c) 2013 Martin Segado
// All rights reserved (until we choose a license)

module dsp_core #(
   LFSR_POLYNOMIAL = 36'h80000003B,

   SAMPLE_WIDTH = 36,   SAMPLE_FRACTIONAL_PART_WIDTH = 30, 
   PARAM_WIDTH  = 36,   PARAM_FRACTIONAL_PART_WIDTH  = 30,
   IO_WIDTH     = 24,   IO_FRACTIONAL_PART_WIDTH     = 20,

   SAMPLE_ADDR_WIDTH = 10,
   PARAM_ADDR_WIDTH  = 10
) (
   input logic clk, reset_n, // CPU clock & asyncronous reset
   interface sample_mem,
   interface param_mem,
   interface io_mem,
   
   input  instr_t instruction,
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

logic signed [ACCUM_WIDTH-1:0] M, next_M, // data registers & next-state variables
                               A, next_A;
                               
logic [LFSR_WIDTH-1:0] lfsr, next_lfsr;   // LFSR register and next-state variable

logic signed [SAMPLE_WIDTH-1:0] saturated_A, // saturator output
                                mult_in1;    // first multiplier input

logic signed [PARAM_WIDTH-1:0] mult_in2;     // second multiplier input
                                
instr_t read_instr,
        ex1_instr,
        ex2_instr, 
        writeback_instr;

        
/***** COMBINATORIAL LOGIC: *****/

always_comb begin
      // Data Request:
      sample_mem.rd_addr = read_instr.sample_addr;
      param_mem.rd_addr  = read_instr.param_addr;
      io_mem.rd_addr     = read_instr.param_addr;

      // Execute #1:
      case (ex1_instr.opcode)  // set first input to multiplier
         IN      : mult_in1 = 1'b1 << SAMPLE_FRACTIONAL_PART_WIDTH;
         default : mult_in1 = sample_mem.rd_data;
      endcase
      
      case (ex1_instr.opcode)  // set second input to multiplier (align decimals for input!)
         IN      : mult_in2 = signed'(io_mem.rd_data) << (PARAM_FRACTIONAL_PART_WIDTH - IO_FRACTIONAL_PART_WIDTH);
         default : mult_in2 = param_mem.rd_data;
      endcase

      next_M = mult_in1 * mult_in2; // multiply!
      
      // Execute #2:
      case (ex2_instr.opcode)  // handle accumulator inputs
         MUL, IN : next_A = M;
         MAC     : next_A = M + A;
         ROTMAC  : next_A = M + ring_bus_in;
         default : next_A = A;
      endcase
      
      if (lfsr[0] == 1)
         next_lfsr = (lfsr >> 1) ^ LFSR_POLYNOMIAL; // Galois LFSR logic
      else              
         next_lfsr = (lfsr >> 1);
      
      // Saturation & Writeback:
      saturated_A = A[PARAM_FRACTIONAL_PART_WIDTH + SAMPLE_WIDTH-1 -: SAMPLE_WIDTH];  
            // TODO: currently *truncates*; add saturation logic
      
      sample_mem.wr_addr = writeback_instr.sample_addr;
      
      case (writeback_instr.opcode)  // handle accumulator inputs
         IN, STORE : sample_mem.wr_en = 1'b1;
         default   : sample_mem.wr_en = 1'b0;
      endcase
end
 
assign test_out = lfsr; // TODO: Remove once testing is complete
 
 
/***** REGISTER LOGIC: *****/

always_ff @(posedge clk or negedge reset_n) begin
   if (~reset_n) begin         // TODO: finish reset logic once registers are all declared
      M <= '0;
      A <= '0;
      lfsr <= LFSR_POLYNOMIAL; // initialize LFSR with non-zero value to prevent lockup
   end
   else begin
      read_instr <= instruction;  // register instruction input
      ex1_instr <= read_instr; // propagate control information
      ex2_instr <= ex1_instr;
      writeback_instr <= ex2_instr;
      
      M <= next_M;
      A <= next_A;
      lfsr <= next_lfsr;
   end
end

endmodule
