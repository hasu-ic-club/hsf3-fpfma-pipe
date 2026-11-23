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
// FILE NAME: hsf3_grs_rshift.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1
// VERSION DESCRIPTION: First Edition cloned from HSF1 v0.2
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/23    First Edition cloned from HSF1 v0.2
//-------------------------------------------------------------------------
// PURPOSE: Unsigned right shifter with GRS rounding bit recording
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                 DEFAULT VALUE
// DATA_WIDTH          1-128       Shifted data width          24
// SFT_AMOUNT_WIDTH    1-128        Shift amount width         8
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Unsigned right shifter with GRS rounding bit recording
module hsf3_grs_rshift
import hsf3_typedef_pkg::*;
#(
    parameter int DATA_WIDTH       = 24,
    parameter int SFT_AMOUNT_WIDTH = 8
)
(
    input  grs_s                           grs_in,
    input  logic  [DATA_WIDTH - 1:0]       data_in,
    input  logic  [SFT_AMOUNT_WIDTH - 1:0] sft_in,

    output logic  [DATA_WIDTH - 1:0]       data_out,
    output grs_s                           grs_out
);

genvar                                      stg, idx;

// Total width includes original data width and guard, round bit
localparam int                              TOTAL_DWIDTH                          = DATA_WIDTH + 2;
localparam int                              SFT_STAGES                            = $clog2(TOTAL_DWIDTH);     // Barrel shifter stages
localparam int                              VLD_SFT_AMOUNT_WIDTH                  = $clog2(TOTAL_DWIDTH + 1); // Width of valid shift amount

// Valid shift amount
logic          [VLD_SFT_AMOUNT_WIDTH - 1:0] vld_sft;                                                          // Truncated shift amount to valid
logic                                       large_sft;                                                        // Indicate all valid bits shifted out

// Barrel shifter stages
logic          [TOTAL_DWIDTH - 1:0]         bsft_data            [SFT_STAGES + 1];
logic                                       bsft_sticky          [SFT_STAGES + 1];

// Sticky bit when large amount shifting
logic                                       sticky_large_sft;

// Valid shift amount truncate
// Fix on 0.2, the bit-width of sft-in may smaller than the VLD_SFT_AMOUNT_WIDTH
assign vld_sft          = VLD_SFT_AMOUNT_WIDTH'($unsigned(sft_in));

// Determination of very large shift out (fast path)
`GENERATE_START
if (SFT_AMOUNT_WIDTH <= VLD_SFT_AMOUNT_WIDTH) begin : gen_small_sft
    assign large_sft        = sft_in >= TOTAL_DWIDTH;
end : gen_small_sft
else begin : gen_large_sft
    logic sft_high_nonzero; // Higher bits (bits over valid shift amount width) not zero

    assign sft_high_nonzero = |sft_in[SFT_AMOUNT_WIDTH - 1:VLD_SFT_AMOUNT_WIDTH];
    assign large_sft        = sft_high_nonzero || (vld_sft >= TOTAL_DWIDTH);
end : gen_large_sft
`GENERATE_END

// Input layer
assign bsft_data[0]     = {data_in, grs_in.guard, grs_in.round};
assign bsft_sticky[0]   = grs_in.sticky;

// Barrel shifter
`GENERATE_START
for (stg = 0; stg < SFT_STAGES; stg++) begin : bsft_stage
    localparam int STAGE_SFT    = (1 << stg);

    logic stg_do_shift;   // Indicate current stage need to be shifted or not
    logic lossed_bits_or; // OR of shifted out bits in current stage

    assign stg_do_shift         = vld_sft[stg];

    // Barrel shifting
    for (idx = 0; idx < TOTAL_DWIDTH; idx++) begin : bsft_bits
        if (idx + STAGE_SFT < TOTAL_DWIDTH) begin
            // The shifted bit is still in the range of valid data
            assign bsft_data[stg + 1][idx] = stg_do_shift ? bsft_data[stg][idx + STAGE_SFT] : bsft_data[stg][idx];
        end
        else begin
            // Shift out
            assign bsft_data[stg + 1][idx] = stg_do_shift ? '0 : bsft_data[stg][idx];
        end
    end : bsft_bits

    // Sticky bit
    assign lossed_bits_or       = |bsft_data[stg][STAGE_SFT - 1:0];
    assign bsft_sticky[stg + 1] = bsft_sticky[stg] | (stg_do_shift ? lossed_bits_or : 'b0);
end : bsft_stage
`GENERATE_END

// The sticky bit when large shifting applied is OR of all bits input
assign sticky_large_sft = |{data_in, grs_in};

// Final output
always_comb begin : sft_final_out
    if (large_sft) begin
        data_out       = '0;
        grs_out.guard  = '0;
        grs_out.round  = '0;
        grs_out.sticky = sticky_large_sft;
    end
    else begin
        data_out       = bsft_data[SFT_STAGES][2 +: DATA_WIDTH];
        grs_out.guard  = bsft_data[SFT_STAGES][1];
        grs_out.round  = bsft_data[SFT_STAGES][0];
        grs_out.sticky = bsft_sticky[SFT_STAGES];
    end
end : sft_final_out

endmodule : hsf3_grs_rshift