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
// FILE NAME: hsf3_macros.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1a0
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/23    First Edition
//-------------------------------------------------------------------------
// PURPOSE: Macros for F3 floating point FMA
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                 DEFAULT VALUE
// N/A
//-FHDR--------------------------------------------------------------------

`ifndef HSF3_MACROS_SVH
`define HSF3_MACROS_SVH

`define HSF3_MANTISSA_TYPEDEF(MANT_BW) typedef logic [MANT_BW - 1:0] fp_mant_t
`define HSF3_EXPONENT_TYPEDEF(EXP_BW) typedef logic [EXP_BW - 1:0] fp_exp_t

`define HSF3_EXT_MANT_TYPEDEF(MANT_BW) typedef logic [MANT_BW + 1 - 1:0] fp_ext_mant_t

`define HSF3_PROD_MANT_TYPEDEF(MANT_BW) typedef logic [MANT_BW * 2 + 2 - 1:0] fp_prod_mant_t

`define HSF3_MANTISSA_ALIGNED_TYPEDEF(MANT_BW) typedef logic [MANT_BW * 2 + 2 + 2 - 1:0] mant_aligned_t

`define HSF3_FP_TYPEDEF(EXP_BW, MANT_BW) typedef struct packed \
{ \
    logic sign; \
    logic [EXP_BW  - 1:0] exp; \
    logic [MANT_BW - 1:0] mantissa; \
} fp_s

`endif // HSF2_MACROS_SVH
