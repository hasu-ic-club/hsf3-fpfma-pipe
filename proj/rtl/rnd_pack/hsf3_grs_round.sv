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
// FILE NAME: hsf3_grs_round.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1a0
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1a0      O. Tsusaki    2026/11/24    First edition cloned from hsf2_grs_round
//-------------------------------------------------------------------------
// PURPOSE: Floating point rounding with GRS
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME  RANGE           DESCRIPTION             DEFAULT VALUE
// MANTISSA_WIDTH  1-128           Mantissa bit width      23
// FP_ROUND_MOD    fp_round_mode_s Floating point rounding FP_ROUND_MODE_TIES_TO_EVEN
//                                 mode
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

module hsf3_grs_round
import hsf3_typedef_pkg::*;
#(
    parameter int             MANTISSA_WIDTH = 23,
    parameter fp_round_mode_s FP_ROUND_MODE  = FP_ROUND_MODE_TIES_TO_EVEN
)
(
    input  logic                            sign_in,
    input  logic [MANTISSA_WIDTH + 1 - 1:0] ext_mant_in,
    input  grs_s                            grs_in,
    output logic [MANTISSA_WIDTH + 1 - 1:0] rnd_mant_out,
    output logic                            rnd_cout
);

logic lsb_mant;

assign lsb_mant = ext_mant_in[0];

`GENERATE_START
if (FP_ROUND_MODE == FP_ROUND_MODE_TIES_TO_EVEN) begin : round_tte
    assign {rnd_cout, rnd_mant_out} = ext_mant_in + ((grs_in.guard && (grs_in.round || grs_in.sticky || lsb_mant)) ? 'd1 : 'd0);
end : round_tte
else if (FP_ROUND_MODE == FP_ROUND_MODE_TOWARD_ZERO) begin : round_tz
    assign {rnd_cout, rnd_mant_out} = ext_mant_in + 'd0;
end : round_tz
else if (FP_ROUND_MODE == FP_ROUND_MODE_TOWARD_POSITIVE) begin : round_tp
    assign {rnd_cout, rnd_mant_out} = ext_mant_in + ((!sign_in && (grs_in.guard || grs_in.round || grs_in.sticky)) ? 'd1 : 'd0);
end : round_tp
else begin : round_tn
    assign {rnd_cout, rnd_mant_out} = ext_mant_in + ((sign_in && (grs_in.guard || grs_in.round || grs_in.sticky)) ? 'd1 : 'd0);
end : round_tn
`GENERATE_END

endmodule : hsf3_grs_round