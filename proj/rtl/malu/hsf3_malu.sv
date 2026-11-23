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
// RELEASE VERSION: 0.1
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/23    First Edition
//-------------------------------------------------------------------------
// PURPOSE: Multiplier arithmetic logic unit (stage) for pipelined FMA
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME  RANGE           DESCRIPTION             DEFAULT VALUE
// EXPONENT_WIDTH  1-32            Exponent bit width      8
// MANTISSA_WIDTH  1-128           Mantissa bit width      23
// FP_ROUND_MOD    fp_round_mode_s Floating point rounding FP_ROUND_MODE_TIES_TO_EVEN
//                                 mode
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
    parameter fp_round_mode_s FP_ROUND_MODE  = FP_ROUND_MODE_TIES_TO_EVEN,
    `LP_MODULE int OP_WIDTH        = 1 + EXPONENT_WIDTH + MANTISSA_WIDTH,
    `LP_MODULE int LZC_WIDTH       = $clog2(MANTISSA_WIDTH + 1 + 1),
    `LP_MODULE int REXP_WIDTH      = hs_math_basic_pkg::max(EXPONENT_WIDTH, LZC_WIDTH) + 1,
    `LP_MODULE int REXP_SUM_WIDTH  = REXP_WIDTH + 2,
    `LP_MODULE int FULL_PROD_WIDTH = MANTISSA_WIDTH * 2 + 2
)
(
    // Input operands
    input  logic               [OP_WIDTH - 1:0]           op_a_in,
    input  logic               [OP_WIDTH - 1:0]           op_b_in,
    input  logic               [OP_WIDTH - 1:0]           op_c_in,

    // Full product and addend payload for postmul
    output logic               [FULL_PROD_WIDTH - 1:0]    prod_mant_out,
    output logic        signed [REXP_SUM_WIDTH - 1:0]     prod_exp_out,
    output logic               [MANTISSA_WIDTH:0]         c_mant_out,
    output logic        signed [REXP_WIDTH - 1:0]         c_exp_out,

    output malu_flags_s                                   flags_out
);

`HSF3_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);
`HSF3_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);

typedef logic [LZC_WIDTH - 1:0] lzc_t;
typedef logic signed [REXP_WIDTH - 1:0] rexp_t;

// FP format structure
fp_s               op_a_fp;
fp_s               op_b_fp;
fp_s               op_c_fp;
fp_s               pass_result;

// Extended mantissa
fp_ext_mant_t      ext_mant_a;
fp_ext_mant_t      ext_mant_b;
fp_ext_mant_t      ext_mant_c;

// Operand and product classification
logic              op_a_denorm;
logic              op_b_denorm;
logic              op_c_denorm;
logic              op_c_nan;
logic              op_c_inf;
logic              op_c_zero;
logic              prod_nan;
logic              prod_inf;
logic              prod_zero;
logic              prod_sign;
logic              result_pass;

// LZC of mantissa of de-normalized numbers
lzc_t              lzc_mant_a;
lzc_t              lzc_mant_b;
lzc_t              lzc_mant_c;

// Force normalized (extended exponent) mantissa
fp_ext_mant_t      frcn_mant_a;
fp_ext_mant_t      frcn_mant_b;
fp_ext_mant_t      frcn_mant_c;

// Real exponent
rexp_t             rexp_a;
rexp_t             rexp_b;
rexp_t             rexp_c;

// Assign input operators to FP format
assign op_a_fp                        = fp_s'(op_a_in);
assign op_b_fp                        = fp_s'(op_b_in);
assign op_c_fp                        = fp_s'(op_c_in);

// Classify A and B and resolve special values of their product.
hsf3_mul_sp_result_gen #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
sp_result_gen_inst
(
    .op_a_in    (op_a_in    ),
    .op_b_in    (op_b_in    ),
    .prod_nan   (prod_nan   ),
    .prod_inf   (prod_inf   ),
    .prod_zero  (prod_zero  ),
    .op_a_denorm(op_a_denorm),
    .op_b_denorm(op_b_denorm),
    .prod_sign  (prod_sign  )
);

hsf3_bvd #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
bvd_op_c_inst
(
    .op_in    (op_c_in    ),
    .is_nan   (op_c_nan   ),
    .is_inf   (op_c_inf   ),
    .is_denorm(op_c_denorm),
    .is_zero  (op_c_zero  )
);

hsf3_fma_sp_result_gen #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH),
    .FP_ROUND_MODE (FP_ROUND_MODE )
)
fma_sp_result_gen_inst
(
    .prod_nan   (prod_nan       ),
    .prod_inf   (prod_inf       ),
    .prod_zero  (prod_zero      ),
    .prod_sign  (prod_sign      ),
    .op_c_in    (op_c_in        ),
    .c_nan      (op_c_nan       ),
    .c_inf      (op_c_inf       ),
    .c_zero     (op_c_zero      ),
    .result_pass(result_pass    ),
    .pass_result(pass_result    )
);

// On a bypass, carry the encoded result in the existing C fields.
assign c_mant_out                     = result_pass ? {1'b0, pass_result.mantissa} : frcn_mant_c;
assign c_exp_out                      = result_pass ? rexp_t'({1'b0, pass_result.exp}) : rexp_c;
assign flags_out.prod_sign            = prod_sign;
assign flags_out.c_sign               = result_pass ? pass_result.sign : op_c_fp.sign;
assign flags_out.c_zero               = op_c_zero;
assign flags_out.result_pass          = result_pass;

// A zero exponent field has no hidden bit, including for signed zero.
assign ext_mant_a                     = {|op_a_fp.exp, op_a_fp.mantissa};
assign ext_mant_b                     = {|op_b_fp.exp, op_b_fp.mantissa};
assign ext_mant_c                     = {|op_c_fp.exp, op_c_fp.mantissa};

// Leading zero counter for de-normalized numbers
hsf3_hblzc
#(
    .DATA_WIDTH     ($bits(fp_ext_mant_t)),
    .LZC_BLOCK_WIDTH(4                   )
)
lzc_mant_a_inst
(
    .din(ext_mant_a),
    .lzc(lzc_mant_a)
);

hsf3_hblzc
#(
    .DATA_WIDTH     ($bits(fp_ext_mant_t)),
    .LZC_BLOCK_WIDTH(4                   )
)
lzc_mant_b_inst
(
    .din(ext_mant_b),
    .lzc(lzc_mant_b)
);

hsf3_hblzc
#(
    .DATA_WIDTH     ($bits(fp_ext_mant_t)),
    .LZC_BLOCK_WIDTH(4                   )
)
lzc_mant_c_inst
(
    .din(ext_mant_c),
    .lzc(lzc_mant_c)
);

// Force normalized mantissa
// For numbers already normalized, we pass the extend mantissa
// For denormalized numbers, we pass left shifted mantissa which
//     set the MSB of mantissa to 1
hsf3_lshift
#(
    .DATA_WIDTH      ($bits(fp_ext_mant_t)),
    .SFT_AMOUNT_WIDTH($bits(lzc_t)        )
)
denorm_mant_a_lsft_inst
(
    .data_in (ext_mant_a ),
    .sft_in  (lzc_mant_a ),
    .data_out(frcn_mant_a)
);

hsf3_lshift
#(
    .DATA_WIDTH      ($bits(fp_ext_mant_t)),
    .SFT_AMOUNT_WIDTH($bits(lzc_t)        )
)
denorm_mant_b_lsft_inst
(
    .data_in (ext_mant_b ),
    .sft_in  (lzc_mant_b ),
    .data_out(frcn_mant_b)
);

hsf3_lshift
#(
    .DATA_WIDTH      ($bits(fp_ext_mant_t)),
    .SFT_AMOUNT_WIDTH($bits(lzc_t)        )
)
denorm_mant_c_lsft_inst
(
    .data_in (ext_mant_c ),
    .sft_in  (lzc_mant_c ),
    .data_out(frcn_mant_c)
);

// Core multiplier for A and B's mantissa
hsf3_cmul #(
    .DATA_WIDTH($bits(fp_ext_mant_t))
)
cmul_inst
(
    .op_a_in   (frcn_mant_a  ),
    .op_b_in   (frcn_mant_b  ),
    .result_out(prod_mant_out)
);

// Exponent extract
hsf3_exp_extract
#(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .LZC_WIDTH     (LZC_WIDTH     )
)
exp_a_extract_inst
(
    .exp_in   (op_a_fp.exp),
    .denorm_in(op_a_denorm),
    .lzc_in   (lzc_mant_a ),
    .real_exp (rexp_a     )
);

hsf3_exp_extract
#(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .LZC_WIDTH     (LZC_WIDTH     )
)
exp_b_extract_inst
(
    .exp_in   (op_b_fp.exp),
    .denorm_in(op_b_denorm),
    .lzc_in   (lzc_mant_b ),
    .real_exp (rexp_b     )
);

hsf3_exp_extract
#(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .LZC_WIDTH     (LZC_WIDTH     )
)
exp_c_extract_inst
(
    .exp_in   (op_c_fp.exp),
    .denorm_in(op_c_denorm),
    .lzc_in   (lzc_mant_c ),
    .real_exp (rexp_c     )
);

// Exponent summary
hsf3_exp_sum #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .REXP_WIDTH    (REXP_WIDTH    )
)
rexp_sum_inst
(
    .rexp_a_in(rexp_a      ),
    .rexp_b_in(rexp_b      ),
    .prod_exp (prod_exp_out)
);

endmodule : hsf3_malu
