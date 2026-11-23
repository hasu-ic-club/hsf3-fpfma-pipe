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
// FILE NAME: hsf3_aalu.sv
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
// PURPOSE: Adder arithmetic logic unit (stage) for pipelined FMA
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME  RANGE           DESCRIPTION             DEFAULT VALUE
// EXPONENT_WIDTH  1-32            Exponent bit width      8
// MANTISSA_WIDTH  1-128           Mantissa bit width      23
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"
`include "hsf3_macros.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Adder arithmetic logic unit (stage) for pipelined FMA
module hsf3_aalu
import hsf3_typedef_pkg::*;
#(
    parameter int             EXPONENT_WIDTH = 8,
    parameter int             MANTISSA_WIDTH = 23,
    `LP_MODULE int LZC_WIDTH       = $clog2(MANTISSA_WIDTH + 1 + 1),
    `LP_MODULE int REXP_WIDTH      = hs_math_basic_pkg::max(EXPONENT_WIDTH, LZC_WIDTH) + 1,
    `LP_MODULE int REXP_SUM_WIDTH  = REXP_WIDTH + 2,
    `LP_MODULE int FULL_PROD_WIDTH = MANTISSA_WIDTH * 2 + 2,
    `LP_MODULE int ALIGNED_WIDTH   = FULL_PROD_WIDTH + 1,
    `LP_MODULE int SUM_WIDTH       = ALIGNED_WIDTH + 1
)
(
    // Input aligned operands
    input  logic                  [ALIGNED_WIDTH - 1:0]   mant_x_in,
    input  logic                  [ALIGNED_WIDTH - 1:0]   mant_y_align_in,
    input  logic           signed [REXP_SUM_WIDTH - 1:0]  exp_base_in,

    input  postmul_flags_s                                flags_in,

    // Adder result output
    output logic                  [SUM_WIDTH - 1:0]       mant_sum_out,
    output logic           signed [REXP_SUM_WIDTH - 1:0]  exp_base_out,

    output aalu_flags_s                                   flags_out
);

`HSF3_MANTISSA_TYPEDEF(MANTISSA_WIDTH);
`HSF3_EXPONENT_TYPEDEF(EXPONENT_WIDTH);
`HSF3_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);

`HSF3_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);
`HSF3_MANTISSA_ALIGNED_TYPEDEF(MANTISSA_WIDTH);

// Exact zero determination
logic x_eq_y;

// Core adder
hsf3_cadder #(
    .DATA_WIDTH(ALIGNED_WIDTH)
)
cadder_inst
(
    .op_a_in   (mant_x_in       ),
    .op_b_in   (mant_y_align_in ),
    .add_sub   (flags_in.add_sub),
    .result_out(mant_sum_out    )
);

// Exact zero determine
assign x_eq_y                = mant_x_in == mant_y_align_in;
assign flags_out.exact_zero  = !flags_in.result_pass &&
    flags_in.add_sub && x_eq_y;

// Pass the exponent base
always_comb begin : pass_exp_base
    exp_base_out = exp_base_in;
end : pass_exp_base

// Pass other flags
assign flags_out.result_pass = flags_in.result_pass;
assign flags_out.result_sign = flags_in.result_sign;

endmodule : hsf3_aalu
