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
    `LP_MODULE int LZC_WIDTH        = $clog2(MANTISSA_WIDTH + 1 + 1),
    `LP_MODULE int REXP_WIDTH       = hs_math_basic_pkg::max(EXPONENT_WIDTH, LZC_WIDTH) + 1,
    `LP_MODULE int REXP_SUM_WIDTH   = REXP_WIDTH + 2,
    `LP_MODULE int FULL_PROD_WIDTH  = MANTISSA_WIDTH * 2 + 2,
    `LP_MODULE int ALIGNED_WIDTH    = FULL_PROD_WIDTH + 2,
    `LP_MODULE int SUM_WIDTH        = ALIGNED_WIDTH + 1,
    `LP_MODULE int SFT_AMOUNT_WIDTH = $clog2(ALIGNED_WIDTH + 1)
)
(
    // Raw product, aligned C and remaining alignment control
    input  logic                  [FULL_PROD_WIDTH - 1:0]   prod_mant_in,
    input  logic                  [ALIGNED_WIDTH - 1:0]     c_mant_align_in,
    input  logic           signed [REXP_SUM_WIDTH - 1:0]    exp_base_in,
    input  logic                  [SFT_AMOUNT_WIDTH - 1:0]  sft_amount_in,
    input  logic                                            shift_prod_in,
    input  logic                                            cmp_mant_en_in,
    input  malu_flags_s                                     flags_in,

    // Adder result output
    output logic                  [SUM_WIDTH - 1:0]         mant_sum_out,
    output logic           signed [REXP_SUM_WIDTH - 1:0]    exp_base_out,

    output aalu_flags_s                                     flags_out
);

`HSF3_MANTISSA_ALIGNED_TYPEDEF(MANTISSA_WIDTH);

typedef logic [SUM_WIDTH - 1:0] mant_sum_t;

logic          [SFT_AMOUNT_WIDTH - 1:0]   prod_sft_amount;
logic          [FULL_PROD_WIDTH - 1:0]    prod_mant_shifted_hi;
grs_s                                     prod_sft_grs_out;
mant_aligned_t                            prod_mant_align;
logic          [MANTISSA_WIDTH + 1:0]     prod_mant_cmp;
logic                                     c_large;
mant_aligned_t                            mant_x;
mant_aligned_t                            mant_y;
mant_sum_t                                mant_sum;
logic                                     x_eq_y;

// Align the raw product when C has the larger base exponent.
assign prod_sft_amount       = shift_prod_in ? sft_amount_in : '0;

hsf3_grs_rshift #(
    .DATA_WIDTH      (FULL_PROD_WIDTH ),
    .SFT_AMOUNT_WIDTH(SFT_AMOUNT_WIDTH)
)
prod_align_rshift_inst (
    .grs_in  ('0                  ),
    .data_in (prod_mant_in        ),
    .sft_in  (prod_sft_amount     ),
    .data_out(prod_mant_shifted_hi),
    .grs_out (prod_sft_grs_out    )
);

assign prod_mant_align       = {prod_mant_shifted_hi, prod_sft_grs_out.guard,
        prod_sft_grs_out.round | prod_sft_grs_out.sticky};

// For exponent differences of 0 and -1, C has zero padding below the
// compared slice. Use fixed product slices in parallel with the right shifter.
assign prod_mant_cmp         = shift_prod_in ?
    {1'b0, prod_mant_in[FULL_PROD_WIDTH - 1:MANTISSA_WIDTH + 1]} :
    prod_mant_in[FULL_PROD_WIDTH - 1:MANTISSA_WIDTH];
assign c_large               = cmp_mant_en_in ?
    (prod_mant_cmp < c_mant_align_in[ALIGNED_WIDTH - 1:MANTISSA_WIDTH + 2]) : shift_prod_in;

assign mant_x                = c_large ? c_mant_align_in : prod_mant_align;
assign mant_y                = c_large ? prod_mant_align : c_mant_align_in;

// Core adder
hsf3_cadder #(
    .DATA_WIDTH(ALIGNED_WIDTH)
)
cadder_inst
(
    .op_a_in   (mant_x          ),
    .op_b_in   (mant_y          ),
    .add_sub   (flags_in.add_sub),
    .result_out(mant_sum        )
);

// Exact zero determine
assign x_eq_y                = mant_x == mant_y;
assign flags_out.exact_zero  = !flags_in.result_pass &&
    flags_in.add_sub && x_eq_y;

// Forward the encoded bypass mantissa and exponent.
always_comb begin : bypass_fwd
    mant_sum_out = flags_in.result_pass ? mant_sum_t'(c_mant_align_in) : mant_sum;
    exp_base_out = exp_base_in;
end : bypass_fwd

// Pass other flags
assign flags_out.result_pass = flags_in.result_pass;
assign flags_out.result_sign = (flags_in.result_pass || c_large) ? flags_in.c_sign : flags_in.prod_sign;

endmodule : hsf3_aalu
