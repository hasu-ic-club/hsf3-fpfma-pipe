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
// AUTHOR:    Onodera T.
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.2
// VERSION DESCRIPTION: Select coarse windows directly by group index
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/23    First Edition
// 0.2        Onodera T.    2026/11/25    Select the bank using the leading
//                                        group and exponent limit in parallel
//
//-------------------------------------------------------------------------
// PURPOSE: Renormalization module to select an overlapping
//          coarse window for result renormalization
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME    RANGE          DESCRIPTION               DEFAULT VALUE
// MANTISSA_WIDTH    1-128          Mantissa bit width        23
// WINDOW_HI_WIDTH                  Signed window limit width 12
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
    `LP_MODULE int WINDOW_WIDTH    = EXT_MANT_WIDTH + RENORM_WINDOW_EXTRA_BITS,
    `LP_MODULE int LEAD_IDX_WIDTH  = $clog2(SUM_WIDTH + 1) + 1
)
(
    input  logic                       [SUM_WIDTH - 1:0]       mant_sum_in,

    // Lower-bound bit position to place the most 1 significant bit of mantissa
    input  logic                signed [WINDOW_HI_WIDTH - 1:0] limit_hi_in,

    output logic                       [WINDOW_WIDTH - 1:0]    coarse_window_out,  // Coarse window
    output renorm_fine_off_t                                   fine_offset_out,    // Fine offset in the window
    output logic                                               coarse_sticky_out,  // Coarse sticky bit
    output logic                signed [LEAD_IDX_WIDTH - 1:0]  lead_hi_out         // Most 1 bit location of mantissa
);

localparam        int GROUP_SIZE                            = 1 << RENORM_FINE_OFFSET_WIDTH;
localparam        int PAD_LOW                               = MANTISSA_WIDTH + 2;
localparam        int VALID_WINDOW_COUNT                    = SUM_WIDTH + PAD_LOW;
localparam        int GROUP_COUNT                           = (VALID_WINDOW_COUNT + GROUP_SIZE - 1) / GROUP_SIZE;
localparam        int LEAD_GROUP_COUNT                      = (SUM_WIDTH + GROUP_SIZE - 1) / GROUP_SIZE;
localparam        int PAD_HIGH                              = GROUP_COUNT * GROUP_SIZE - SUM_WIDTH;
// The bank size is a power of two so the group index can be split into two fields.
localparam        int CANDIDATE_PER_BANK                    = 4;
localparam        int CANDIDATE_IDX_WIDTH                   = $clog2(CANDIDATE_PER_BANK);
localparam        int GROUP_IDX_WIDTH                       = (GROUP_COUNT > CANDIDATE_PER_BANK) ?
    $clog2(GROUP_COUNT) : CANDIDATE_IDX_WIDTH;
localparam        int BANK_COUNT                            = (GROUP_COUNT + CANDIDATE_PER_BANK - 1) /
    CANDIDATE_PER_BANK;

localparam        int PADDED_SUM_WIDTH                      = PAD_HIGH + SUM_WIDTH + PAD_LOW;

typedef logic [LEAD_GROUP_COUNT - 1:0] lead_grp_t;
typedef logic [PADDED_SUM_WIDTH - 1:0] padded_sum_t;
typedef logic [GROUP_IDX_WIDTH - 1:0] grp_idx_t;
typedef logic signed [LEAD_IDX_WIDTH - 1:0] lead_idx_t;

typedef struct packed
{
    logic [WINDOW_WIDTH - 1:0] window;
    logic                      sticky;
} coarse_data_s;

// Padded summary mantissa
padded_sum_t          padded_sum;

// Leading bit detection
lead_grp_t            lead_nonzero;                                                                              // Non-zero flag for each mantissa group
lead_grp_t            lead_selected;                                                                             // Most non-zero group flag (One-hot)
renorm_fine_off_t     lead_group_offset  [LEAD_GROUP_COUNT];                                                     // Most 1 bit position in each group
grp_idx_t             lead_group;                                                                                // Most non-zero group index
renorm_fine_off_t     lead_offset;                                                                               // Most 1 bit position in most non-zero group
logic                 lead_valid;                                                                                // Mantissa contains at least one set bit

// Exponent limit decode
grp_idx_t             limit_group;                                                                               // Limited lower bound group
renorm_fine_off_t     limit_offset;                                                                              // Offset in corresponding group
logic                 limit_past_window;                                                                         // Indicate the lower bound is passed the selectable window
logic                 limit_valid;                                                                               // Exponent lower bound group valid

// Window selection control
logic                 take_limit_group;                                                                          // Use lower bound group as coarse window

//  Use lower bound group's in-group offset for coarse window
//  Note: This can be set when lower bound group is same as the lead group
//        We should confirm the offset of most 1 bit is not at left of bound
logic                 take_limit_offset;

grp_idx_t             group_sel;                                                                                 // Finally selected group
logic                 window_empty;                                                                              // No valid window to select

// Coarse window data path
coarse_data_s         bank_data          [BANK_COUNT];
coarse_data_s         selected_data;

// Pad the summary mantissa
// Note: We should use padded bits to select continous window from mantissa
//       for ANY selectable group
assign padded_sum        = {{PAD_HIGH{1'b0}}, mant_sum_in, {PAD_LOW{1'b0}}};

