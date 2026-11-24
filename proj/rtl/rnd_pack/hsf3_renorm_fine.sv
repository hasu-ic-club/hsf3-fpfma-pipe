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
// FILE NAME: hsf3_renorm_fine.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/23    First Edition
//
//-------------------------------------------------------------------------
// PURPOSE: Fine renormalization module to extract the mantissa and
//          GRS bits from the selected coarse window
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME  RANGE           DESCRIPTION             DEFAULT VALUE
// EXPONENT_WIDTH  1-32            Exponent bit width      8
// SUM_WIDTH
// MANTISSA_WIDTH  1-128           Mantissa bit width      23
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Fine renormalization module to extract the mantissa and GRS bits from the selected coarse window
module hsf3_renorm_fine
import hsf3_typedef_pkg::*;
#(
    parameter  int MANTISSA_WIDTH = 23,
    `LP_MODULE int EXT_MANT_WIDTH = MANTISSA_WIDTH + 1,
    `LP_MODULE int WINDOW_WIDTH   = EXT_MANT_WIDTH + RENORM_WINDOW_EXTRA_BITS
)
(
    input  logic             [WINDOW_WIDTH - 1:0]   coarse_window_in,
    input  renorm_fine_off_t                        fine_offset_in,
    input  logic                                    coarse_sticky_in,

    output logic             [EXT_MANT_WIDTH - 1:0] mant_pre_rnd_out,
    output grs_s                                    grs_out
);

localparam int                                         MANT_GR_WIDTH    = EXT_MANT_WIDTH + 2;
localparam int                                         FINE_HIGH_BIT    = RENORM_FINE_OFFSET_WIDTH - 1;
localparam int                                         FINE_HIGH_SHIFT  = 1 << FINE_HIGH_BIT;
localparam int                                         FINE_STICKY_BITS = (1 << RENORM_FINE_OFFSET_WIDTH) - 1;

logic          [MANT_GR_WIDTH + FINE_HIGH_SHIFT - 1:0] fine_mid;
logic          [MANT_GR_WIDTH - 1:0]                   mant_gr;
logic          [FINE_STICKY_BITS - 1:0]                sticky_mask;

// Keep enough bits after the first mux for the optional high-bit shift.
assign fine_mid         = coarse_window_in[fine_offset_in[FINE_HIGH_BIT - 1:0] +: $bits(fine_mid)];
assign mant_gr          = fine_offset_in[FINE_HIGH_BIT] ?
    fine_mid[FINE_HIGH_SHIFT +: MANT_GR_WIDTH] : fine_mid[0 +: MANT_GR_WIDTH];

`GENERATE_START
for (genvar bit_idx = 0; bit_idx < FINE_STICKY_BITS; bit_idx++) begin : gen_sticky_mask
    assign sticky_mask[bit_idx] = fine_offset_in > renorm_fine_off_t'(bit_idx);
end : gen_sticky_mask
`GENERATE_END

assign mant_pre_rnd_out = mant_gr[2 +: EXT_MANT_WIDTH];
assign grs_out.guard    = mant_gr[1];
assign grs_out.round    = mant_gr[0];
assign grs_out.sticky   = coarse_sticky_in | (|(coarse_window_in[FINE_STICKY_BITS - 1:0] & sticky_mask));

endmodule : hsf3_renorm_fine
