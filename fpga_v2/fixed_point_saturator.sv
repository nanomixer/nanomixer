// Copyright (c) 2013 Kenneth Arnold, Martin Segado
// All rights reserved (until we choose a license)

module fixed_point_saturator #(
   IN_WIDTH  = 36,   IN_FRAC_BITS  = 30,   IN_SINT_BITS  = IN_WIDTH  - IN_FRAC_BITS,
   OUT_WIDTH = 24,   OUT_FRAC_BITS = 20,   OUT_SINT_BITS = OUT_WIDTH - OUT_FRAC_BITS,

   NUM_TRUNCATED_MSBS = IN_SINT_BITS - OUT_SINT_BITS
) (
   input logic  [IN_WIDTH-1:0]  data_in,
   output logic [OUT_WIDTH-1:0] data_out,
   output logic is_saturated
);

logic [NUM_TRUNCATED_MSBS-1:0] truncated_msbs;
logic [OUT_WIDTH-1:0] presaturated_out;

always_comb begin
   truncated_msbs   = data_in[IN_WIDTH-1 -: NUM_TRUNCATED_MSBS];
   presaturated_out = data_in[IN_WIDTH-NUM_TRUNCATED_MSBS-1 -: OUT_WIDTH];
   
   // if truncated MSBs aren't equal to the (sign extended) output MSB, saturate output:
   is_saturated = signed'(truncated_msbs) != signed'(presaturated_out[OUT_WIDTH-1]);
   
   case ({is_saturated, data_in[IN_WIDTH-1]})
      2'b10   : data_out = {1'b0, {(OUT_WIDTH-1){1'b1}}};  // largest positive number
      2'b11   : data_out = {1'b1, {(OUT_WIDTH-1){1'b0}}};  // largest negative number
      default : data_out = presaturated_out;  // yay, no saturation needed!
   endcase
end

endmodule
