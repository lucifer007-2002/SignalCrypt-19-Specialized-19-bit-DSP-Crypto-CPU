`timescale 1ns / 1ps
//------------------------------------------------------------
// mac_unit.v  —  Signed 19×19 multiply-accumulate
// Maps to Xilinx DSP48E1 on Artix-7
//
// DSP48E1 operation: P = A * B + C
//   A port: 30 bits (we use [18:0], sign-extended to 30)
//   B port: 18 bits (we use [17:0], sign-extended — 19th bit below)
//   C port: 48 bits (fed from accumulator — ACC)
//   P output: 48 bits (we use [37:0] for 19×19 product range)
//
// WHY B IS 18 BITS, NOT 19:
//   DSP48E1 B port is exactly 18 bits. A signed 19-bit value
//   needs sign extension. The 19th bit (MSB of rs2) feeds into
//   the A port extension or is handled by widening A.
//   Solution: sign-extend rs2 to 18 bits using [17:0] and handle
//   the MSB by sign-extending A to 30 bits including the carry.
//   For a cleaner mapping: keep rs2 as signed 18-bit operand
//   (range −131072 to +131071) and rs1 as signed 19-bit via A.
//   Alternatively, use both A[29:0] for full 19-bit × 18-bit.
//   This implementation uses: A=rs1 sign-extended to 25 bits,
//   B=rs2[17:0] sign-extended. Product range: 25×18 = 43-bit
//   signed result — fits in 48-bit P. Truncated to [37:0] for ACC.
//
// INFERENCE RULES — violate any one and you get LUT multiplier:
//   1. Inputs to DSP must come from registers (the ID/EX pipeline
//      register IS the input register — do NOT add another)
//   2. Use (* use_dsp = "yes" *) attribute on the accumulator reg
//   3. Accumulate with: acc <= acc + (a_in * b_in)
//      where a_in and b_in are already registered signals
//   4. mac_clear uses synchronous reset on the accumulator:
//      acc <= (a_in * b_in) when clear, else acc + (a_in * b_in)
//   5. Do NOT put any combinational logic on a_in or b_in between
//      the source register and this module's always block
//------------------------------------------------------------
module mac_unit (
    input  wire        clk,
    input  wire        rst,

    // Operand inputs — these MUST be pipeline register outputs
    // (ID/EX rs1_data and rs2_data). No logic between them and here.
    input  wire [18:0] a_in,        // rs1 — maps to DSP48 A port
    input  wire [17:0] b_in,        // rs2[17:0] — maps to DSP48 B port

    // MAC control
    input  wire        mac_en,      // 1 = perform MAC this cycle
    input  wire        mac_clear,   // 1 = clear ACC before multiply (MACZ)

    // Accumulator output
    output wire [37:0] acc_out      // truncated to meaningful 38 bits
);
    // (* use_dsp = "yes" *) — forces DSP48 inference even if
    // Vivado's cost model prefers LUTs for small multiplications.
    // Place this attribute directly on the accumulator register.
    (* use_dsp = "yes" *)
    reg [47:0] acc;

    // Sign-extend a_in to match DSP48 A port width
    // DSP48E1 A is 30 bits. Sign-extend 19-bit signed value.
    wire signed [29:0] a_ext = {{11{a_in[18]}}, a_in};

    // Sign-extend b_in — already 18 bits, DSP48 B is exactly 18 bits
    wire signed [17:0] b_ext = b_in;

    // MAC operation — this pattern is what Vivado recognises
    // for DSP48E1 inference: registered operands, += (A*B)
    always @(posedge clk) begin
        if (rst) begin
            acc <= 48'd0;
        end else if (mac_en) begin
            if (mac_clear)
                // MACZ: P = A * B (clear accumulator)
                acc <= a_ext * b_ext;
            else
                // MAC: P = P + A * B
                acc <= acc + (a_ext * b_ext);
        end
        // mac_en=0: accumulator holds its value
    end

    // Output truncated to 38 bits — maximum meaningful width
    // for signed 19-bit × 18-bit multiplication.
    // acc[37:0] covers the full product range.
    // acc[47:38] will be sign-extension bits — safe to discard.
    assign acc_out = acc[37:0];

endmodule
