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
// FILE NAME: hsf3_jam_rshift.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/24    First Edition
//-------------------------------------------------------------------------
// PURPOSE: Right-shift unit with sticky-bit generation for floating-point exponent alignment
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                 DEFAULT VALUE
// DATA_WIDTH          >=1         Shifted data and jam width  24
// SFT_AMOUNT_WIDTH    >=1         Shift amount width          8
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Right-shift unit with sticky-bit generation for floating-point exponent alignment
// Output bit 0 includes the bit shifted into it and all bits shifted out.
module hsf3_jam_rshift
#(
    parameter int DATA_WIDTH       = 24,
    parameter int SFT_AMOUNT_WIDTH = 8
)
(
    input  wire   [DATA_WIDTH - 1:0]       data_in,
    input  wire   [SFT_AMOUNT_WIDTH - 1:0] sft_in,

    output logic  [DATA_WIDTH - 1:0]       data_out
);

localparam int SHIFT_LIMIT_WIDTH = $clog2(DATA_WIDTH + 1);
localparam int LOW_SHIFT_WIDTH   = (SFT_AMOUNT_WIDTH < SHIFT_LIMIT_WIDTH) ?
    SFT_AMOUNT_WIDTH : SHIFT_LIMIT_WIDTH;
localparam int SFT_STAGES        = (LOW_SHIFT_WIDTH + 1) / 2;

typedef logic [DATA_WIDTH - 1:0] data_t;
typedef logic [2 * SFT_STAGES - 1:0] shift_select_t;

shift_select_t shift_select;
data_t         stage_data [0:SFT_STAGES];

// Zero-extend the most significant digit when the low shift width is odd.
assign shift_select  = shift_select_t'(sft_in[LOW_SHIFT_WIDTH - 1:0]);
assign stage_data[0] = data_in;

`GENERATE_START
for (genvar stage = 0; stage < SFT_STAGES; stage++) begin : radix4_stage
    localparam int UNIT_SHIFT = 1 << (2 * stage);
    data_t         candidate [0:3];

    assign candidate[0] = stage_data[stage];
    for (genvar digit = 1; digit < 4; digit++) begin : fixed_shift
        localparam int SHIFT_COUNT = digit * UNIT_SHIFT;

        if (SHIFT_COUNT >= DATA_WIDTH) begin : all_bits_jammed
            assign candidate[digit] = data_t'(|stage_data[stage]);
        end : all_bits_jammed
        else begin : partial_shift
            // Fold the previous jam bit and the newly discarded bits into bit 0.
            assign candidate[digit] = {
                stage_data[stage][DATA_WIDTH - 1:1] >> SHIFT_COUNT,
                |stage_data[stage][SHIFT_COUNT:0]
            };
        end : partial_shift
    end : fixed_shift

    assign stage_data[stage + 1] = shift_select[2 * stage + 1] ?
        (shift_select[2 * stage] ? candidate[3] : candidate[2]) :
        (shift_select[2 * stage] ? candidate[1] : candidate[0]);
end : radix4_stage

if (SFT_AMOUNT_WIDTH > LOW_SHIFT_WIDTH) begin : large_shift
    wire high_shift = |sft_in[SFT_AMOUNT_WIDTH - 1:LOW_SHIFT_WIDTH];
    assign data_out = high_shift ? data_t'(|data_in) : stage_data[SFT_STAGES];
end : large_shift
else begin : low_shift
    assign data_out = stage_data[SFT_STAGES];
end : low_shift
`GENERATE_END

endmodule : hsf3_jam_rshift
