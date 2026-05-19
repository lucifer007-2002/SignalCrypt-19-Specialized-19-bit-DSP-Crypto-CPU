`timescale 1ns / 1ps
//------------------------------------------------------------
// lfsr_unit.v  —  19-bit Galois LFSR
//
// WHY GALOIS NOT FIBONACCI:
//   Fibonacci LFSR: output bit = XOR of multiple tap positions,
//   then shift. The XOR chain has depth = number_of_taps - 1.
//   For a 19-bit register with 4 taps, that is 3 XOR levels —
//   ~1.2ns. Acceptable, but it gets worse as tap count grows.
//
//   Galois LFSR: shift register where each tap position XORs
//   the output bit into itself in parallel. ALL taps operate
//   simultaneously in a single XOR gate each. Depth = 1 XOR
//   regardless of tap count or register width. ~0.4ns.
//
//   At 200MHz (5ns budget) the difference seems small, but
//   the Galois topology also produces better randomness quality
//   (full maximal-length sequence) with simpler hardware.
//
// TAP POLYNOMIAL:
//   19-bit maximal-length polynomial: x^19 + x^18 + x^17 + x^14 + 1
//   Tap positions (0-indexed from bit 0): 18, 17, 16, 13
//   (bit 0 is the output/feedback bit)
//
// fn[2:0] input selects from 4 built-in tap polynomials:
//   3'b000: standard x^19+x^18+x^17+x^14+1
//   3'b001: x^19+x^6+1  (sparse, fast)
//   3'b010: x^19+x^18+x^17+x^16+1
//   3'b011: x^19+x^5+x^2+x+1
//   others: default to polynomial 0
//
// The LFSR instruction: rd = lfsr_next(rs1)
//   rs1 = current LFSR state (input)
//   rd  = next LFSR state (output, 1 step)
//   Result is purely combinational — registered by EX/WB.
//------------------------------------------------------------
module lfsr_unit (
    input  wire [18:0] state_in,    // current LFSR state (from rs1)
    input  wire [2:0]  tap_sel,     // tap polynomial select (from fn)
    output reg  [18:0] state_out    // next state (combinational)
);
    // Feedback bit = LSB of current state
    wire fb = state_in[0];

    // Galois step: shift right by 1, XOR feedback into tap positions
    // next[i] = state[i+1] XOR (fb AND tap_mask[i])
    // next[18] = 0 (MSB gets 0 from shift-in), then fb applied if tap

    wire [18:0] shifted = {1'b0, state_in[18:1]};  // shift right, MSB=0

    // Tap masks for each polynomial
    // Bit i = 1 means tap at position i (feedback XORed into bit i)
    wire [18:0] mask;
    assign mask =
        (tap_sel == 3'b000) ? 19'b111_0000_0000_0001_0000 : // x^19+x^18+x^17+x^14+1 → taps at 18,17,16,13
        (tap_sel == 3'b001) ? 19'b000_0000_0000_0100_0000 : // x^19+x^6+1 → tap at 6
        (tap_sel == 3'b010) ? 19'b111_1000_0000_0000_0000 : // x^19+x^18+x^17+x^16+1 → taps at 18,17,16,15
        (tap_sel == 3'b011) ? 19'b000_0000_0000_0010_0111 : // x^19+x^5+x^2+x+1 → taps at 5,2,1,0
                              19'b111_0000_0000_0001_0000 ;  // default = poly 0

    always @(*) begin
        // Galois update: each tap position XORs feedback bit
        // If fb=1, XOR the mask into the shifted state
        // If fb=0, state just shifts (no XOR needed)
        state_out = shifted ^ (fb ? mask : 19'd0);
    end

endmodule
