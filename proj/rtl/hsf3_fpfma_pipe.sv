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
// FILE NAME: hsf3_fpfma_pipe.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.2
// VERSION DESCRIPTION: Multiplier Pipeline Optimized Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/23    First Edition
// 0.2        O. Tsusaki    2026/11/24    Multiplier Pipeline Optimized Edition
//
//-------------------------------------------------------------------------
// PURPOSE: Pipelined floating-point fused multipy-adder (FMA)
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

// Pipelined floating-point fused multipy-adder (FMA)
module hsf3_fpfma_pipe
import hs_ifr_misc_typedefs_pkg::*;
import hsf3_typedef_pkg::*;
#(
    parameter int             EXPONENT_WIDTH = 8,
    parameter int             MANTISSA_WIDTH = 23,
    parameter fp_round_mode_s FP_ROUND_MODE  = FP_ROUND_MODE_TIES_TO_EVEN,
    `LP_MODULE int OP_WIDTH = 1 + EXPONENT_WIDTH + MANTISSA_WIDTH
)
(
    // Clock & reset
    input  logic                  clk,
    input  logic                  aresetn,

    // Operators input (handshake)
    input  logic [OP_WIDTH - 1:0] op_a_in,
    input  logic [OP_WIDTH - 1:0] op_b_in,
    input  logic [OP_WIDTH - 1:0] op_c_in,
    input  logic                  op_valid,
    output logic                  op_ready,

    // Result output (handshake)
    output logic [OP_WIDTH - 1:0] result_out,
    output logic                  result_valid,
    input  logic                  result_ready,

    // Exception output (sync with result)
    output logic                  exception_out,    // Indicate the result has exception value (NaN/infinite)
    output logic                  nan_out,          // Indicate the result is NaN
    output logic                  inf_out           // Indicate the result is infinite
);

`HSF3_MANTISSA_TYPEDEF(MANTISSA_WIDTH);
`HSF3_EXPONENT_TYPEDEF(EXPONENT_WIDTH);

`HSF3_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);
`HSF3_PROD_MANT_TYPEDEF(MANTISSA_WIDTH);
`HSF3_MANTISSA_ALIGNED_TYPEDEF(MANTISSA_WIDTH);

localparam           int LZC_WIDTH                = $clog2(MANTISSA_WIDTH + 1 + 1);
localparam           int REXP_WIDTH               = hs_math_basic_pkg::max(EXPONENT_WIDTH, LZC_WIDTH) + 1;
localparam           int REXP_SUM_WIDTH           = REXP_WIDTH + 2;
localparam           int SUM_WIDTH                = $bits(mant_aligned_t) + 1;
localparam           int SFT_AMOUNT_WIDTH         = $clog2($bits(mant_aligned_t) + 1);

typedef logic signed [REXP_SUM_WIDTH - 1:0] prod_rexp_t;
typedef logic        [SUM_WIDTH - 1:0]      mant_sum_t;

// Packed structures for inter-stage data path
typedef struct packed
{
    fp_ext_mant_t                  mant_a;
    fp_ext_mant_t                  mant_b;
    fp_ext_mant_t                  c_mant;
    prod_rexp_t                    exp_base;
    logic [SFT_AMOUNT_WIDTH - 1:0] sft_amount;
    logic                          shift_prod;
    logic                          cmp_mant_en;
    preproc_flags_s                flags;
} preproc_malu_dp_s;

typedef struct packed
{
    fp_prod_mant_t                 mant_prod;
    mant_aligned_t                 c_mant_align;
    prod_rexp_t                    exp_base;
    logic [SFT_AMOUNT_WIDTH - 1:0] sft_amount;
    logic                          shift_prod;
    logic                          cmp_mant_en;
    malu_flags_s                   flags;
} malu_aalu_dp_s;

typedef struct packed
{
    mant_sum_t   mant_sum;
    prod_rexp_t  exp_base;
    aalu_flags_s flags;
} aalu_renorm_dp_s;

typedef struct packed
{
    fp_ext_mant_t  mant_pre_rnd;
    prod_rexp_t    exp_rnd;
    grs_s          grs;
    renorm_flags_s flags;
} renorm_rnd_pack_dp_s;

typedef struct packed
{
    logic [OP_WIDTH - 1:0] result;
    exception_flags_s      exception_flags;
} rnd_pack_out_dp_s;

// Inter-stage handshake
logic                    preproc_malu_hs_valid;
logic                    preproc_malu_hs_ready;
logic                    malu_aalu_hs_valid;
logic                    malu_aalu_hs_ready;
logic                    aalu_renorm_hs_valid;
logic                    aalu_renorm_hs_ready;
logic                    renorm_rnd_pack_hs_valid;
logic                    renorm_rnd_pack_hs_ready;

