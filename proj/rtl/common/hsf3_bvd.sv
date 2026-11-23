//+FHDR--------------------------------------------------------------------
// Copyright (C) 2026 Hasunosora IC Design Club
// MIT License
// Permission is hereby granted, free of charge, to any person obtaining a 
// copy of this design and associated documentation files (the “Design”), 
// to deal in the Design without restriction, including without limitation 
// the rights to use, copy, modify, merge, publish, distribute, sublicense, 
// and/or sell copies of the Design, and to permit persons to whom the 
// Design is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included 
// in all copies or substantial portions of the Design.
//
// THE DESIGN IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, 
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF 
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, 
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, 
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
// DESIGN OR THE USE OR OTHER DEALINGS IN THE DESIGN.
//-------------------------------------------------------------------------
// FILE NAME: hsf3_bvd.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/24    Cloned from hsf2_bvd
//-------------------------------------------------------------------------
// PURPOSE: Floating-point boundary value detector
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                 DEFAULT VALUE
// EXPONENT_WIDTH      1-32        Bit width of exponent       8
// MANTISSA_WIDTH      1-128       Bit width of mantissa       23
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"
`include "hsf3_macros.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Floating-point boundary value detector
module hsf3_bvd
#(
    parameter int EXPONENT_WIDTH = 8,
    parameter int MANTISSA_WIDTH = 23,
    `LP_MODULE int OP_WIDTH = 1 + EXPONENT_WIDTH + MANTISSA_WIDTH
)
(
    input  logic [OP_WIDTH - 1:0] op_in,
    
    output logic                  is_nan,
    output logic                  is_inf,
    output logic                  is_denorm,
    output logic                  is_zero
);

`HSF3_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);

// FP format structure
fp_s  op_in_fp;

// Sub-field flags
logic exp_all_ones;
logic exp_zero;
logic mantissa_not_zero;

// Assign to FP format strucuture
assign op_in_fp          = fp_s'(op_in);

// Sub-field all 0/1 detection
assign exp_all_ones      = &op_in_fp.exp;
assign exp_zero          = ~|op_in_fp.exp;
assign mantissa_not_zero = |op_in_fp.mantissa;

// Boundary value detection
assign is_nan            = exp_all_ones && mantissa_not_zero;   // Exponent max and mantissa not zero
assign is_inf            = exp_all_ones && ~mantissa_not_zero;  // Exponent max and mantissa zero
assign is_denorm         = exp_zero && mantissa_not_zero;       // Exponent zero but mantissa not zero
assign is_zero           = exp_zero && !mantissa_not_zero;      // Mantissa and exponent zero

endmodule : hsf3_bvd