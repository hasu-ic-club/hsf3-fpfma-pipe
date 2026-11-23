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
// FILE NAME: hsf3_lzc.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1a0
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1a0      O. Tsusaki    2026/11/23    First Edition cloned from HSF2
//-------------------------------------------------------------------------
// PURPOSE: Hierarchical block leading zero counter for
//          de-normalized operands of floating point multiplier
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                 DEFAULT VALUE
// DATA_WIDTH          1-128       Width to calculate the      23
//                                 leading zeros
// LZC_BLOCK_WIDTH     2-128       Bit width of each block     8
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Hierarchical block leading zero counter for de-normalized operands of floating point multiplier
module hsf3_hblzc
#(
    parameter  int DATA_WIDTH      = 23,
    parameter  int LZC_BLOCK_WIDTH = 8,
    `LP_MODULE int LZC_WIDTH  = $clog2(DATA_WIDTH + 1)
)
(
    input  logic [DATA_WIDTH - 1:0] din,
    output logic [LZC_WIDTH - 1:0]  lzc
);

genvar         idx;

localparam int NUM_BLOCKS                 = (DATA_WIDTH + LZC_BLOCK_WIDTH - 1) / LZC_BLOCK_WIDTH;
localparam int EXT_DWIDTH                 = NUM_BLOCKS * LZC_BLOCK_WIDTH;
localparam int PAD_BITS                   = EXT_DWIDTH - DATA_WIDTH;
localparam int BLK_LZC_WIDTH              = $clog2(LZC_BLOCK_WIDTH + 1);                         // Bit width to present LZC of each block
localparam int EXT_LZC_WIDTH              = $clog2(EXT_DWIDTH + 1);

typedef logic [EXT_DWIDTH - 1:0]      ext_data_t;
typedef logic [LZC_BLOCK_WIDTH - 1:0] blk_t;
typedef logic [BLK_LZC_WIDTH - 1:0]   blk_lzc_t;
typedef logic [EXT_LZC_WIDTH - 1:0]   ext_lzc_t;

// Padded data with leading zeros
ext_data_t     ext_data;

// LZC result for each block
logic          blk_non_zero  [NUM_BLOCKS];
blk_lzc_t      blk_lzc       [NUM_BLOCKS];

// LZC reuslt
ext_lzc_t      ext_lzc;

// Assign and padding the input data
assign ext_data = ext_data_t'(din);

// LZC blocks
`GENERATE_START
for (idx = 0; idx < NUM_BLOCKS; idx++) begin : gen_lzc_blk
    blk_t blk_bits;

    // Assign block 0 -> MSB, ...
    assign blk_bits          = ext_data[$bits(ext_data_t) - 1 - idx * LZC_BLOCK_WIDTH -: LZC_BLOCK_WIDTH];

    // Detect the block non-zero
    assign blk_non_zero[idx] = |blk_bits;

    // Leading zero count
    // This will generate as a LUT
    always_comb begin : lzc_in_blk
        blk_lzc[idx] = BLK_LZC_WIDTH'($bits(blk_t));

        for (int bidx = 0; bidx < $bits(blk_t); bidx++) begin
            if (blk_bits[LZC_BLOCK_WIDTH - 1 - bidx]) begin
                blk_lzc[idx] = BLK_LZC_WIDTH'(bidx);
                break;
            end
        end
    end : lzc_in_blk
end : gen_lzc_blk
`GENERATE_END

// Block priority encoding
always_comb begin : blk_prio_enc
    ext_lzc = ext_lzc_t'(EXT_DWIDTH);

    for (int blk = 0; blk < NUM_BLOCKS; blk++) begin
        if (blk_non_zero[blk]) begin
            ext_lzc = blk * $bits(blk_t) + blk_lzc[blk];
            break;
        end
    end
end : blk_prio_enc

assign lzc = LZC_WIDTH'(ext_lzc - PAD_BITS);

endmodule : hsf3_hblzc