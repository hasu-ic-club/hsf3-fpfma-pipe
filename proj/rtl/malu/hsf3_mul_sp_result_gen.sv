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
// FILE NAME: hsf3_mul_sp_result_gen.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/23    First Edition
//-------------------------------------------------------------------------
// PURPOSE: Specifal result generator for NaN/infinity/zero values of multiplier
//          Sideband for denorm numbers and result sign
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

// Specifal result generator for NaN/infinity/zero values of multiplier
module hsf3_mul_sp_result_gen
#(
    parameter int EXPONENT_WIDTH = 8,
    parameter int MANTISSA_WIDTH = 23,
    `LP_MODULE int OP_WIDTH = 1 + EXPONENT_WIDTH + MANTISSA_WIDTH
)
(
    // Input operators
    input  logic [OP_WIDTH - 1:0] op_a_in,
    input  logic [OP_WIDTH - 1:0] op_b_in,

    // Special result output
    output logic                  prod_nan,   // Product is NaN (high-priority)
    output logic                  prod_inf,   // Product is infinity
    output logic                  prod_zero,  // Product is zero

    // Sideband output
    output logic                  op_a_denorm,
    output logic                  op_b_denorm,
    output logic                  prod_sign
);

// Sign of operators
logic op_a_sign;
logic op_b_sign;

// Boundary flags of operands
logic op_a_nan;
logic op_a_inf;
logic op_a_zero;
logic op_b_nan;
logic op_b_inf;
logic op_b_zero;

// Sign extract
assign op_a_sign   = op_a_in[OP_WIDTH - 1];
assign op_b_sign   = op_b_in[OP_WIDTH - 1];

// Boundary value detector
hsf3_bvd
#(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
bvd_op_a_inst
(
    .op_in    (op_a_in    ),
    .is_nan   (op_a_nan   ),
    .is_inf   (op_a_inf   ),
    .is_denorm(op_a_denorm),
    .is_zero  (op_a_zero  )
);

hsf3_bvd
#(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
bvd_op_b_inst
(
    .op_in    (op_b_in    ),
    .is_nan   (op_b_nan   ),
    .is_inf   (op_b_inf   ),
    .is_denorm(op_b_denorm),
    .is_zero  (op_b_zero  )
);

// Special result determination
assign prod_nan    = (op_a_nan || op_b_nan) ||
    (op_a_inf && op_b_zero) ||
    (op_b_inf && op_a_zero);
assign prod_zero   = op_a_zero || op_b_zero;
assign prod_inf    = op_a_inf || op_b_inf;
assign prod_sign   = op_a_sign ^ op_b_sign;

endmodule : hsf3_mul_sp_result_gen
