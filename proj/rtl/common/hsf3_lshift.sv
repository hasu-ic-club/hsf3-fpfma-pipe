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
// FILE NAME: hsf3_lshift.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1
// VERSION DESCRIPTION: First Edition cloned from HSF2 v0.2
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1        O. Tsusaki    2026/11/23    First Edition cloned from HSF2 v0.2
//
//-------------------------------------------------------------------------
// PURPOSE: Unsigned left shifter (binary shifter)
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                 DEFAULT VALUE
// DATA_WIDTH          1-128       Shifted data width          24
// SFT_AMOUNT_WIDTH    1-128       Shift amount width          8
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Unsigned left shifter (binary shifter)
module hsf3_lshift
#(
    parameter int DATA_WIDTH       = 24,
    parameter int SFT_AMOUNT_WIDTH = 8
)
(
    input  logic  [DATA_WIDTH - 1:0]       data_in,
    input  logic  [SFT_AMOUNT_WIDTH - 1:0] sft_in,

    output logic  [DATA_WIDTH - 1:0]       data_out
);

genvar         stg, idx;

localparam int SFT_STAGES                            = $clog2(DATA_WIDTH);     // Barrel shifter stages
localparam int VLD_SFT_AMOUNT_WIDTH                  = $clog2(DATA_WIDTH + 1); // Width of valid shift amount

typedef logic [DATA_WIDTH - 1:0]           data_t;
typedef logic [VLD_SFT_AMOUNT_WIDTH - 1:0] vld_sft_t;

vld_sft_t      vld_sft;
data_t         bsft_data            [SFT_STAGES + 1];

// Valid shift amount truncate
assign vld_sft      = VLD_SFT_AMOUNT_WIDTH'($unsigned(sft_in));

// Input layer
assign bsft_data[0] = data_in;

// Barrel shifter
`GENERATE_START
for (stg = 0; stg < SFT_STAGES; stg++) begin : bsft_stage
    localparam int STAGE_SFT    = (1 << stg);

    logic stg_do_shift;   // Indicate current stage need to be shifted or not
    logic lossed_bits_or; // OR of shifted out bits in current stage

    assign stg_do_shift         = vld_sft[stg];

    // Barrel shifting
    for (idx = 0; idx < DATA_WIDTH; idx++) begin : bsft_bits
        if (idx >= STAGE_SFT) begin
            // The shifted bit is still in the range of valid data
            assign bsft_data[stg + 1][idx] = stg_do_shift ? bsft_data[stg][idx - STAGE_SFT] : bsft_data[stg][idx];
        end
        else begin
            // Shift 0 in
            assign bsft_data[stg + 1][idx] = stg_do_shift ? '0 : bsft_data[stg][idx];
        end
    end : bsft_bits
end : bsft_stage
`GENERATE_END

// Final output
assign data_out     = bsft_data[SFT_STAGES];

endmodule : hsf3_lshift