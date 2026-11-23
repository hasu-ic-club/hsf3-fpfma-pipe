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
// FILE NAME: hsf3_exp_extract.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/23    First Edition cloned from HSF2
//-------------------------------------------------------------------------
// PURPOSE: Real exponent extractor for floating-point FMA
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME  RANGE           DESCRIPTION              DEFAULT VALUE
// EXPONENT_WIDTH  1-32            Exponent bit width       8
// LZC_WIDTH       1-32            Leading zero count width 8
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Real exponent extractor for FMA
module hsf3_exp_extract
#(
    parameter int EXPONENT_WIDTH = 8,
    parameter int LZC_WIDTH      = 8,
    `LP_MODULE int REXP_WIDTH = hs_math_basic_pkg::max(EXPONENT_WIDTH, LZC_WIDTH) + 1
)
(
    input  logic        [EXPONENT_WIDTH - 1:0] exp_in,
    input  logic                               denorm_in,
    input  logic        [LZC_WIDTH - 1:0]      lzc_in,

    output logic signed [REXP_WIDTH - 1:0]     real_exp
);

logic signed [REXP_WIDTH - 1:0] exp_signed;
logic signed [REXP_WIDTH - 1:0] lzc_signed;

assign exp_signed = signed'({1'b0, exp_in});
assign lzc_signed = signed'({1'b0, lzc_in});

assign real_exp   = denorm_in ? -(lzc_signed - 'sd1) : exp_signed;

endmodule : hsf3_exp_extract