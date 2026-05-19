`timescale 1ns / 1ps
//------------------------------------------------------------
// wb_stage.v
// Writeback stage — combinational mux + key register write
//
// wb_sel encoding (from EX/WB register):
//   2'b00 = ALU result      (ADD, SUB, AND, OR, XOR, shifts,
//                            MOVI, ADDI, etc.)
//   2'b01 = memory data     (LD, LDK)
//   2'b10 = accumulator     (RDACC — low or high half)
//   2'b11 = crypto result   (LFSR, SBOX, KEYXOR)
//
// RDACC half-select:
//   RDACC passes imm[0] through in ex_wb_rdacc_sel.
//   0 → lower 19 bits of ACC (acc[18:0])
//   1 → upper 19 bits of ACC (acc[37:19])
//   The remaining bits [47:38] are sign extension — NEVER read.
//
// Key register write:
//   LDK writes KEYREG from memory data, not ALU result.
//   Control signal: ex_wb_key_write && wb_sel==01
//   Write happens here in WB — same cycle memory data is valid.
//   This is correct: LDK has 2-cycle latency just like LD,
//   and the programmer inserts a NOP after LDK anyway.
//------------------------------------------------------------
module wb_stage (
    // From EX/WB pipeline register
    input  wire [18:0] ex_wb_alu_result,
    input  wire [37:0] ex_wb_acc,
    input  wire [18:0] ex_wb_crypto_result,
    input  wire [3:0]  ex_wb_rd_addr,
    input  wire        ex_wb_reg_write,
    input  wire [1:0]  ex_wb_wb_sel,
    input  wire        ex_wb_key_write,
    input  wire        ex_wb_rdacc_sel,  // imm[0] for RDACC half select

    // From data memory (1-cycle latency output)
    input  wire [18:0] dmem_rdata,

    // Register file write port (→ ID stage)
    output wire [18:0] wb_data,
    output wire [3:0]  wb_rd,
    output wire        wb_reg_write,

    // Key register write port (→ key_reg in sc19_top)
    output wire [18:0] key_wdata,
    output wire        key_we
);
    // ── ACC half-select ──────────────────────────────────────
    // RDACC reads lower or upper 19-bit half of 38-bit accumulator
    // rdacc_sel = 0: acc[18:0]   (result of low-precision reads)
    // rdacc_sel = 1: acc[37:19]  (high word — integer part of fixed-pt)
    wire [18:0] acc_word = ex_wb_rdacc_sel ? ex_wb_acc[37:19]
                                           : ex_wb_acc[18:0];

    // ── WB data mux — four sources ───────────────────────────
    assign wb_data =
        (ex_wb_wb_sel == 2'b01) ? dmem_rdata          :  // LD result
        (ex_wb_wb_sel == 2'b10) ? acc_word             :  // RDACC
        (ex_wb_wb_sel == 2'b11) ? ex_wb_crypto_result  :  // crypto
                                   ex_wb_alu_result;       // default: ALU

    // Pass through register address and write enable
    assign wb_rd        = ex_wb_rd_addr;
    assign wb_reg_write = ex_wb_reg_write;

    // ── Key register write ────────────────────────────────────
    // LDK: write KEYREG from memory data when key_write is asserted
    // key_write is only set by LDK in the control unit
    assign key_wdata = dmem_rdata;
    assign key_we    = ex_wb_key_write;

endmodule
