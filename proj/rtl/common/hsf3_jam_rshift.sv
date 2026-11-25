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
// RELEASE VERSION: 0.2
// VERSION DESCRIPTION: Configurable power-of-two shift radix and sticky group size
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/24    First Edition
// 0.2        O. Tsusaki    2026/11/25    Add configurable shift radix and
//                                        parallel sticky-bit generation
//-------------------------------------------------------------------------
// PURPOSE: Right-shift unit with sticky-bit generation for floating-point exponent alignment
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                       DEFAULT VALUE
// DATA_WIDTH          >=1         Shifted data and jam width        24
// SFT_AMOUNT_WIDTH    >=1         Shift amount width                8
// RADIX_EXP2          1..30       Radix of each shift stage (2^N)   2
// JAM_GRP_SIZE_EXP2   2..30       Bits in each sticky reduce group  2
//                                 (2^N)
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
    parameter int DATA_WIDTH        = 24,
    parameter int SFT_AMOUNT_WIDTH  = 8,
    parameter int RADIX_EXP2        = 2,
    parameter int JAM_GRP_SIZE_EXP2 = 2
)
(
    input  logic [DATA_WIDTH - 1:0]       data_in,
    input  logic [SFT_AMOUNT_WIDTH - 1:0] sft_in,

    output logic [DATA_WIDTH - 1:0]       data_out
);

genvar             stage;
genvar             bit_idx;
genvar             grp_idx;

// Keep both powers of two representable as positive int values.
localparam     bit VALID_RADIX_EXP2                    = (RADIX_EXP2 >= 1) && (RADIX_EXP2 <= 30);
localparam     bit VALID_JAM_GRP_EXP2                  = (JAM_GRP_SIZE_EXP2 >= 2) && (JAM_GRP_SIZE_EXP2 <= 30);
localparam     int RADIX                               = 2 ** (VALID_RADIX_EXP2 ? RADIX_EXP2 : 1);
localparam     int SHIFT_LIMIT_WIDTH                   = $clog2(DATA_WIDTH + 1);
localparam     int LOW_SHIFT_WIDTH                     = (SFT_AMOUNT_WIDTH < SHIFT_LIMIT_WIDTH) ? SFT_AMOUNT_WIDTH : SHIFT_LIMIT_WIDTH;
localparam     int SFT_BIT_WIDTH                       = $clog2(RADIX);
localparam     int SFT_STAGES                          = 1 + (LOW_SHIFT_WIDTH - 1) / SFT_BIT_WIDTH;

localparam     int JAM_GROUP_SIZE                      = 2 ** (VALID_JAM_GRP_EXP2 ? JAM_GRP_SIZE_EXP2 : 2);
localparam     int JAM_OFFSET_WIDTH                    = $clog2(JAM_GROUP_SIZE);
localparam     int JAM_GROUPS                          = 1 + (DATA_WIDTH - 1) / JAM_GROUP_SIZE;
localparam     int JAM_INDEX_WIDTH                     = (SHIFT_LIMIT_WIDTH > JAM_OFFSET_WIDTH) ? SHIFT_LIMIT_WIDTH - JAM_OFFSET_WIDTH : 1;
localparam     int JAM_MASK_WIDTH                      = (JAM_GROUP_SIZE < DATA_WIDTH) ? JAM_GROUP_SIZE : DATA_WIDTH;

typedef logic [DATA_WIDTH - 1:0] data_t;
typedef logic [LOW_SHIFT_WIDTH - 1:0] shift_select_t;
typedef logic [JAM_OFFSET_WIDTH - 1:0] jam_offset_t;
typedef logic [JAM_INDEX_WIDTH - 1:0] jam_index_t;
typedef logic [JAM_GROUPS - 1:0] jam_groups_t;
typedef logic [JAM_MASK_WIDTH - 1:0] jam_mask_t;

shift_select_t     shift_select;
data_t             stage_data         [SFT_STAGES + 1];
jam_offset_t       jam_offset;
jam_index_t        shift_group;
jam_mask_t         jam_mask;
jam_groups_t       jam_groups;
data_t             jammed_data;

