// Copyright (c) 2013 Martin Segado
// All rights reserved (until we choose a license)

module dsp_core #(
   LFSR_POLYNOMIAL = 36'h80000003B,
   LFSR_WIDTH = $size(LFSR_POLYNOMIAL),

   SAMPLE_WIDTH = 36,   SAMPLE_FRAC_BITS = 30,   SAMPLE_SINT_BITS = SAMPLE_WIDTH - SAMPLE_FRAC_BITS,
   PARAM_WIDTH  = 36,   PARAM_FRAC_BITS  = 30,   PARAM_SINT_BITS  = PARAM_WIDTH  - PARAM_FRAC_BITS,
   IO_WIDTH     = 24,   IO_FRAC_BITS     = 20,   IO_SINT_BITS     = IO_WIDTH     - IO_FRAC_BITS,

   OPCODE_WIDTH = 6,
   SAMPLE_ADDR_WIDTH = 10,
   PARAM_ADDR_WIDTH  = 10,
   
   ACCUM_WIDTH = SAMPLE_WIDTH + PARAM_WIDTH,
   ACCUM_FRAC_BITS = SAMPLE_FRAC_BITS + PARAM_FRAC_BITS,
   ACCUM_SINT_BITS = SAMPLE_SINT_BITS + PARAM_SINT_BITS,
   
   INSTR_WIDTH = OPCODE_WIDTH + SAMPLE_ADDR_WIDTH + PARAM_ADDR_WIDTH
) (
   input logic clk, reset_n, // CPU clock & asyncronous reset
   interface sample_mem,
   interface param_mem,
   interface io_mem,
   
   input  logic [INSTR_WIDTH-1:0] instruction,
   input  logic signed [ACCUM_WIDTH-1:0] ring_bus_in,  // intercore communication
   output logic signed [ACCUM_WIDTH-1:0] ring_bus_out, // intercore communication
   
   input  logic signed [35:0] test_in,
   output logic signed [35:0] test_out
);


/***** TYPE DEFINITIONS: *****/

typedef enum logic [OPCODE_WIDTH-1:0] {   // define opcode type with explicit encoding
   NOP    = 6'h00,
   MUL    = 6'h01,
   MAC    = 6'h02,
   ROTMAC = 6'h03,
   STORE  = 6'h04,
   IN     = 6'h05,
   OUT    = 6'h06,
   SPIN   = 6'h07,
   AMAC   = 6'h08
} opcode_t;

typedef struct packed {
   opcode_t                      opcode;
   logic [SAMPLE_ADDR_WIDTH-1:0] sample_addr;
   logic [PARAM_ADDR_WIDTH-1:0]  param_addr;
} instr_t;


/***** VARIABLE DECLARATIONS: *****/

logic signed [ACCUM_WIDTH-1:0] M, next_M, // data registers & next-state variables
                               A, next_A;
                               
logic [LFSR_WIDTH-1:0] lfsr, next_lfsr;   // LFSR register and next-state variable

logic signed [SAMPLE_WIDTH-1:0] mult_in1, // first multiplier input
                                sample_saturator_out;

logic signed [PARAM_WIDTH-1:0] mult_in2;  // second multiplier input
                                
instr_t decode_instr,
        read_instr,
        ex1_instr,
        ex2_instr, 
        writeback_instr;

logic [SAMPLE_ADDR_WIDTH-1:0] spin_pointer, next_spin_pointer;
        
logic [ACCUM_SINT_BITS - IO_SINT_BITS-1 : 0] io_truncated_MSBs;
logic [ACCUM_SINT_BITS - SAMPLE_SINT_BITS-1 : 0] sample_truncated_MSBs;
      
      
/***** MODULE INSTANTIATION & CONNECTIONS: *****/
      
// Connect a saturator between accumulator and sample memory write port
fixed_point_saturator #(.IN_WIDTH(ACCUM_WIDTH),
                        .IN_FRAC_BITS(ACCUM_FRAC_BITS),
                        .OUT_WIDTH(SAMPLE_WIDTH),
                        .OUT_FRAC_BITS(SAMPLE_FRAC_BITS)) 
                     sample_saturator (.data_in(A),
                                       .data_out(sample_saturator_out));

