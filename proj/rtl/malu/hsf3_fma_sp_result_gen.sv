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
// FILE NAME: hsf3_fma_sp_result_gen.sv
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
// PURPOSE: Specifal result generator for FMA
//          This module receives product flags and operand C's flags to
//          determine which special result should be selected to output
//          Also, this module provides the "pass_result" when the bypass
//          flag has been flagged.
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

// Specifal result generator for FMA
module hsf3_fma_sp_result_gen
import hsf3_typedef_pkg::*;
#(
    parameter int             EXPONENT_WIDTH = 8,
    parameter int             MANTISSA_WIDTH = 23,
    parameter fp_round_mode_s FP_ROUND_MODE  = FP_ROUND_MODE_TIES_TO_EVEN,
    `LP_MODULE int OP_WIDTH = 1 + EXPONENT_WIDTH + MANTISSA_WIDTH
)
(
    input  logic                  prod_nan,
    input  logic                  prod_inf,
    input  logic                  prod_zero,
    input  logic                  prod_sign,

    input  logic [OP_WIDTH - 1:0] op_c_in,
    input  logic                  c_nan,
    input  logic                  c_inf,
    input  logic                  c_zero,

    output logic                  result_pass,
    output logic [OP_WIDTH - 1:0] pass_result
);

`HSF3_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);

logic c_sign;
fp_s  pass_fp;

assign c_sign      = op_c_in[OP_WIDTH - 1];

// Note: We generate NaN and Inf values by 'bypass' route.

always_comb begin : special_result
    if (prod_nan || c_nan || (prod_inf && c_inf && (prod_sign != c_sign))) begin
        // NaN + NaN = NaN
        // Inf - Inf = NaN
        result_pass      = 1'b1;
        pass_fp.sign     = '0;
        pass_fp.exp      = '1;
        pass_fp.mantissa = MANTISSA_WIDTH'(1);
    end
    else if (prod_inf || c_inf) begin
        // Inf + Inf = Inf
        // -Inf - Inf = -Inf
        result_pass      = 1'b1;
        pass_fp.sign     = prod_inf ? prod_sign : c_sign;
        pass_fp.exp      = '1;
        pass_fp.mantissa = '0;
    end
    else if (prod_zero && c_zero) begin
        result_pass      = 1'b1;
        pass_fp.exp      = '0;
        pass_fp.mantissa = '0;

        // Both zero
        // 0 + (-0) = -0 (rounding toward ngative)
        // 0 + 0 = 0     (other rounding)
        if (FP_ROUND_MODE == FP_ROUND_MODE_TOWARD_NEGATIVE) begin
            pass_fp.sign = prod_sign | c_sign;
        end
        else begin
            pass_fp.sign = prod_sign & c_sign;
        end
    end
    else if (prod_zero) begin
        // Product is zero, bypass operand C to result
        result_pass      = 1'b1;
        pass_fp          = fp_s'(op_c_in);
    end
    else begin
        // Else, normal
        result_pass      = 1'b0;
        pass_fp          = '0;
    end
end : special_result

assign pass_result = pass_fp;

endmodule : hsf3_fma_sp_result_gen