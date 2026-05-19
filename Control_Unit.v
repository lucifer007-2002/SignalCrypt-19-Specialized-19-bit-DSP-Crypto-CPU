`timescale 1ns / 1ps
//------------------------------------------------------------
// control_unit.v
// Decodes 5-bit opcode → all pipeline control signals
//
// wb_sel encoding:
//   2'b00 = ALU result
//   2'b01 = memory read data (LD)
//   2'b10 = accumulator low or high word (RDACC)
//   2'b11 = crypto unit result (LFSR, SBOX, KEYXOR)
//------------------------------------------------------------

// Opcode constants — match Part 2 table exactly
`define OP_ADD    5'b00000
`define OP_SUB    5'b00001
`define OP_AND    5'b00010
`define OP_OR     5'b00011
`define OP_XOR    5'b00100
`define OP_SHL    5'b00101
`define OP_SHR    5'b00110
`define OP_NOT    5'b00111
`define OP_ADDI   5'b01000
`define OP_ANDI   5'b01001
`define OP_ORI    5'b01010
`define OP_XORI   5'b01011
`define OP_SHLI   5'b01100
`define OP_SHRI   5'b01101
`define OP_MOVI   5'b01110
`define OP_NOP    5'b01111
`define OP_LD     5'b10000
`define OP_ST     5'b10001
`define OP_LDK    5'b10010
`define OP_RSVD   5'b10011
`define OP_BEQ    5'b10100
`define OP_BNE    5'b10101
`define OP_BLT    5'b10110
`define OP_JMP    5'b10111
`define OP_JMPR   5'b11000
`define OP_MAC    5'b11001
`define OP_MACZ   5'b11010
`define OP_RDACC  5'b11011
`define OP_LFSR   5'b11100
`define OP_SBOX   5'b11101
`define OP_KEYXOR 5'b11110
`define OP_HALT   5'b11111

module control_unit (
    input  wire [4:0]  opcode,

    // Instruction format (for immediate generator)
    output reg  [1:0]  fmt,          // 00=R, 01=I, 10=B

    // Register file controls
    output reg         reg_write,    // 1 = write result to register file
    output reg  [1:0]  wb_sel,       // writeback source select

    // Memory controls
    output reg         mem_read,     // 1 = load
    output reg         mem_write,    // 1 = store
    output reg         key_write,    // 1 = write to KEYREG (LDK)

    // DSP / MAC controls
    output reg         is_mac,       // 1 = MAC or MACZ instruction
    output reg         mac_clear,    // 1 = MACZ (clear ACC before multiply)

    // Crypto controls
    output reg         is_crypto,    // 1 = LFSR, SBOX, or KEYXOR
    output reg  [1:0]  crypto_sel,   // 00=LFSR, 01=SBOX, 10=KEYXOR

    // Branch controls
    output reg         is_branch,    // 1 = conditional branch
    output reg         is_jump,      // 1 = unconditional jump
    output reg         is_jmpr,      // 1 = indirect jump (JMPR)

    // ALU operation (passed through to EX)
    output reg  [3:0]  alu_op,       // matches ALU module encoding

    // Special
    output reg         is_halt,
    output reg         illegal
);
    // ALU operation encoding
    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_AND  = 4'd2;
    localparam ALU_OR   = 4'd3;
    localparam ALU_XOR  = 4'd4;
    localparam ALU_SHL  = 4'd5;
    localparam ALU_SHR  = 4'd6;
    localparam ALU_NOT  = 4'd7;
    localparam ALU_PASS = 4'd8;  // pass rs1 / imm directly (MOVI, LD addr)
    localparam ALU_NOP  = 4'd15;

    always @(*) begin
        // Safe defaults — every signal explicitly set, no latches
        fmt        = 2'b00;
        reg_write  = 1'b0;
        wb_sel     = 2'b00;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        key_write  = 1'b0;
        is_mac     = 1'b0;
        mac_clear  = 1'b0;
        is_crypto  = 1'b0;
        crypto_sel = 2'b00;
        is_branch  = 1'b0;
        is_jump    = 1'b0;
        is_jmpr    = 1'b0;
        alu_op     = ALU_NOP;
        is_halt    = 1'b0;
        illegal    = 1'b0;

        case (opcode)
            //── ALU register-register ──────────────────────
            `OP_ADD: begin
                reg_write = 1'b1; alu_op = ALU_ADD; fmt = 2'b00; end
            `OP_SUB: begin
                reg_write = 1'b1; alu_op = ALU_SUB; fmt = 2'b00; end
            `OP_AND: begin
                reg_write = 1'b1; alu_op = ALU_AND; fmt = 2'b00; end
            `OP_OR: begin
                reg_write = 1'b1; alu_op = ALU_OR;  fmt = 2'b00; end
            `OP_XOR: begin
                reg_write = 1'b1; alu_op = ALU_XOR; fmt = 2'b00; end
            `OP_SHL: begin
                reg_write = 1'b1; alu_op = ALU_SHL; fmt = 2'b00; end
            `OP_SHR: begin
                reg_write = 1'b1; alu_op = ALU_SHR; fmt = 2'b00; end
            `OP_NOT: begin
                reg_write = 1'b1; alu_op = ALU_NOT; fmt = 2'b00; end

            //── ALU immediate ──────────────────────────────
            `OP_ADDI: begin
                reg_write = 1'b1; alu_op = ALU_ADD; fmt = 2'b01; end
            `OP_ANDI: begin
                reg_write = 1'b1; alu_op = ALU_AND; fmt = 2'b01; end
            `OP_ORI: begin
                reg_write = 1'b1; alu_op = ALU_OR;  fmt = 2'b01; end
            `OP_XORI: begin
                reg_write = 1'b1; alu_op = ALU_XOR; fmt = 2'b01; end
            `OP_SHLI: begin
                reg_write = 1'b1; alu_op = ALU_SHL; fmt = 2'b01; end
            `OP_SHRI: begin
                reg_write = 1'b1; alu_op = ALU_SHR; fmt = 2'b01; end
            `OP_MOVI: begin
                // MOVI: rd = zero-extended imm10
                // Use ALU_PASS — EX stage passes imm as result
                reg_write = 1'b1; alu_op = ALU_PASS; fmt = 2'b01; end

            //── Memory ─────────────────────────────────────
            `OP_LD: begin
                // LD: address = rd + imm10, result → rd
                // 2-cycle visible latency — programmer inserts NOP
                reg_write = 1'b1; mem_read = 1'b1;
                alu_op = ALU_ADD; fmt = 2'b01; wb_sel = 2'b01; end
            `OP_ST: begin
                // ST: DMEM[rs1 + imm6] = rs2 — R-type with imm6 offset
                mem_write = 1'b1; alu_op = ALU_ADD; fmt = 2'b00; end
            `OP_LDK: begin
                // LDK: KEYREG = DMEM[rd + imm10]
                mem_read = 1'b1; key_write = 1'b1;
                alu_op = ALU_ADD; fmt = 2'b01; end

            //── Branch / Jump ───────────────────────────────
            `OP_BEQ: begin
                is_branch = 1'b1; fmt = 2'b10; alu_op = ALU_NOP; end
            `OP_BNE: begin
                is_branch = 1'b1; fmt = 2'b10; alu_op = ALU_NOP; end
            `OP_BLT: begin
                is_branch = 1'b1; fmt = 2'b10; alu_op = ALU_NOP; end
            `OP_JMP: begin
                is_jump = 1'b1; fmt = 2'b10; alu_op = ALU_NOP; end
            `OP_JMPR: begin
                is_jmpr = 1'b1; fmt = 2'b00; alu_op = ALU_NOP; end

            //── MAC / DSP48 ─────────────────────────────────
            `OP_MAC: begin
                // ACC = ACC + (rs1 × rs2) — maps to DSP48E1
                is_mac = 1'b1; fmt = 2'b00; end
            `OP_MACZ: begin
                // ACC = rs1 × rs2 (clear first)
                is_mac = 1'b1; mac_clear = 1'b1; fmt = 2'b00; end
            `OP_RDACC: begin
                // rd = ACC[18:0] or ACC[37:19] based on imm10[0]
                reg_write = 1'b1; wb_sel = 2'b10; fmt = 2'b01; end

            //── Crypto ──────────────────────────────────────
            `OP_LFSR: begin
                reg_write = 1'b1; is_crypto = 1'b1;
                crypto_sel = 2'b00; wb_sel = 2'b11; fmt = 2'b00; end
            `OP_SBOX: begin
                reg_write = 1'b1; is_crypto = 1'b1;
                crypto_sel = 2'b01; wb_sel = 2'b11; fmt = 2'b00; end
            `OP_KEYXOR: begin
                reg_write = 1'b1; is_crypto = 1'b1;
                crypto_sel = 2'b10; wb_sel = 2'b11; fmt = 2'b00; end

            //── Special ─────────────────────────────────────
            `OP_NOP: begin
                // Explicitly do nothing — all defaults hold
            end
            `OP_HALT: begin
                is_halt = 1'b1; end

            `OP_RSVD: begin
                illegal = 1'b1; end

            default: begin
                illegal = 1'b1; end
        endcase
    end
endmodule