assign shift_select   = sft_in[LOW_SHIFT_WIDTH - 1:0];
assign stage_data[0]  = data_in;
assign jam_offset     = jam_offset_t'(shift_select);
assign shift_group    = jam_index_t'(shift_select >> JAM_OFFSET_WIDTH);

`GENERATE_START
if (!VALID_RADIX_EXP2) begin : invalid_radix
    initial $fatal(1, "hsf3_jam_rshift RADIX_EXP2 must be between 1 and 30, got %0d", RADIX_EXP2);
end : invalid_radix

if (!VALID_JAM_GRP_EXP2) begin : invalid_jam_group
    initial $fatal(1, "hsf3_jam_rshift JAM_GRP_SIZE_EXP2 must be between 2 and 30, got %0d", JAM_GRP_SIZE_EXP2);
end : invalid_jam_group

for (stage = 0; stage < SFT_STAGES; stage++) begin : radix_stage
    localparam int BIT_OFFSET      = SFT_BIT_WIDTH * stage;
    localparam int REMAINING_BITS  = LOW_SHIFT_WIDTH - BIT_OFFSET;
    localparam int DIGIT_WIDTH     = (REMAINING_BITS < SFT_BIT_WIDTH) ? REMAINING_BITS : SFT_BIT_WIDTH;
    localparam int SFT_CANDIDATES  = 1 << DIGIT_WIDTH;
    data_t         candidate [SFT_CANDIDATES];

    assign candidate[0]            = stage_data[stage];
    for (bit_idx = 1; bit_idx < SFT_CANDIDATES; bit_idx++) begin : fixed_shift
        localparam int SHIFT_COUNT   = bit_idx << BIT_OFFSET;
        assign candidate[bit_idx]    = stage_data[stage] >> SHIFT_COUNT;
    end : fixed_shift

    assign stage_data[stage + 1]   = candidate[shift_select[BIT_OFFSET +: DIGIT_WIDTH]];
end : radix_stage

// Reduce the original input in parallel with shifting. Groups below the shift
// boundary contribute all bits. The offset selects the prefix of the boundary group.
for (bit_idx = 0; bit_idx < JAM_MASK_WIDTH; bit_idx++) begin : jam_prefix_mask
    assign jam_mask[bit_idx] = jam_offset >= jam_offset_t'(bit_idx);
end : jam_prefix_mask

for (grp_idx = 0; grp_idx < JAM_GROUPS; grp_idx++) begin : jam_grp
    localparam jam_index_t GROUP_INDEX    = jam_index_t'(grp_idx);
    localparam int         GRP_BASE       = JAM_GROUP_SIZE * grp_idx;
    localparam int         REMAINING_BITS = DATA_WIDTH - GRP_BASE;
    localparam int         GRP_WIDTH      = (REMAINING_BITS < JAM_GROUP_SIZE) ? REMAINING_BITS : JAM_GROUP_SIZE;
    logic [GRP_WIDTH - 1:0] grp_data;
    logic grp_prefix;

    assign grp_data                       = data_in[GRP_BASE +: GRP_WIDTH];
    assign grp_prefix                     = |(grp_data & jam_mask[GRP_WIDTH - 1:0]);

    assign jam_groups[grp_idx]            = ((shift_group > GROUP_INDEX) && (|grp_data)) ||
        ((shift_group == GROUP_INDEX) && grp_prefix);
end : jam_grp

// Bit zero is the jam bit even when the data width is one.
assign jammed_data[0] = |jam_groups;
if (DATA_WIDTH > 1) begin : shifted_upper_bits
    assign jammed_data[DATA_WIDTH - 1:1] = stage_data[SFT_STAGES][DATA_WIDTH - 1:1];
end : shifted_upper_bits

if (SFT_AMOUNT_WIDTH > LOW_SHIFT_WIDTH) begin : large_shift
    logic high_shift;

    assign high_shift                    = |sft_in[SFT_AMOUNT_WIDTH - 1:LOW_SHIFT_WIDTH];
    assign data_out                      = high_shift ? data_t'(|data_in) : jammed_data;
end : large_shift
else begin : low_shift
    assign data_out                      = jammed_data;
end : low_shift
`GENERATE_END

endmodule : hsf3_jam_rshift
