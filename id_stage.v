`timescale 1ns / 1ps
//------------------------------------------------------------
// id_stage.v
// Decode stage — instantiates control_unit, imm_gen, regfile
// Drives ID/EX pipeline register
//------------------------------------------------------------
module id_stage (
    input  wire        clk,
    input  wire        rst,

    // From IF/ID register
    input  wire [18:0] if_id_pc,
    input  wire [18:0] if_id_instr,
    input  wire        if_id_valid,

    // Hazard controls
    input  wire        stall,
    input  wire        flush,

    // WB writeback port → register file
    input  wire [3:0]  wb_rd,
    input  wire [18:0] wb_data,
    input  wire        wb_reg_write,

    //── ID/EX pipeline register outputs ──────────────────────
    // Data
    output reg  [18:0] id_ex_pc,
    output reg  [18:0] id_ex_rs1_data,
    output reg  [18:0] id_ex_rs2_data,
    output reg  [18:0] id_ex_imm,
    output reg  [3:0]  id_ex_rs1_addr,
    output reg  [3:0]  id_ex_rs2_addr,
    output reg  [3:0]  id_ex_rd_addr,
    output reg  [4:0]  id_ex_opcode,
    output reg  [2:0]  id_ex_fn,         // instr[2:0] — LFSR tap select, RDACC half

    // Control signals
    output reg  [3:0]  id_ex_alu_op,
    output reg  [1:0]  id_ex_fmt,
    output reg         id_ex_reg_write,
    output reg  [1:0]  id_ex_wb_sel,
    output reg         id_ex_mem_read,
    output reg         id_ex_mem_write,
    output reg         id_ex_key_write,
    output reg         id_ex_is_mac,
    output reg         id_ex_mac_clear,
    output reg         id_ex_is_crypto,
    output reg  [1:0]  id_ex_crypto_sel,
    output reg         id_ex_is_branch,
    output reg         id_ex_is_jump,
    output reg         id_ex_is_jmpr,
    output reg         id_ex_is_halt,

    // Combinational decode outputs for hazard detection
    output wire [3:0]  id_rs1_addr,
    output wire [3:0]  id_rs2_addr
);

    //── Instruction field extraction (combinational) ──────────
    wire [4:0]  opcode  = if_id_instr[18:14];
    wire [3:0]  rs1     = if_id_instr[13:10];
    wire [3:0]  rs2_rd  = if_id_instr[9:6];    // rs2 in R-type, rd in I-type
    wire [2:0]  fn      = if_id_instr[2:0];

    // For R-type: rd comes from [5:3] (3 bits only — rd[3] = rs2_rd[3])
    // Convention: rd is always bits [9:6] for simplicity
    // (4-bit register address from the same field as rs2 in I-type)
    wire [3:0]  rd_addr = if_id_instr[9:6];

    assign id_rs1_addr = rs1;
    assign id_rs2_addr = rs2_rd;

    //── Control unit ──────────────────────────────────────────
    wire [1:0]  fmt;
    wire        reg_write, mem_read, mem_write, key_write;
    wire        is_mac, mac_clear, is_crypto;
    wire [1:0]  crypto_sel;
    wire        is_branch, is_jump, is_jmpr, is_halt, illegal;
    wire [3:0]  alu_op;
    wire [1:0]  wb_sel;

    control_unit u_ctrl (
        .opcode     (opcode),
        .fmt        (fmt),
        .reg_write  (reg_write),
        .wb_sel     (wb_sel),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .key_write  (key_write),
        .is_mac     (is_mac),
        .mac_clear  (mac_clear),
        .is_crypto  (is_crypto),
        .crypto_sel (crypto_sel),
        .is_branch  (is_branch),
        .is_jump    (is_jump),
        .is_jmpr    (is_jmpr),
        .alu_op     (alu_op),
        .is_halt    (is_halt),
        .illegal    (illegal)
    );

    //── Immediate generator ───────────────────────────────────
    wire [18:0] imm;

    imm_gen u_immgen (
        .instr   (if_id_instr),
        .fmt     (fmt),
        .imm_out (imm)
    );

    //── Register file ─────────────────────────────────────────
    wire [18:0] rs1_data, rs2_data;

    regfile u_regfile (
        .clk (clk),
        .ra1 (rs1),
        .rd1 (rs1_data),
        .ra2 (rs2_rd),
        .rd2 (rs2_data),
        .wa  (wb_rd),
        .wd  (wb_data),
        .we  (wb_reg_write)
    );

    //── ID/EX pipeline register ───────────────────────────────
    wire bubble = rst || flush || !if_id_valid;

    always @(posedge clk) begin
        if (bubble) begin
            id_ex_pc         <= 19'd0;
            id_ex_rs1_data   <= 19'd0;
            id_ex_rs2_data   <= 19'd0;
            id_ex_imm        <= 19'd0;
            id_ex_rs1_addr   <= 4'd0;
            id_ex_rs2_addr   <= 4'd0;
            id_ex_rd_addr    <= 4'd0;
            id_ex_opcode     <= 5'b01111;  // NOP opcode
            id_ex_fn         <= 3'd0;
            id_ex_alu_op     <= 4'd15;     // ALU_NOP
            id_ex_fmt        <= 2'd0;
            id_ex_reg_write  <= 1'b0;
            id_ex_wb_sel     <= 2'b00;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_key_write  <= 1'b0;
            id_ex_is_mac     <= 1'b0;
            id_ex_mac_clear  <= 1'b0;
            id_ex_is_crypto  <= 1'b0;
            id_ex_crypto_sel <= 2'b00;
            id_ex_is_branch  <= 1'b0;
            id_ex_is_jump    <= 1'b0;
            id_ex_is_jmpr    <= 1'b0;
            id_ex_is_halt    <= 1'b0;
        end else if (!stall) begin
            id_ex_pc         <= if_id_pc;
            id_ex_rs1_data   <= rs1_data;
            id_ex_rs2_data   <= rs2_data;
            id_ex_imm        <= imm;
            id_ex_rs1_addr   <= rs1;
            id_ex_rs2_addr   <= rs2_rd;
            id_ex_rd_addr    <= rd_addr;
            id_ex_opcode     <= opcode;
            id_ex_fn         <= fn;
            id_ex_alu_op     <= alu_op;
            id_ex_fmt        <= fmt;
            id_ex_reg_write  <= reg_write;
            id_ex_wb_sel     <= wb_sel;
            id_ex_mem_read   <= mem_read;
            id_ex_mem_write  <= mem_write;
            id_ex_key_write  <= key_write;
            id_ex_is_mac     <= is_mac;
            id_ex_mac_clear  <= mac_clear;
            id_ex_is_crypto  <= is_crypto;
            id_ex_crypto_sel <= crypto_sel;
            id_ex_is_branch  <= is_branch;
            id_ex_is_jump    <= is_jump;
            id_ex_is_jmpr    <= is_jmpr;
            id_ex_is_halt    <= is_halt;
        end
        // stall: ID/EX holds
    end

endmodule
