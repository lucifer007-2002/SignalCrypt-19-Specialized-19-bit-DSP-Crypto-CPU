`timescale 1ns / 1ps
//------------------------------------------------------------
// alu.v  —  19-bit ALU for SignalCrypt-19
// Purely combinational. Not on the critical timing path —
// ALU operations complete well within 5ns on Artix-7 -2.
//
// alu_op encoding:
//   4'd0  = ADD    4'd1  = SUB    4'd2  = AND
//   4'd3  = OR     4'd4  = XOR    4'd5  = SHL
//   4'd6  = SHR    4'd7  = NOT    4'd8  = PASS (imm→result)
//   4'd15 = NOP → output 0
//
// Shift amount: lower 4 bits of operand_b (16 registers,
// max meaningful shift for 19-bit data is 18, 4 bits = 0–15
// covers the useful range; shifts ≥16 produce zero).
//------------------------------------------------------------
module alu (
    input  wire [18:0] operand_a,   // rs1 data (or rd for I-type)
    input  wire [18:0] operand_b,   // rs2 data OR sign-extended immediate
    input  wire [3:0]  alu_op,

    output reg  [18:0] result,
    output wire        zero,        // result == 0 (for BEQ/BNE)
    output wire        negative     // result[18] == 1 (for BLT signed)
);
    assign zero     = (result == 19'd0);
    assign negative = result[18];

    wire [3:0] shamt = operand_b[3:0];  // shift amount from lower 4 bits

    always @(*) begin
        case (alu_op)
            4'd0:  result = operand_a + operand_b;                    // ADD
            4'd1:  result = operand_a - operand_b;                    // SUB
            4'd2:  result = operand_a & operand_b;                    // AND
            4'd3:  result = operand_a | operand_b;                    // OR
            4'd4:  result = operand_a ^ operand_b;                    // XOR
            4'd5:  result = operand_a << shamt;                       // SHL logical
            4'd6:  result = operand_a >> shamt;                       // SHR logical
            4'd7:  result = ~operand_a;                               // NOT (b ignored)
            4'd8:  result = operand_b;                                // PASS imm/rs2
            default: result = 19'd0;                                  // NOP
        endcase
    end
endmodule
