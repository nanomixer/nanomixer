// megafunction wizard: %LPM_MULT%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: lpm_mult 

// ============================================================
// File Name: mult_signed_24_24_48.v
// Megafunction Name(s):
// 			lpm_mult
//
// Simulation Library Files(s):
// 			lpm
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 12.0 Build 178 05/31/2012 SJ Web Edition
// ************************************************************


//Copyright (C) 1991-2012 Altera Corporation
//Your use of Altera Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Altera Program License 
//Subscription Agreement, Altera MegaCore Function License 
//Agreement, or other applicable license agreement, including, 
//without limitation, that your use is for the sole purpose of 
//programming logic devices manufactured by Altera and sold by 
//Altera or its authorized distributors.  Please refer to the 
//applicable agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module mult_signed_24_24_48 (
	dataa,
	datab,
	result);

	input	[23:0]  dataa;
	input	[23:0]  datab;
	output	[47:0]  result;

	wire [47:0] sub_wire0;
	wire [47:0] result = sub_wire0[47:0];

	lpm_mult	lpm_mult_component (
				.dataa (dataa),
				.datab (datab),
				.result (sub_wire0),
				.aclr (1'b0),
				.clken (1'b1),
				.clock (1'b0),
				.sum (1'b0));
	defparam
		lpm_mult_component.lpm_hint = "MAXIMIZE_SPEED=5",
		lpm_mult_component.lpm_representation = "SIGNED",
		lpm_mult_component.lpm_type = "LPM_MULT",
		lpm_mult_component.lpm_widtha = 24,
		lpm_mult_component.lpm_widthb = 24,
		lpm_mult_component.lpm_widthp = 48;


endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: AutoSizeResult NUMERIC "1"
// Retrieval info: PRIVATE: B_isConstant NUMERIC "0"
// Retrieval info: PRIVATE: ConstantB NUMERIC "0"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: PRIVATE: LPM_PIPELINE NUMERIC "0"
// Retrieval info: PRIVATE: Latency NUMERIC "0"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: SignedMult NUMERIC "1"
// Retrieval info: PRIVATE: USE_MULT NUMERIC "1"
// Retrieval info: PRIVATE: ValidConstant NUMERIC "0"
// Retrieval info: PRIVATE: WidthA NUMERIC "24"
// Retrieval info: PRIVATE: WidthB NUMERIC "24"
// Retrieval info: PRIVATE: WidthP NUMERIC "48"
// Retrieval info: PRIVATE: aclr NUMERIC "0"
// Retrieval info: PRIVATE: clken NUMERIC "0"
// Retrieval info: PRIVATE: new_diagram STRING "1"
// Retrieval info: PRIVATE: optimize NUMERIC "0"
// Retrieval info: LIBRARY: lpm lpm.lpm_components.all
// Retrieval info: CONSTANT: LPM_HINT STRING "MAXIMIZE_SPEED=5"
// Retrieval info: CONSTANT: LPM_REPRESENTATION STRING "SIGNED"
// Retrieval info: CONSTANT: LPM_TYPE STRING "LPM_MULT"
// Retrieval info: CONSTANT: LPM_WIDTHA NUMERIC "24"
// Retrieval info: CONSTANT: LPM_WIDTHB NUMERIC "24"
// Retrieval info: CONSTANT: LPM_WIDTHP NUMERIC "48"
// Retrieval info: USED_PORT: dataa 0 0 24 0 INPUT NODEFVAL "dataa[23..0]"
// Retrieval info: USED_PORT: datab 0 0 24 0 INPUT NODEFVAL "datab[23..0]"
// Retrieval info: USED_PORT: result 0 0 48 0 OUTPUT NODEFVAL "result[47..0]"
// Retrieval info: CONNECT: @dataa 0 0 24 0 dataa 0 0 24 0
// Retrieval info: CONNECT: @datab 0 0 24 0 datab 0 0 24 0
// Retrieval info: CONNECT: result 0 0 48 0 @result 0 0 48 0
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_signed_24_24_48.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_signed_24_24_48.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_signed_24_24_48.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_signed_24_24_48.bsf TRUE FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_signed_24_24_48_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_signed_24_24_48_bb.v TRUE
// Retrieval info: LIB_FILE: lpm
