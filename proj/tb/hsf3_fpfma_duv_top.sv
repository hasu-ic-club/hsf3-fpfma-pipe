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
// FILE NAME: hsf3_fpfma_duv_top.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/24    Initial version
//-------------------------------------------------------------------------
// PURPOSE: Cocotb testbench DUV wrapper for HSF3
//          This wrapper solved the problem that FP_ROUND_MODE can no be passed
//          as an enumeratable item in some simulator
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

// Cocotb testbench DUV wrapper for HSF3
module hsf3_fpfma_duv_top
import hsf3_typedef_pkg::fp_round_mode_s;
#(
    parameter int EXPONENT_WIDTH = 8,
    parameter int MANTISSA_WIDTH = 23,
    parameter int FP_ROUND_MODE  = 0,
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

hsf3_fpfma_pipe #(
    .EXPONENT_WIDTH(EXPONENT_WIDTH                 ),
    .MANTISSA_WIDTH(MANTISSA_WIDTH                 ),
    .FP_ROUND_MODE (fp_round_mode_s'(FP_ROUND_MODE))
)
duv
(
    .clk          (clk          ),
    .aresetn      (aresetn      ),
    .op_a_in      (op_a_in      ),
    .op_b_in      (op_b_in      ),
    .op_c_in      (op_c_in      ),
    .op_valid     (op_valid     ),
    .op_ready     (op_ready     ),
    .result_out   (result_out   ),
    .result_valid (result_valid ),
    .result_ready (result_ready ),
    .exception_out(exception_out),
    .nan_out      (nan_out      ),
    .inf_out      (inf_out      )
);

endmodule : hsf3_fpfma_duv_top