// Inter-stage data path
preproc_malu_dp_s        preproc_out;
preproc_malu_dp_s        malu_in;

malu_aalu_dp_s           malu_out;
malu_aalu_dp_s           aalu_in;

aalu_renorm_dp_s         aalu_out;
aalu_renorm_dp_s         renorm_in;

renorm_rnd_pack_dp_s     renorm_out;
renorm_rnd_pack_dp_s     rnd_pack_in;

rnd_pack_out_dp_s        rnd_pack_out;
rnd_pack_out_dp_s        output_dp;

// Stage I: Operand preprocessing
hsf3_preproc #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH),
    .FP_ROUND_MODE (FP_ROUND_MODE )
)
preproc_inst (
    .op_a_in        (op_a_in                ),
    .op_b_in        (op_b_in                ),
    .op_c_in        (op_c_in                ),
    .mant_a_out     (preproc_out.mant_a     ),
    .mant_b_out     (preproc_out.mant_b     ),
    .c_mant_out     (preproc_out.c_mant     ),
    .exp_base_out   (preproc_out.exp_base   ),
    .sft_amount_out (preproc_out.sft_amount ),
    .shift_prod_out (preproc_out.shift_prod ),
    .cmp_mant_en_out(preproc_out.cmp_mant_en),
    .flags_out      (preproc_out.flags      )
);

