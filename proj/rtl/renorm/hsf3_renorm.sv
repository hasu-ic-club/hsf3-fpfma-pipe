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
// RELEASE VERSION: 0.2
// VERSION DESCRIPTION: Coarse-fine refine shifter version
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/23    First Edition
// 0.2        O. Tsusaki    2026/11/24    Enable coarse-fine refine shifter
//                                        to optimize area and performance
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
    `LP_MODULE int ALIGNED_WIDTH   = FULL_PROD_WIDTH + 2,
    `LP_MODULE int SUM_WIDTH       = ALIGNED_WIDTH + 1,
    `LP_MODULE int EXT_MANT_WIDTH  = MANTISSA_WIDTH + 1,
    `LP_MODULE int WINDOW_WIDTH    = EXT_MANT_WIDTH + RENORM_WINDOW_EXTRA_BITS
)
(
    // Input adder result
    input  logic                    [SUM_WIDTH - 1:0]          mant_sum_in,
    input  logic             signed [REXP_SUM_WIDTH - 1:0]     exp_base_in,

    input  aalu_flags_s                                        flags_in,

    // Renormalization result output
    output logic                    [WINDOW_WIDTH - 1:0]       coarse_window_out,
    output renorm_fine_off_t                                   fine_offset_out,
    output logic                                               coarse_sticky_out,
    output logic             signed [REXP_SUM_WIDTH - 1:0]     exp_rnd_out,

    output renorm_flags_s                                      flags_out
);

localparam        int FULL_SUM_LZC_WIDTH = $clog2(SUM_WIDTH + 1);
localparam        int RENORM_CALC_WIDTH  = REXP_SUM_WIDTH + 1;
localparam        int HIDDEN_OFFSET      = SUM_WIDTH - 1 - FULL_PROD_WIDTH;

typedef logic        [FULL_SUM_LZC_WIDTH - 1:0] sum_lzc_t;
typedef logic        [WINDOW_WIDTH - 1:0]       renorm_window_t;
typedef logic signed [RENORM_CALC_WIDTH - 1:0]  renorm_calc_t;

// Leading zero of summary mantissa
sum_lzc_t             mant_sum_lzc;

// Renormalization scaling
renorm_calc_t         exp_base_calc;
renorm_calc_t         lzc_calc;
renorm_calc_t         lzc_limit;
renorm_calc_t         scale;
renorm_calc_t         exp_rnd_calc;
renorm_calc_t         window_hi;
renorm_window_t       coarse_window;
renorm_fine_off_t     fine_offset;
logic                 coarse_sticky;

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
assign lzc_limit             = exp_base_calc + renorm_calc_t'(HIDDEN_OFFSET - 1);
assign scale                 = (lzc_limit < lzc_calc) ? lzc_limit : lzc_calc;
assign exp_rnd_calc          = exp_base_calc - scale + renorm_calc_t'(HIDDEN_OFFSET);
assign window_hi             = renorm_calc_t'(SUM_WIDTH - 1) - scale;

// Coarse window selection (mutliple-bit group) and
// do fine renormalization in the next stage.
hsf3_renorm_coarse_sft #(
    .MANTISSA_WIDTH (MANTISSA_WIDTH   ),
    .WINDOW_HI_WIDTH(RENORM_CALC_WIDTH)
)
renorm_coarse_sft_inst
(
    .mant_sum_in      (mant_sum_in  ),
    .window_hi_in     (window_hi    ),
    .coarse_window_out(coarse_window),
    .fine_offset_out  (fine_offset  ),
    .coarse_sticky_out(coarse_sticky)
);

// Output selection
always_comb begin : out_mux
    if (flags_in.result_pass) begin
        // Place the bypass mantissa and zero G/R at fine offset zero.
        coarse_window_out = renorm_window_t'({1'b1, mant_sum_in[MANTISSA_WIDTH - 1:0], 2'b00});
        fine_offset_out   = '0;
        coarse_sticky_out = 1'b0;
        exp_rnd_out       = exp_base_in;
    end
    else if (flags_in.exact_zero) begin
        coarse_window_out = '0;
        fine_offset_out   = '0;
        coarse_sticky_out = 1'b0;
        exp_rnd_out       = '0;
    end
    else begin
        coarse_window_out = coarse_window;
        fine_offset_out   = fine_offset;
        coarse_sticky_out = coarse_sticky;
        exp_rnd_out       = exp_rnd_calc[REXP_SUM_WIDTH - 1:0];
    end
end : out_mux

// Pass the flags
assign flags_out.exact_zero  = flags_in.exact_zero;
assign flags_out.result_pass = flags_in.result_pass;
assign flags_out.result_sign = flags_in.result_sign;

endmodule : hsf3_renorm
