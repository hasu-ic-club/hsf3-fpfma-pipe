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
// FILE NAME: hsf3_renorm_coarse_sft.sv
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
// PURPOSE: Renormalization module to select an overlapping
//          coarse window for result renormalization
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME    RANGE          DESCRIPTION               DEFAULT VALUE
// MANTISSA_WIDTH    1-128          Mantissa bit width        23
// WINDOW_HI_WIDTH                  Signed window index width 12
// SUM_WIDTH                        AALU sum width            ALIGNED_WIDTH + 1
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Renormalization module to select an overlapping coarse window for result renormalization
module hsf3_renorm_coarse_sft
import hsf3_typedef_pkg::*;
#(
    parameter  int MANTISSA_WIDTH  = 23,
    parameter  int WINDOW_HI_WIDTH = 12,
    `LP_MODULE int FULL_PROD_WIDTH = 2 * (MANTISSA_WIDTH + 1),
    `LP_MODULE int ALIGNED_WIDTH   = FULL_PROD_WIDTH + 2,
    `LP_MODULE int SUM_WIDTH       = ALIGNED_WIDTH + 1,
    `LP_MODULE int EXT_MANT_WIDTH  = MANTISSA_WIDTH + 1,
    `LP_MODULE int WINDOW_WIDTH    = EXT_MANT_WIDTH + RENORM_WINDOW_EXTRA_BITS
)
(
    input  logic                       [SUM_WIDTH - 1:0]       mant_sum_in,
    input  logic                signed [WINDOW_HI_WIDTH - 1:0] window_hi_in,

    output logic                       [WINDOW_WIDTH - 1:0]    coarse_window_out,
    output renorm_fine_off_t                                   fine_offset_out,
    output logic                                               coarse_sticky_out
);

localparam    int  GROUP_SIZE                      = 1 << RENORM_FINE_OFFSET_WIDTH;
localparam    int  PAD_LOW                         = MANTISSA_WIDTH + 2;
localparam    int  VALID_WINDOW_COUNT              = SUM_WIDTH + PAD_LOW;
localparam    int  GROUP_COUNT                     = (VALID_WINDOW_COUNT + GROUP_SIZE - 1) / GROUP_SIZE;
localparam    int  PAD_HIGH                        = GROUP_COUNT * GROUP_SIZE - SUM_WIDTH;
localparam    int  GROUP_IDX_WIDTH                 = (GROUP_COUNT > 4) ? $clog2(GROUP_COUNT) : 2;
localparam    int  BANK_COUNT                      = (GROUP_COUNT + 3) / 4;

localparam    int  PADDED_SUM_WIDTH                = PAD_HIGH + SUM_WIDTH + PAD_LOW;

typedef logic [PADDED_SUM_WIDTH - 1:0] padded_sum_t;
typedef logic [GROUP_IDX_WIDTH - 1:0] grp_idx_t;

typedef struct packed
{
    logic [WINDOW_WIDTH - 1:0] window;
    logic                      sticky;
} coarse_data_s;

padded_sum_t       padded_sum;
grp_idx_t          group_idx;
logic              window_empty;
coarse_data_s      bank_data          [BANK_COUNT];
coarse_data_s      selected_data;

assign padded_sum        = {{PAD_HIGH{1'b0}}, mant_sum_in, {PAD_LOW{1'b0}}};
assign group_idx         = GROUP_IDX_WIDTH'($unsigned(window_hi_in) >> RENORM_FINE_OFFSET_WIDTH);
assign window_empty      = (window_hi_in < 0) || (window_hi_in >= VALID_WINDOW_COUNT);

`GENERATE_START
for (genvar bank_id = 0; bank_id < BANK_COUNT; bank_id++) begin : gen_bank
    coarse_data_s candidate [0:3];

    for (genvar digit = 0; digit < 4; digit++) begin : gen_candidate
        localparam int GROUP = 4 * bank_id + digit;
        localparam int BASE  = GROUP * GROUP_SIZE;

        if (GROUP < GROUP_COUNT) begin : valid_group
            assign candidate[digit].window = padded_sum[BASE +: WINDOW_WIDTH];

            // All bits below this group's window are sticky for every fine offset.
            if (BASE <= PAD_LOW) begin : zero_prefix
                assign candidate[digit].sticky = 1'b0;
            end : zero_prefix
            else begin : nonempty_prefix
                assign candidate[digit].sticky = |padded_sum[BASE - 1:PAD_LOW];
            end : nonempty_prefix
        end : valid_group
        else begin : unused_group
            assign candidate[digit]        = '0;
        end : unused_group
    end : gen_candidate

    assign bank_data[bank_id] = group_idx[1] ?
        (group_idx[0] ? candidate[3] : candidate[2]) :
        (group_idx[0] ? candidate[1] : candidate[0]);
end : gen_bank

if (BANK_COUNT == 1) begin : single_bank
    assign selected_data = bank_data[0];
end : single_bank
else begin : multiple_banks
    assign selected_data = bank_data[group_idx[GROUP_IDX_WIDTH - 1:2]];
end : multiple_banks
`GENERATE_END

// An empty window can still round to the smallest subnormal.
assign coarse_window_out = window_empty ? '0 : selected_data.window;
assign fine_offset_out   = window_empty ? '0 : renorm_fine_off_t'(window_hi_in);
assign coarse_sticky_out = window_empty ? (|mant_sum_in) : selected_data.sticky;

endmodule : hsf3_renorm_coarse_sft