// Select the higher group before comparing offsets within the same group.
assign lead_valid        = |lead_nonzero;

// Assign which group is the lower bound in
assign limit_group       = grp_idx_t'($unsigned(limit_hi_in) >> RENORM_FINE_OFFSET_WIDTH);
assign limit_offset      = renorm_fine_off_t'(limit_hi_in);

assign limit_past_window = (limit_hi_in >= VALID_WINDOW_COUNT);
assign limit_valid       = !limit_hi_in[WINDOW_HI_WIDTH - 1] && !limit_past_window;

// Determine which group (generated by lead of limited by exponent)
// should be the coarse window
assign take_limit_group  = limit_valid && (!lead_valid || (limit_group > lead_group));
assign take_limit_offset = take_limit_group ||
    (limit_valid && lead_valid && (limit_group == lead_group) && (limit_offset > lead_offset));

// Select the valid window
assign group_sel         = take_limit_group ? limit_group : lead_group;
assign window_empty      = limit_past_window || (!lead_valid && !limit_valid);

// Output the most 1 bit location of mantissa
assign lead_hi_out       = lead_valid ? lead_idx_t'({lead_group, lead_offset}) : '1;

// Generate group indexes
always_comb begin : encode_lead_group
    lead_group  = '0;
    lead_offset = '0;

    for (int group_id = 0; group_id < LEAD_GROUP_COUNT; group_id++) begin
        lead_group  |= lead_selected[group_id] ? grp_idx_t'(group_id) : '0;
        lead_offset |= lead_selected[group_id] ? lead_group_offset[group_id] : '0;
    end
end : encode_lead_group

// Generate lead groups
`GENERATE_START
for (genvar group_id = 0; group_id < LEAD_GROUP_COUNT; group_id++) begin : gen_lead_group
    // Each group
    logic [GROUP_SIZE - 1:0] group_bits;

    // Extract group data from original summary mantissa
    assign group_bits              = padded_sum[PAD_LOW + group_id * GROUP_SIZE +: GROUP_SIZE];

    // Select most non-zero group
    // Indicate this group has 1
    assign lead_nonzero[group_id]  = |group_bits;

    // Select current group when
    // all groups located left than current group are zero
    assign lead_selected[group_id] = lead_nonzero[group_id] &&
        !(|(lead_nonzero >> (group_id + 1)));

    // Extract the precision bit offset of most 1 bit in the group
    always_comb begin : encode_lead_offset
        lead_group_offset[group_id] = '0;

        for (int bit_id = GROUP_SIZE - 1; bit_id >= 0; bit_id--) begin
            if (group_bits[bit_id]) begin
                lead_group_offset[group_id] = renorm_fine_off_t'(bit_id);
                break;
            end
        end
    end : encode_lead_offset
end : gen_lead_group

// Generate all banks (full mantissa window) from padded mantissa for select
// Each bank groups CANDIDATE_PER_BANK candidates. Each valid candidate holds a
// contiguous coarse window from padded_sum and a sticky bit for the bits below it.

// We select the candidate of each bank by low bits of group_sel.
// The high bits select the final bank when multiple banks are present.
// It's a 2-level mux for coarse windows
for (genvar bank_id = 0; bank_id < BANK_COUNT; bank_id++) begin : gen_bank
    coarse_data_s candidate [CANDIDATE_PER_BANK];

    for (genvar digit = 0; digit < CANDIDATE_PER_BANK; digit++) begin : gen_candidate
        localparam int GROUP = CANDIDATE_PER_BANK * bank_id + digit;
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

    assign bank_data[bank_id] = candidate[group_sel[CANDIDATE_IDX_WIDTH - 1:0]];
end : gen_bank

// Take the final selected window (selected bank)
if (BANK_COUNT == 1) begin : single_bank
    assign selected_data = window_empty ? '0 : bank_data[0];
end : single_bank
else begin : multiple_banks
    typedef logic [GROUP_IDX_WIDTH - CANDIDATE_IDX_WIDTH - 1:0] bank_idx_t;

    coarse_data_s masked_bank_data [BANK_COUNT];

    // Mask invalid banks before combining their windows and sticky bits.
    for (genvar bank_id = 0; bank_id < BANK_COUNT; bank_id++) begin : gen_bank_mask
        logic bank_selected;

        assign bank_selected             = !window_empty &&
            (group_sel[GROUP_IDX_WIDTH - 1:CANDIDATE_IDX_WIDTH] == bank_idx_t'(bank_id));
        assign masked_bank_data[bank_id] = bank_selected ? bank_data[bank_id] : '0;
    end : gen_bank_mask

    always_comb begin : combine_banks
        selected_data = '0;

        for (int bank_id = 0; bank_id < BANK_COUNT; bank_id++) begin
            selected_data |= masked_bank_data[bank_id];
        end
    end : combine_banks
end : multiple_banks
`GENERATE_END

// An empty window can still round to the smallest subnormal.
assign coarse_window_out = selected_data.window;
assign fine_offset_out   = window_empty ? '0 : (take_limit_offset ? limit_offset : lead_offset);
assign coarse_sticky_out = window_empty ? lead_valid : selected_data.sticky;

endmodule : hsf3_renorm_coarse_sft
