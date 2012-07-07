//-*-mode:verilog-*--------------------------------------------------------
//
//  Copyright (c) 1999 Cornell University
//  Computer Systems Laboratory
//  Cornell University, Ithaca, NY 14853
//  All Rights Reserved
//
//  Permission to use, copy, modify, and distribute this software
//  and its documentation for any purpose and without fee is hereby
//  granted, provided that the above copyright notice appear in all
//  copies. Cornell University makes no representations
//  about the suitability of this software for any purpose. It is
//  provided "as is" without express or implied warranty. Export of this
//  software outside of the United States of America may require an
//  export license.
//
//  $Id: mips.h,v 1.5 2006/04/11 21:35:52 kca5 Exp $
//
//-------------------------------------------------------------------------

// Multiple inclusion prevention.
`ifndef __MIPS_H__
`define __MIPS_H__

/*----------------------------------------------------------
Instruction Fields
------------------------------------------------------------*/

`define	op    31:26  // 6-bit operation code
`define	rs    25:21  // 5-bit source register specifier
`define	rt    20:16  // 5-bit source/dest register specifier or sub opcode
`define	imm   15:0   // 16-bit immediate, branch or address displacement
`define	tgt   25:0   // 26-bit jump target address
`define	rd    15:11  // 5-bit destination register specifier
`define	sa    10:6   // 5-bit shift amount
`define	funct 5:0    // 6-bit function field


/*----------------------------------------------------------
Symbolic Register Names for Hardware
------------------------------------------------------------*/

`define	r0			5'b00000 
`define	r1			5'b00001
`define	r2			5'b00010
`define	r3			5'b00011
`define	r4			5'b00100
`define	r5			5'b00101
`define	r6			5'b00110
`define	r7			5'b00111
`define	r8			5'b01000
`define	r9			5'b01001
`define	r10			5'b01010
`define	r11			5'b01011
`define	r12			5'b01100
`define	r13			5'b01101
`define	r14			5'b01110
`define	r15			5'b01111
`define	r16			5'b10000
`define	r17			5'b10001
`define	r18			5'b10010
`define	r19			5'b10011
`define	r20			5'b10100
`define	r21			5'b10101
`define	r22			5'b10110
`define	r23			5'b10111
`define	r24			5'b11000
`define	r25			5'b11001
`define	r26			5'b11010
`define	r27			5'b11011
`define	r28			5'b11100
`define	r29			5'b11101
`define	r30			5'b11110
`define	r31			5'b11111

/*----------------------------------------------------------
Symbolic Register Names for Assembler and Compiler
----------------------------------------------------------*/

`define	zero			5'b00000	// Read only zero value
`define	at			5'b00001	// Assembler temporary
`define	v0			5'b00010	// Integer function value
`define	v1			5'b00011
`define	a0			5'b00100	// Parameters
`define	a1			5'b00101
`define	a2			5'b00110
`define	a3			5'b00111
`define	t0			5'b01000	// not preserved by subroutines
`define	t1			5'b01001
`define	t2			5'b01010
`define	t3			5'b01011
`define	t4			5'b01100
`define	t5			5'b01101
`define	t6			5'b01110
`define	t7			5'b01111
`define	s0			5'b10000	// preserved by subroutines
`define	s1			5'b10001
`define	s2			5'b10010
`define	s3			5'b10011
`define	s4			5'b10100
`define	s5			5'b10101
`define	s6			5'b10110
`define	s7			5'b10111
`define	t8			5'b11000	// preserved by subroutines
`define	t9			5'b11001
`define	k0			5'b11010	// Kernel
`define	k1			5'b11011
`define	gp			5'b11100	// Global pointer
`define	sp			5'b11101	// Stack pointer
`define	s8			5'b11110	// preserved by subroutines
`define	ra			5'b11111	// Link register

/*----------------------------------------------------------
Opcode Assignments for `op Operations
----------------------------------------------------------*/

`define	SPECIAL			6'b000000
`define	REGIMM			6'b000001
`define	J			6'b000010
`define	JAL			6'b000011
`define	BEQ			6'b000100
`define	BNE			6'b000101
`define	BLEZ			6'b000110
`define	BGTZ			6'b000111

