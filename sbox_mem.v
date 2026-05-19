`timescale 1ns / 1ps
//------------------------------------------------------------
// sbox_mem.v  —  16-entry 4-bit → 4-bit substitution box
//
// The SBOX instruction: rd = SBOX[rs1[3:0]]
// Input:  lower 4 bits of rs1 (0–15)
// Output: 4-bit substitution value, zero-extended to 19 bits
//
// SBOX values: AES-style nibble S-box (not full AES SBOX —
// that operates on bytes). Using the PRESENT cipher S-box:
//   x: 0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
//      C  5  6  B  9  0  A  D  3  E  F  8  4  7  1  2
// This is a known cryptographically-sound 4-bit S-box with
// good differential and linear cryptanalysis resistance.
//
// Implementation: 16-entry ROM — Vivado infers as LUTRAM
// (distributed RAM) for 16 entries. Too small for BRAM.
// If you want BRAM inference: add (* rom_style = "block" *)
// but you'll waste an entire RAMB36 tile for 16 entries.
// Leave as LUTRAM — 4 LUT6s, zero timing concern.
//------------------------------------------------------------
module sbox_mem (
    input  wire [3:0]  addr,       // rs1[3:0]
    output wire [18:0] sbox_out    // zero-extended result
);
    // PRESENT cipher S-box
    reg [3:0] sbox [0:15];

    initial begin
        sbox[0]  = 4'hC;
        sbox[1]  = 4'h5;
        sbox[2]  = 4'h6;
        sbox[3]  = 4'hB;
        sbox[4]  = 4'h9;
        sbox[5]  = 4'h0;
        sbox[6]  = 4'hA;
        sbox[7]  = 4'hD;
        sbox[8]  = 4'h3;
        sbox[9]  = 4'hE;
        sbox[10] = 4'hF;
        sbox[11] = 4'h8;
        sbox[12] = 4'h4;
        sbox[13] = 4'h7;
        sbox[14] = 4'h1;
        sbox[15] = 4'h2;
    end

    // Combinational read — async ROM, no clock needed
    assign sbox_out = {15'b0, sbox[addr]};

endmodule