// Connect a saturator between accumulator and io memory write port
fixed_point_saturator #(.IN_WIDTH(ACCUM_WIDTH),
                        .IN_FRAC_BITS(ACCUM_FRAC_BITS),
                        .OUT_WIDTH(IO_WIDTH),
                        .OUT_FRAC_BITS(IO_FRAC_BITS)) 
                     io_saturator (.data_in(A),
                                   .data_out(io_mem.wr_data));


/***** COMBINATORIAL LOGIC: *****/

always_comb begin
      // Instruction "Decode":
      decode_instr = instr_t'(instruction);

      case (decode_instr.opcode)
         // Note: *positive* spin shifts data to *higher* addresses by *reducing* pointer:
         SPIN    : next_spin_pointer = spin_pointer - decode_instr.sample_addr;
         default : next_spin_pointer = spin_pointer;
      endcase
      
      decode_instr.sample_addr += spin_pointer;
      
      // Data Request:
      sample_mem.rd_addr = decode_instr.sample_addr;
      param_mem.rd_addr  = decode_instr.param_addr;
      io_mem.rd_addr     = read_instr.param_addr; // TODO
      /* WARNING: It turns out inputs to altsyncram blocks are registered, but not outputs.
         This is causing problems with timing since the memory read and multiply occur
         in the same clock cycle. For now, then, I'm (1) sending the request to memory one
         clock earlier (from "decode_instr" instead of "read_instr"), AND (2) enabling the
         output registers on the altsyncram components for parameter/sample memory. */
      
      sample_mem.rd_en   = 1'b1;  // always read for now
      param_mem.rd_en    = 1'b1;
      io_mem.rd_en       = 1'b1;
      
      // Execute #1:
      case (ex1_instr.opcode)  // set first input to multiplier
         IN      : mult_in1 = 1'b1 << SAMPLE_FRAC_BITS;
         default : mult_in1 = sample_mem.rd_data;
      endcase
      
      case (ex1_instr.opcode)  // set second input to multiplier (align decimals for input!)
         IN      : mult_in2 = signed'(io_mem.rd_data) << (PARAM_FRAC_BITS - IO_FRAC_BITS);
         AMAC    : mult_in2 = sample_saturator_out;
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
      
      // Saturation & Writeback (note that saturation is handled by modules above):
      io_mem.wr_addr = writeback_instr.param_addr;
      case (writeback_instr.opcode)
         OUT     : io_mem.wr_en = 1'b1;
         default : io_mem.wr_en = 1'b0;
      endcase
      
      sample_mem.wr_data = sample_saturator_out;
      sample_mem.wr_addr = writeback_instr.sample_addr;
      case (writeback_instr.opcode)
         IN, STORE : sample_mem.wr_en = 1'b1;
         default   : sample_mem.wr_en = 1'b0;
      endcase
      
      ring_bus_out = A; // inter-dsp communication output
end
 
assign test_out = lfsr; // TODO: Remove once testing is complete
 
 
/***** REGISTER LOGIC: *****/

always_ff @(posedge clk or negedge reset_n) begin
   if (~reset_n) begin         // TODO: finish reset logic once registers are all declared
      spin_pointer <= '0;
   
      read_instr <= '0;
      ex1_instr <= '0;
      ex2_instr <= '0;
      writeback_instr <= '0;
      
      M <= '0;
      A <= '0;
      lfsr <= LFSR_POLYNOMIAL; // initialize LFSR with non-zero value to prevent lockup
   end
   else begin
      spin_pointer <= next_spin_pointer;
   
      read_instr <= decode_instr; // propagate control information
      ex1_instr <= read_instr;
      ex2_instr <= ex1_instr;
      writeback_instr <= ex2_instr;
      
      M <= next_M;
      A <= next_A;
      lfsr <= next_lfsr;
   end
end

endmodule
