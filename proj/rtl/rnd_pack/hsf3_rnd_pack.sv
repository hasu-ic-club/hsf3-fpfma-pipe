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
// FILE NAME: hsf3_rnd_pack.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/24    First Edition
//
//-------------------------------------------------------------------------
// PURPOSE: Rounding and repack unit (stage) for pipelined FMA
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME  RANGE           DESCRIPTION             DEFAULT VALUE
// EXPONENT_WIDTH  1-32            Exponent bit width      8
// MANTISSA_WIDTH  1-128           Mantissa bit width      23
// FP_ROUND_MODE   fp_round_mode_s Floating point rounding FP_ROUND_MODE_TIES_TO_EVEN
//                                 mode
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"
`include "hsf3_macros.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Rounding and repack unit (stage) for pipelined FMA
module hsf3_rnd_pack
import hsf3_typedef_pkg::*;
#(
    parameter int             EXPONENT_WIDTH = 8,
    parameter int             MANTISSA_WIDTH = 23,
    parameter fp_round_mode_s FP_ROUND_MODE  = FP_ROUND_MODE_TIES_TO_EVEN,
    `LP_MODULE int OP_WIDTH        = 1 + EXPONENT_WIDTH + MANTISSA_WIDTH,
    `LP_MODULE int LZC_WIDTH       = $clog2(MANTISSA_WIDTH + 1 + 1),
    `LP_MODULE int REXP_WIDTH      = hs_math_basic_pkg::max(EXPONENT_WIDTH, LZC_WIDTH) + 1,
    `LP_MODULE int REXP_SUM_WIDTH  = REXP_WIDTH + 2
)
(
    // Input renormalization result
    input  logic                    [MANTISSA_WIDTH + 1 - 1:0] mant_pre_rnd_in,
    input  logic             signed [REXP_SUM_WIDTH - 1:0]     exp_rnd_in,
    input  grs_s                                               grs_in,

    input  renorm_flags_s                                      flags_in,

    output logic                    [OP_WIDTH - 1:0]           result_out,
    output exception_flags_s                                   exception_out
);

`HSF3_MANTISSA_TYPEDEF(MANTISSA_WIDTH);
`HSF3_EXPONENT_TYPEDEF(EXPONENT_WIDTH);

`HSF3_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);

`HSF3_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);

typedef logic signed [REXP_SUM_WIDTH - 1:0] srexp_t;

localparam fp_exp_t INF_EXPONENT        = '1;
localparam fp_exp_t MAX_FINITE_EXPONENT = INF_EXPONENT - fp_exp_t'(1);

// GRS rounding output
fp_ext_mant_t rnd_mant;
logic         rnd_cout;

// Rounding and renormalization result
srexp_t       rnd_renorm_exp;
fp_ext_mant_t rnd_renorm_mant;
logic         hidden_bit;
logic         finite_overflow;
logic         overflow_to_inf;

// Output result
fp_s          fp_out;

// GRS rounding
hsf3_grs_round #(
    .MANTISSA_WIDTH(MANTISSA_WIDTH),
    .FP_ROUND_MODE (FP_ROUND_MODE )
)
grs_round_inst
(
    .sign_in     (flags_in.result_sign),
    .ext_mant_in (mant_pre_rnd_in     ),
    .grs_in      (grs_in              ),
    .rnd_mant_out(rnd_mant            ),
    .rnd_cout    (rnd_cout            )
);

// Determine the rounded renormalization exponent and mantissa
always_comb begin : rnd_cout_sel
    if (rnd_cout) begin
        rnd_renorm_exp  = (exp_rnd_in + srexp_t'(1));
        rnd_renorm_mant = {rnd_cout, rnd_mant[1 +: MANTISSA_WIDTH]};
    end
    else begin
        rnd_renorm_exp  = exp_rnd_in;
        rnd_renorm_mant = rnd_mant;
    end
end : rnd_cout_sel

// Hidden bit
assign hidden_bit = rnd_renorm_mant[MANTISSA_WIDTH];

// Compare the full exponent before truncating it for packing.
assign finite_overflow = hidden_bit &&
    (rnd_renorm_exp > srexp_t'({1'b0, MAX_FINITE_EXPONENT}));
assign overflow_to_inf = (FP_ROUND_MODE == FP_ROUND_MODE_TIES_TO_EVEN) ||
    ((FP_ROUND_MODE == FP_ROUND_MODE_TOWARD_POSITIVE) && !flags_in.result_sign) ||
    ((FP_ROUND_MODE == FP_ROUND_MODE_TOWARD_NEGATIVE) && flags_in.result_sign);

// Output selection
always_comb begin : out_mux
    if (flags_in.result_pass) begin
        fp_out.sign     = flags_in.result_sign;
        fp_out.exp      = exp_rnd_in[EXPONENT_WIDTH - 1:0];
        fp_out.mantissa = mant_pre_rnd_in[MANTISSA_WIDTH - 1:0];
    end
    else if (flags_in.exact_zero) begin
        fp_out.sign     = (FP_ROUND_MODE == FP_ROUND_MODE_TOWARD_NEGATIVE);
        fp_out.exp      = '0;
        fp_out.mantissa = '0;
    end
    else if (finite_overflow) begin
        fp_out.sign     = flags_in.result_sign;
        fp_out.exp      = overflow_to_inf ? INF_EXPONENT : MAX_FINITE_EXPONENT;
        fp_out.mantissa = overflow_to_inf ? '0 : '1;
    end
    else begin
        fp_out.sign     = flags_in.result_sign;
        fp_out.exp      = hidden_bit ? rnd_renorm_exp[EXPONENT_WIDTH - 1:0] : '0;
        fp_out.mantissa = rnd_renorm_mant[MANTISSA_WIDTH - 1:0];
    end
end : out_mux

assign result_out = fp_out;

// Classify the selected result, including bypasses and overflow results.
hsf3_bvd #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
result_bvd_inst
(
    .op_in    (result_out       ),
    .is_nan   (exception_out.nan),
    .is_inf   (exception_out.inf),
    .is_denorm(                 ),
    .is_zero  (                 )
);

endmodule : hsf3_rnd_pack