`define	ADDI			6'b001000
`define	ADDIU			6'b001001
`define	SLTI			6'b001010
`define	SLTIU			6'b001011
`define	ANDI			6'b001100
`define	ORI			6'b001101
`define	XORI			6'b001110
`define	LUI			6'b001111

`define	COP0			6'b010000
`define	COP1			6'b010001
`define	COP2			6'b010010
`define	COP3			6'b010011
`define	BEQL			6'b010100
`define	BNEL			6'b010101
`define	BLEZL			6'b010110
`define	BGTZL			6'b010111

`define	LB			6'b100000
`define	LH			6'b100001
`define	LWL			6'b100010
`define	LW			6'b100011
`define	LBU			6'b100100
`define	LHU			6'b100101
`define	LWR			6'b100110

`define	SB			6'b101000
`define	SH			6'b101001
`define	SWL			6'b101010
`define	SW			6'b101011

`define	SWR			6'b101110
`define	CACHE			6'b101111

`define	LL			6'b110000
`define	LWC1			6'b110001
`define	LWC2			6'b110010
`define	LWC3			6'b110011

`define	LDC1			6'b110101
`define	LDC2			6'b110110
`define	LDC3			6'b110111

`define	SC			6'b111000
`define	SWC1			6'b111001
`define	SWC2			6'b111010
`define	SWC3			6'b111011

`define	SDC1			6'b111101
`define	SDC2			6'b111110
`define	SDC3			6'b111111


/*----------------------------------------------------------
Opcode Assignments for `SPECIAL function Operations
----------------------------------------------------------*/

`define	SLL			6'b000000
`define	SRL			6'b000010
`define	SRA			6'b000011
`define	SLLV			6'b000100
`define	SRLV			6'b000110
`define	SRAV			6'b000111

`define	JR			6'b001000
`define	JALR			6'b001001

`define	SYSCALL			6'b001100
`define	BREAK			6'b001101

`define	MFHI			6'b010000
`define	MTHI			6'b010001
`define	MFLO			6'b010010
`define	MTLO			6'b010011

`define	MULT			6'b011000
`define	MULTU			6'b011001
`define	DIV			6'b011010
`define	DIVU			6'b011011

`define	ADD			6'b100000
`define	ADDU			6'b100001
`define	SUB			6'b100010
`define	SUBU			6'b100011
`define	AND			6'b100100
`define	OR			6'b100101
`define	XOR			6'b100110
`define	NOR			6'b100111

`define	SLT			6'b101010
`define	SLTU			6'b101011

`define	TGE			6'b110000
`define	TGEU			6'b110001
`define	TLT			6'b110010
`define	TLTU			6'b110011
`define	TEQ			6'b110100

`define	TNE			6'b110110

/*----------------------------------------------------------------------------
Opcode Assignments for `REGIMM rt Operations
-----------------------------------------------------------------------------*/

`define	BLTZ			5'b00000
`define	BGEZ			5'b00001
`define	BLTZL			5'b00010
`define	BGEZL			5'b00011

`define	TGEI			5'b01000
`define	TGEIU			5'b01001
`define	TLTI			5'b01010
`define	TLTIU			5'b01011
`define	TEQI			5'b01100

`define	TNEI			5'b01110

`define	BLTZAL			5'b10000
`define	BGEZAL			5'b10001
`define	BLTZALL			5'b10010
`define	BGEZALL			5'b10011

/*----------------------------------------------------------------------------
Opcode Assignments for `COPz rs Operations
-----------------------------------------------------------------------------*/

`define	MF			5'b00000
`define	CF			5'b00010
`define	MT			5'b00100
`define	CT			5'b00110

`define	BC			5'b01000

/*----------------------------------------------------------
Opcode Assignments for `COPz rt Operations
----------------------------------------------------------*/

`define	BCF			5'b00000
`define	BCT			5'b00001
`define	BCFL			5'b00010
`define	BCTL			5'b00011

/*---------------------------------------------------------------------------
Miscellaneous
-----------------------------------------------------------------------------*/

`endif // !defined(__MIPS_H__)