// Pipeline slice between preproc and MALU
hs_dpath_skid_buffer #(
    .FULL_THROUGHPUT(BOOL_TRUE               ),
    .CTRL_PIPE      (BOOL_FALSE              ),
    .DATA_PIPE      (BOOL_TRUE               ),
    .STROBE_UNIT    ($bits(preproc_malu_dp_s)),
    .DATA_TYPE      (preproc_malu_dp_s       )
)
preproc_malu_pipe_inst
(
    .clk       (clk                  ),
    .aresetn   (aresetn              ),
    .in_data   (preproc_out          ),
    .in_valid  (op_valid             ),
    .in_last   ('0                   ),
    .in_ready  (op_ready             ),
    .in_strobe ('0                   ),
    .out_data  (malu_in              ),
    .out_valid (preproc_malu_hs_valid),
    .out_last  (                     ),
    .out_ready (preproc_malu_hs_ready),
    .out_strobe(                     )
);

// Stage II: Multiply and align C
hsf3_malu #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
malu_inst (
    .mant_a_in       (malu_in.mant_a       ),
    .mant_b_in       (malu_in.mant_b       ),
    .c_mant_in       (malu_in.c_mant       ),
    .exp_base_in     (malu_in.exp_base     ),
    .sft_amount_in   (malu_in.sft_amount   ),
    .shift_prod_in   (malu_in.shift_prod   ),
    .cmp_mant_en_in  (malu_in.cmp_mant_en  ),
    .flags_in        (malu_in.flags        ),
    .prod_mant_out   (malu_out.mant_prod   ),
    .c_mant_align_out(malu_out.c_mant_align),
    .exp_base_out    (malu_out.exp_base    ),
    .sft_amount_out  (malu_out.sft_amount  ),
    .shift_prod_out  (malu_out.shift_prod  ),
    .cmp_mant_en_out (malu_out.cmp_mant_en ),
    .flags_out       (malu_out.flags       )
);

// Pipeline slice between MALU and AALU
hs_dpath_skid_buffer #(
    .FULL_THROUGHPUT(BOOL_TRUE            ),
    .CTRL_PIPE      (BOOL_FALSE           ),
    .DATA_PIPE      (BOOL_TRUE            ),
    .STROBE_UNIT    ($bits(malu_aalu_dp_s)),
    .DATA_TYPE      (malu_aalu_dp_s       )
)
malu_aalu_pipe_inst
(
    .clk       (clk                  ),
    .aresetn   (aresetn              ),
    .in_data   (malu_out             ),
    .in_valid  (preproc_malu_hs_valid),
    .in_last   ('0                   ),
    .in_ready  (preproc_malu_hs_ready),
    .in_strobe ('0                   ),
    .out_data  (aalu_in              ),
    .out_valid (malu_aalu_hs_valid   ),
    .out_last  (                     ),
    .out_ready (malu_aalu_hs_ready   ),
    .out_strobe(                     )
);

// Stage III: Align the product and add or subtract
hsf3_aalu #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
aalu_inst (
    .prod_mant_in   (aalu_in.mant_prod   ),
    .c_mant_align_in(aalu_in.c_mant_align),
    .exp_base_in    (aalu_in.exp_base    ),
    .sft_amount_in  (aalu_in.sft_amount  ),
    .shift_prod_in  (aalu_in.shift_prod  ),
    .cmp_mant_en_in (aalu_in.cmp_mant_en ),
    .flags_in       (aalu_in.flags       ),
    .mant_sum_out   (aalu_out.mant_sum   ),
    .exp_base_out   (aalu_out.exp_base   ),
    .flags_out      (aalu_out.flags      )
);

// Pipeline slice between AALU and renorm
hs_dpath_skid_buffer #(
    .FULL_THROUGHPUT(BOOL_TRUE              ),
    .CTRL_PIPE      (BOOL_FALSE             ),
    .DATA_PIPE      (BOOL_TRUE              ),
    .STROBE_UNIT    ($bits(aalu_renorm_dp_s)),
    .DATA_TYPE      (aalu_renorm_dp_s       )
)
aalu_renorm_pipe_inst
(
    .clk       (clk                  ),
    .aresetn   (aresetn              ),
    .in_data   (aalu_out             ),
    .in_valid  (malu_aalu_hs_valid   ),
    .in_last   ('0                   ),
    .in_ready  (malu_aalu_hs_ready   ),
    .in_strobe ('0                   ),
    .out_data  (renorm_in            ),
    .out_valid (aalu_renorm_hs_valid ),
    .out_last  (                     ),
    .out_ready (aalu_renorm_hs_ready ),
    .out_strobe(                     )
);

// Stage IV: Result renormalization
hsf3_renorm #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
renorm_inst (
    .mant_sum_in     (renorm_in.mant_sum      ),
    .exp_base_in     (renorm_in.exp_base      ),
    .flags_in        (renorm_in.flags         ),
    .mant_pre_rnd_out(renorm_out.mant_pre_rnd ),
    .exp_rnd_out     (renorm_out.exp_rnd      ),
    .grs_out         (renorm_out.grs          ),
    .flags_out       (renorm_out.flags        )
);

// Pipeline slice between renorm and rnd_pack
hs_dpath_skid_buffer #(
    .FULL_THROUGHPUT(BOOL_TRUE                  ),
    .CTRL_PIPE      (BOOL_FALSE                 ),
    .DATA_PIPE      (BOOL_TRUE                  ),
    .STROBE_UNIT    ($bits(renorm_rnd_pack_dp_s)),
    .DATA_TYPE      (renorm_rnd_pack_dp_s       )
)
renorm_rnd_pack_pipe_inst
(
    .clk       (clk                     ),
    .aresetn   (aresetn                 ),
    .in_data   (renorm_out              ),
    .in_valid  (aalu_renorm_hs_valid    ),
    .in_last   ('0                      ),
    .in_ready  (aalu_renorm_hs_ready    ),
    .in_strobe ('0                      ),
    .out_data  (rnd_pack_in             ),
    .out_valid (renorm_rnd_pack_hs_valid),
    .out_last  (                        ),
    .out_ready (renorm_rnd_pack_hs_ready),
    .out_strobe(                        )
);

// Stage V: Round and pack the result
hsf3_rnd_pack #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH),
    .FP_ROUND_MODE (FP_ROUND_MODE )
)
rnd_pack_inst (
    .mant_pre_rnd_in(rnd_pack_in.mant_pre_rnd    ),
    .exp_rnd_in     (rnd_pack_in.exp_rnd         ),
    .grs_in         (rnd_pack_in.grs             ),
    .flags_in       (rnd_pack_in.flags           ),
    .result_out     (rnd_pack_out.result         ),
    .exception_out  (rnd_pack_out.exception_flags)
);

// Pipeline slice between rnd_pack and output
hs_dpath_skid_buffer #(
    .FULL_THROUGHPUT(BOOL_TRUE               ),
    .CTRL_PIPE      (BOOL_FALSE              ),
    .DATA_PIPE      (BOOL_TRUE               ),
    .STROBE_UNIT    ($bits(rnd_pack_out_dp_s)),
    .DATA_TYPE      (rnd_pack_out_dp_s       )
)
rnd_pack_out_pipe_inst
(
    .clk       (clk                     ),
    .aresetn   (aresetn                 ),
    .in_data   (rnd_pack_out            ),
    .in_valid  (renorm_rnd_pack_hs_valid),
    .in_last   ('0                      ),
    .in_ready  (renorm_rnd_pack_hs_ready),
    .in_strobe ('0                      ),
    .out_data  (output_dp               ),
    .out_valid (result_valid            ),
    .out_last  (                        ),
    .out_ready (result_ready            ),
    .out_strobe(                        )
);

assign result_out    = output_dp.result;
assign exception_out = |output_dp.exception_flags;
assign nan_out       = output_dp.exception_flags.nan;
assign inf_out       = output_dp.exception_flags.inf;

endmodule : hsf3_fpfma_pipe

