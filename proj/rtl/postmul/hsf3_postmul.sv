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
// FILE NAME: hsf3_postmul.sv
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
// PURPOSE: Post-multiply processing unit (stage) for pipelined FMA
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

// Post-multiply processing unit (stage) for pipelined FMA
module hsf3_postmul
import hsf3_typedef_pkg::*;
#(
    parameter int             EXPONENT_WIDTH = 8,
    parameter int             MANTISSA_WIDTH = 23,
    `LP_MODULE int LZC_WIDTH       = $clog2(MANTISSA_WIDTH + 1 + 1),
    `LP_MODULE int REXP_WIDTH      = hs_math_basic_pkg::max(EXPONENT_WIDTH, LZC_WIDTH) + 1,
    `LP_MODULE int REXP_SUM_WIDTH  = REXP_WIDTH + 2,
    `LP_MODULE int FULL_PROD_WIDTH = MANTISSA_WIDTH * 2 + 2,
    `LP_MODULE int ALIGNED_WIDTH   = FULL_PROD_WIDTH + 1 // Aligned mantissa width of product result and operand C
)
(
    // Input operands (product and operand C)
    input  logic                  [FULL_PROD_WIDTH - 1:0] prod_mant_in,
    input  logic           signed [REXP_SUM_WIDTH - 1:0]  prod_exp_in,
    input  logic                  [MANTISSA_WIDTH:0]      c_mant_in,
    input  logic           signed [REXP_WIDTH - 1:0]      c_exp_in,

    input  malu_flags_s                                   flags_in,

    // Output aligned operands
    output logic                  [ALIGNED_WIDTH - 1:0]   mant_x_out,       // Large mantissa
    output logic                  [ALIGNED_WIDTH - 1:0]   mant_y_align_out, // Aligned small mantissa
    output logic           signed [REXP_SUM_WIDTH - 1:0]  exp_base_out,     // Aligned base exponent

    output postmul_flags_s                                flags_out
);

`HSF3_MANTISSA_TYPEDEF(MANTISSA_WIDTH);
`HSF3_EXPONENT_TYPEDEF(EXPONENT_WIDTH);
`HSF3_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);

`HSF3_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);
`HSF3_MANTISSA_ALIGNED_TYPEDEF(MANTISSA_WIDTH);

typedef logic signed [REXP_SUM_WIDTH - 1:0] rexp_sum_t;
typedef logic [REXP_SUM_WIDTH - 1:0] sft_amount_t;
typedef logic [ALIGNED_WIDTH - 3:0] mant_rshift_t;

// Aligned mantissa
logic              prod_cout;
mant_aligned_t     prod_mant_align;
mant_aligned_t     c_mant_align;

// Exponent difference to align
rexp_sum_t         prod_exp_norm;
rexp_sum_t         c_exp_ext;
rexp_sum_t         exp_diff;

// Exponent align flags
logic              exp_prod_lt_c;
logic              exp_prod_eq_c;
logic              mant_prod_lt_c;

logic              c_large;                              // Indicate operator C is larger than product

// Swapped mantissa of Y, which not re-aligned
mant_aligned_t     mant_y;

// Right shifter parameters
sft_amount_t       sft_amount;
mant_rshift_t      mant_y_shifted_hi;
grs_s              sft_grs_in;
grs_s              sft_grs_out;

// Align mantissa of product and operand C
assign prod_cout             = prod_mant_in[FULL_PROD_WIDTH - 1];
assign prod_mant_align       = prod_cout ?
    {prod_mant_in, 1'b0} :
    {prod_mant_in[FULL_PROD_WIDTH - 2:0], 2'b00};

// Padding zeros for operand C to align
assign c_mant_align          = {c_mant_in, {(MANTISSA_WIDTH + 2){1'b0}}};

// Align the exponents (difference)
assign prod_exp_norm         = prod_exp_in + rexp_sum_t'(prod_cout);
assign c_exp_ext             = rexp_sum_t'(c_exp_in);
assign exp_diff              = prod_exp_norm - c_exp_ext;

// Exponent comparison
assign exp_prod_lt_c         = exp_diff < 0;
assign exp_prod_eq_c         = exp_diff == 0;
assign mant_prod_lt_c        = prod_mant_align[FULL_PROD_WIDTH : MANTISSA_WIDTH + 2] < c_mant_in;

assign c_large               = !flags_in.c_zero &&
    (exp_prod_lt_c || (exp_prod_eq_c && mant_prod_lt_c));

// Non-swap/swap for operators and base exponent, sign selection
always_comb begin : op_swap_bexp_sign_sel
    if (flags_in.result_pass) begin
        // Forward the encoded result with Y = 0 for the next stage.
        mant_x_out            = mant_aligned_t'(c_mant_in[MANTISSA_WIDTH - 1:0]);
        mant_y                = '0;

        exp_base_out          = c_exp_ext;
        flags_out.result_sign = flags_in.c_sign;
    end
    else if (c_large) begin
        // C is larger than product
        // X = C, Y = P
        mant_x_out            = c_mant_align;
        mant_y                = prod_mant_align;

        exp_base_out          = c_exp_ext;
        flags_out.result_sign = flags_in.c_sign;
    end
    else begin
        // X = P, Y = C
        mant_x_out            = prod_mant_align;
        mant_y                = c_mant_align;

        exp_base_out          = prod_exp_norm;
        flags_out.result_sign = flags_in.prod_sign;
    end
end : op_swap_bexp_sign_sel

// Right shifter w/ GRS for pre-align exponent of Y
assign sft_amount            = $unsigned(exp_diff[REXP_SUM_WIDTH - 1] ? -exp_diff : exp_diff);
assign sft_grs_in.guard      = mant_y[1];
assign sft_grs_in.round      = mant_y[0];
assign sft_grs_in.sticky     = '0;

hsf3_grs_rshift #(
    .DATA_WIDTH      ($bits(mant_rshift_t)),
    .SFT_AMOUNT_WIDTH($bits(sft_amount_t) )
)
small_align_rshift_inst (
    .grs_in  (sft_grs_in                 ),
    .data_in (mant_y[ALIGNED_WIDTH - 1:2]),
    .sft_in  (sft_amount                 ),
    .data_out(mant_y_shifted_hi          ),
    .grs_out (sft_grs_out                )
);

assign mant_y_align_out      = {mant_y_shifted_hi,
        sft_grs_out.guard,
        sft_grs_out.round | sft_grs_out.sticky};

// Select adder/subtractor for same/different sign
assign flags_out.add_sub     = !flags_in.result_pass && !flags_in.c_zero &&
    (flags_in.prod_sign ^ flags_in.c_sign);

// Pass bypass flags
assign flags_out.result_pass = flags_in.result_pass;

endmodule : hsf3_postmul
