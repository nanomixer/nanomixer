/**
 * MEM pipeline stage.
 * 
 * Inputs:
 *  Control inputs:
 *  MemSigned: 1 if loaded partial word is sign-extended, 0 else.
 *  LoadMode: mux control of what to load:
 *   0: load word
 *   1: load half-word
 *   2: load byte
 * 
 *  Data inputs:
 *  dataAddr: Address of data.
 *  dataIn:   Data input from the data memory.
 *
 * Outputs:
 *  memOut: parsed data read from memory
 * 
 * Note:
 *  The CAST processor handled some of the output handling here.
 *  We're moving that to the main cpu module now. This is now
 *  just the load-parsing logic.
 */

module MEM
  (
   // Control inputs:
   input wire MemSigned,
   input wire [1:0] LoadMode,

   // Data inputs:
   input wire [31:0] dataAddr,
   input wire [31:0] dataIn,
   
   // Outputs:
   output wire [31:0] memOut
   );

   wire [1:0] byteOff = dataAddr[1:0];

   wire [31:0] halfWord;
   mux2to1 #(16) halfWordMux
     (
      .a(dataIn[31:16]),
      .b(dataIn[15:0]),
      .ctrl(byteOff[1]),
      .out(halfWord[15:0])
      );

   wire [31:0] byte;
   mux4to1 #(8) byteMux
     (
      .a(dataIn[31:24]),
      .b(dataIn[23:16]),
      .c(dataIn[15:8]),
      .d(dataIn[7:0]),
      .ctrl(byteOff),
      .out(byte[7:0])
      );

   // Extend the read data.
   wire        halfWordExt = halfWord[15] & MemSigned;
   assign      halfWord[31:16] = {16{halfWordExt}};
   wire        byteExt = byte[7] & MemSigned;
   assign      byte[31:8] = {24{byteExt}};
   
   // Switch among the possibilities.
   mux3to1 loadDataMux
     (
      .a(dataIn),
      .b(halfWord),
      .c(byte),
      .ctrl(LoadMode),
      .out(memOut)
      );

endmodule // MEM
