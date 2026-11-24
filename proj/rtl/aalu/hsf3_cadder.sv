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
// FILE NAME: hsf3_cadder.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/24    First Edition cloned from HSF1
//-------------------------------------------------------------------------
// PURPOSE: Core adder for mantissas in floating point adder
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                 DEFAULT VALUE
// DATA_WIDTH          1-1024      Operand data bit width      24
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Core adder for mantissas in floating point adder
module hsf3_cadder
#(
    parameter int DATA_WIDTH = 24
)
(
    input  logic [DATA_WIDTH - 1:0]     op_a_in,
    input  logic [DATA_WIDTH - 1:0]     op_b_in,
    input  logic                        invert_a,
    input  logic                        invert_b,

    output logic [DATA_WIDTH + 1 - 1:0] result_out
);

// Invert either operand and add one to form its two's complement.
logic [DATA_WIDTH - 1:0] adder_op_a;
logic [DATA_WIDTH - 1:0] adder_op_b;
logic                    adder_cin;

logic [DATA_WIDTH - 1:0] adder_result;
logic                    adder_cout;

assign adder_op_a                 = op_a_in ^ {DATA_WIDTH{invert_a}};
assign adder_op_b                 = op_b_in ^ {DATA_WIDTH{invert_b}};
assign adder_cin                  = invert_a || invert_b;

assign {adder_cout, adder_result} = adder_op_a + adder_op_b + adder_cin;

assign result_out                 = {adder_cout ^ adder_cin, adder_result};

endmodule : hsf3_cadder
