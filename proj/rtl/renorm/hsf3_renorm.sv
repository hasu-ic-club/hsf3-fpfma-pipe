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
// FILE NAME: hsf3_renorm.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/23    First Edition
//
//-------------------------------------------------------------------------
// PURPOSE: Result renormalization unit (stage) for pipelined FMA
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

// Result renormalization unit (stage) for pipelined FMA
module hsf3_renorm
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
    // Input adder result
    input  logic                 [SUM_WIDTH - 1:0]          mant_sum_in,
    input  logic          signed [REXP_SUM_WIDTH - 1:0]     exp_base_in,

    input  aalu_flags_s                                     flags_in,

    // Renormalization result output
    output logic                 [MANTISSA_WIDTH + 1 - 1:0] mant_pre_rnd_out,
    output logic          signed [REXP_SUM_WIDTH - 1:0]     exp_rnd_out,
    output grs_s                                            grs_out,

    output renorm_flags_s                                   flags_out
);

`HSF3_MANTISSA_TYPEDEF(MANTISSA_WIDTH);
`HSF3_EXPONENT_TYPEDEF(EXPONENT_WIDTH);
`HSF3_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);

`HSF3_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);
`HSF3_MANTISSA_ALIGNED_TYPEDEF(MANTISSA_WIDTH);

localparam    int FULL_SUM_LZC_WIDTH = $clog2(SUM_WIDTH + 1);
typedef logic [FULL_SUM_LZC_WIDTH - 1:0] sum_lzc_t;

localparam    int PAD_BITS           = MANTISSA_WIDTH + 3;
localparam    int SFT_DATA_WIDTH     = SUM_WIDTH + PAD_BITS - 2;
localparam    int RENORM_CALC_WIDTH  = REXP_SUM_WIDTH + 1;

typedef logic [SFT_DATA_WIDTH - 1:0] mant_sft_t;
typedef logic signed [RENORM_CALC_WIDTH - 1:0] renorm_calc_t;
typedef logic [RENORM_CALC_WIDTH - 1:0] sft_amount_t;

// Leading zero of summary mantissa
sum_lzc_t         mant_sum_lzc;

// Renormalization scaling
renorm_calc_t     exp_base_calc;
renorm_calc_t     lzc_calc;
renorm_calc_t     scale;
renorm_calc_t     exp_rnd_calc;
sft_amount_t      sft_amount;
mant_sft_t        mant_rsft_pad;
mant_sft_t        rshift_data;
grs_s             rshift_grs;

// Leading zero counter (LZC) for result summary mantissa
hsf3_hblzc #(
    .DATA_WIDTH     (SUM_WIDTH),
    .LZC_BLOCK_WIDTH(4        )
)
lzc_inst
(
    .din(mant_sum_in ),
    .lzc(mant_sum_lzc)
);

// Renormalization scaling
assign exp_base_calc         = renorm_calc_t'(exp_base_in);
assign lzc_calc              = renorm_calc_t'({1'b0, mant_sum_lzc});
assign scale                 = (exp_base_calc < lzc_calc) ? exp_base_calc : lzc_calc;
assign exp_rnd_calc          = exp_base_calc - scale + renorm_calc_t'(1);

assign sft_amount            = (flags_in.result_pass || flags_in.exact_zero) ?
    '0 :
    $unsigned(renorm_calc_t'(SUM_WIDTH - 1) - scale);

// Right shift mantissa to renormalize
assign mant_rsft_pad         = {mant_sum_in, {(PAD_BITS - 2){1'b0}}};

hsf3_grs_rshift #(
    .DATA_WIDTH      (SFT_DATA_WIDTH   ),
    .SFT_AMOUNT_WIDTH(RENORM_CALC_WIDTH)
)
renorm_rshift_inst
(
    .grs_in  ('0           ),
    .data_in (mant_rsft_pad),
    .sft_in  (sft_amount   ),
    .data_out(rshift_data  ),
    .grs_out (rshift_grs   )
);

// Output selection
always_comb begin : out_mux
    if (flags_in.result_pass) begin
        // Pass the lower bits to result when bypass
        mant_pre_rnd_out = mant_sum_in[MANTISSA_WIDTH - 1:0];
        exp_rnd_out      = exp_base_in;
        grs_out          = '0;
    end
    else if (flags_in.exact_zero) begin
        mant_pre_rnd_out = '0;
        exp_rnd_out      = '0;
        grs_out          = '0;
    end
    else begin
        mant_pre_rnd_out = rshift_data[MANTISSA_WIDTH + 1:1];
        exp_rnd_out      = exp_rnd_calc[REXP_SUM_WIDTH - 1:0];
        grs_out.guard    = rshift_data[0];
        grs_out.round    = rshift_grs.guard;
        grs_out.sticky   = rshift_grs.round | rshift_grs.sticky;
    end
end : out_mux

// Pass the flags
assign flags_out.exact_zero  = flags_in.exact_zero;
assign flags_out.result_pass = flags_in.result_pass;
assign flags_out.result_sign = flags_in.result_sign;

endmodule : hsf3_renorm
