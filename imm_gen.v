verilog
`timescale 1ns / 1ps
//------------------------------------------------------------
// imm_gen.v
// Immediate sign-extension for SignalCrypt-19
//
// Format encoding (from control_unit):
//   2'b00 = R-type: imm6  = instr[5:0],  sign bit = instr[5]
//   2'b01 = I-type: imm10 = instr[9:0],  sign bit = instr[9]
//   2'b10 = B-type: off10 = instr[9:0],  sign bit = instr[9]
//   (B-type and I-type share the same extraction — different semantics)
//
// CRITICAL — imm10 field:
//   In I-type: bits [13:10] are rd (destination register),
//   bits [9:0] are the 10-bit immediate.
//   The sign bit of imm10 is instr[9] — this is the MSB of
//   what would be rs2 in an R-type instruction.
//   Do NOT use instr[18] as the sign bit for imm10. That is
//   the MSB of the opcode field.
//------------------------------------------------------------
module imm_gen (
    input  wire [18:0] instr,
    input  wire [1:0]  fmt,        // format select from control_unit
    output reg  [18:0] imm_out
);
    always @(*) begin
        case (fmt)
            2'b00: // R-type: 6-bit immediate, sign-extended to 19 bits
                imm_out = {{13{instr[5]}}, instr[5:0]};

            2'b01, // I-type: 10-bit immediate
            2'b10: // B-type: 10-bit PC-relative offset
                // Sign bit is instr[9] — the MSB of bits[9:0]
                imm_out = {{9{instr[9]}}, instr[9:0]};

            default:
                imm_out = 19'd0;
        endcase
    end
endmodule
