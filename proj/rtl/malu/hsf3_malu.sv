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
// FILE NAME: hsf3_malu.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.2
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/23    First Edition
// 0.2        O. Tsusaki    2026/11/24    Optimized pipeline adjusted this
//                                        stage to second stage
//-------------------------------------------------------------------------
// PURPOSE: Multiplier arithmetic logic unit (stage) for pipelined FMA
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

// Multiplier arithmetic logic unit (stage) for pipelined FMA
module hsf3_malu
import hsf3_typedef_pkg::*;
#(
    parameter int             EXPONENT_WIDTH = 8,
    parameter int             MANTISSA_WIDTH = 23,
    `LP_MODULE int LZC_WIDTH        = $clog2(MANTISSA_WIDTH + 1 + 1),
    `LP_MODULE int REXP_WIDTH       = hs_math_basic_pkg::max(EXPONENT_WIDTH, LZC_WIDTH) + 1,
    `LP_MODULE int REXP_SUM_WIDTH   = REXP_WIDTH + 2,
    `LP_MODULE int FULL_PROD_WIDTH  = MANTISSA_WIDTH * 2 + 2,
    `LP_MODULE int ALIGNED_WIDTH    = FULL_PROD_WIDTH + 2,
    `LP_MODULE int SFT_AMOUNT_WIDTH = $clog2(ALIGNED_WIDTH + 1)
)
(
    // Pre-normalized operands and alignment control
    input  logic                  [MANTISSA_WIDTH:0]        mant_a_in,
    input  logic                  [MANTISSA_WIDTH:0]        mant_b_in,
    input  logic                  [MANTISSA_WIDTH:0]        c_mant_in,
    input  logic           signed [REXP_SUM_WIDTH - 1:0]    exp_base_in,
    input  logic                  [SFT_AMOUNT_WIDTH - 1:0]  sft_amount_in,
    input  logic                                            shift_prod_in,
    input  logic                                            cmp_mant_en_in,
    input  preproc_flags_s                                  flags_in,

    // Raw product and aligned C for AALU
    output logic                  [FULL_PROD_WIDTH - 1:0]   prod_mant_out,
    output logic                  [ALIGNED_WIDTH - 1:0]     c_mant_align_out,
    output logic           signed [REXP_SUM_WIDTH - 1:0]    exp_base_out,
    output logic                  [SFT_AMOUNT_WIDTH - 1:0]  sft_amount_out,
    output logic                                            shift_prod_out,
    output logic                                            cmp_mant_en_out,
    output malu_flags_s                                     flags_out
);

`HSF3_MANTISSA_ALIGNED_TYPEDEF(MANTISSA_WIDTH);

typedef logic [ALIGNED_WIDTH - 3:0] mant_rshift_t;

mant_aligned_t                             c_mant;
logic          [SFT_AMOUNT_WIDTH - 1:0]    c_sft_amount;
mant_rshift_t                              c_mant_shifted_hi;
grs_s                                      c_sft_grs_out;

// Core multiplier for A and B's mantissa
hsf3_cmul #(
    .DATA_WIDTH(MANTISSA_WIDTH + 1)
)
cmul_inst
(
    .op_a_in   (mant_a_in    ),
    .op_b_in   (mant_b_in    ),
    .result_out(prod_mant_out)
);

// Align C in parallel with the multiplication when its exponent is smaller.
assign c_mant                = {1'b0, c_mant_in, {(MANTISSA_WIDTH + 2){1'b0}}};
assign c_sft_amount          = shift_prod_in ? '0 : sft_amount_in;

hsf3_grs_rshift #(
    .DATA_WIDTH      ($bits(mant_rshift_t)),
    .SFT_AMOUNT_WIDTH(SFT_AMOUNT_WIDTH    )
)
c_align_rshift_inst (
    .grs_in  ('0                         ),
    .data_in (c_mant[ALIGNED_WIDTH - 1:2]),
    .sft_in  (c_sft_amount               ),
    .data_out(c_mant_shifted_hi          ),
    .grs_out (c_sft_grs_out              )
);

// Keep bypass mantissa bits in the low part of the C datapath.
assign c_mant_align_out      = flags_in.result_pass ?
    mant_aligned_t'(c_mant_in[MANTISSA_WIDTH - 1:0]) :
    {c_mant_shifted_hi, c_sft_grs_out.guard, c_sft_grs_out.round | c_sft_grs_out.sticky};

always_comb begin : pass_fields
    exp_base_out    = exp_base_in;
    sft_amount_out  = sft_amount_in;
    shift_prod_out  = shift_prod_in;
    cmp_mant_en_out = cmp_mant_en_in;
end : pass_fields

assign flags_out.prod_sign   = flags_in.prod_sign;
assign flags_out.c_sign      = flags_in.c_sign;
assign flags_out.add_sub     = !flags_in.result_pass && !flags_in.c_zero &&
    (flags_in.prod_sign ^ flags_in.c_sign);
assign flags_out.result_pass = flags_in.result_pass;

endmodule : hsf3_malu
