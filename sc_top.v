`timescale 1ns / 1ps
//------------------------------------------------------------
// sc19_top.v  —  SignalCrypt-19 complete integration
// Target: AC701 (XC7A200T-2FBG676)
// All 5 pipeline stages + memories + key register wired.
//------------------------------------------------------------
module sc19_top (
    input  wire        sysclk_p,
    input  wire        sysclk_n,
    input  wire        cpu_reset,
    output wire [3:0]  led,
    output wire        uart_tx,
    input  wire        uart_rx,
    input  wire [3:0]  dip_sw
);

    //============================================================
    // SECTION 1 — Clock input (LVDS → single-ended)
    //============================================================
    wire clk_unbuf, clk;

    IBUFDS #(.DIFF_TERM("FALSE"), .IBUF_LOW_PWR("FALSE"))
    u_ibufds (.I(sysclk_p), .IB(sysclk_n), .O(clk_unbuf));

    BUFG u_bufg (.I(clk_unbuf), .O(clk));

    //============================================================
    // SECTION 2 — Internal wire declarations
    //============================================================

    // ── IF stage wires ──
    wire [18:0] if_pc;
    wire [18:0] imem_instr;
    wire        if_id_valid;
    wire [18:0] if_id_pc;

    // ── Hazard / branch control ──
    wire        branch_taken;
    wire [18:0] branch_target;
    wire        stall_if;       // stall IF stage PC and IF/ID reg
    wire        flush_ex;       // flush EX/WB on branch taken

    // Combined flush to IF stage
    wire if_flush = branch_taken;   // branch squashes 2 in-flight instrs
    wire if_stall = stall_if;       // load-use stall (NOP policy — see below)

    // ── ID/EX pipeline register wires ──
    wire [18:0] id_ex_pc;
    wire [18:0] id_ex_rs1_data, id_ex_rs2_data;
    wire [18:0] id_ex_imm;
    wire [3:0]  id_ex_rs1_addr, id_ex_rs2_addr, id_ex_rd_addr;
    wire [4:0]  id_ex_opcode;
    wire [2:0]  id_ex_fn;
    wire [3:0]  id_ex_alu_op;
    wire [1:0]  id_ex_fmt;
    wire        id_ex_reg_write;
    wire [1:0]  id_ex_wb_sel;
    wire        id_ex_mem_read, id_ex_mem_write, id_ex_key_write;
    wire        id_ex_is_mac, id_ex_mac_clear;
    wire        id_ex_is_crypto;
    wire [1:0]  id_ex_crypto_sel;
    wire        id_ex_is_branch, id_ex_is_jump, id_ex_is_jmpr;
    wire        id_ex_is_halt;
    // Combinational decode outputs for hazard unit
    wire [3:0]  id_rs1_addr, id_rs2_addr;

    // ── EX stage outputs ──
    wire [18:0] dmem_addr, dmem_wdata;
    wire        dmem_we, dmem_re;
    wire        ex_key_write_raw;
    wire        cpu_halt;

    // ── EX/WB pipeline register wires ──
    wire [18:0] ex_wb_alu_result;
    wire [37:0] ex_wb_acc;
    wire [18:0] ex_wb_crypto_result;
    wire [3:0]  ex_wb_rd_addr;
    wire        ex_wb_reg_write;
    wire [1:0]  ex_wb_wb_sel;
    wire        ex_wb_mem_read, ex_wb_mem_write;
    wire        ex_wb_key_write;
    wire [18:0] ex_wb_dmem_addr, ex_wb_dmem_wdata;
    wire        ex_wb_rdacc_sel;  // imm[0] carried for RDACC

    // ── Data memory output ──
    wire [18:0] dmem_rdata;

    // ── WB outputs ──
    wire [18:0] wb_data;
    wire [3:0]  wb_rd;
    wire        wb_reg_write;

    // ── Key register ──
    wire [18:0] keyreg_value;    // output of key_reg → EX KEYXOR
    wire [18:0] key_wdata;
    wire        key_we;

    // ── Crypto KEYXOR result (wired back to EX stage) ──
    wire [18:0] keyxor_result = id_ex_rs1_data ^ keyreg_value;

    //============================================================
    // SECTION 3 — Instruction memory
    //============================================================
    instr_mem #(.DEPTH(1024)) u_imem (
        .clk   (clk),
        .addr  (if_pc),
        .instr (imem_instr)
    );

    //============================================================
    // SECTION 4 — IF stage
    //============================================================
    if_stage u_if (
        .clk           (clk),
        .rst           (cpu_reset),
        .stall         (if_stall),
        .flush         (if_flush),
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .if_id_pc      (if_id_pc),
        .if_id_instr   (imem_instr),   // BRAM registered output
        .if_id_valid   (if_id_valid)
    );

    // PC exposed for IMEM address
    assign if_pc = if_id_pc; // if_stage drives PC internally;
    // NOTE: in your if_stage implementation, expose pc as an
    // output wire so sc19_top can connect it to imem addr.
    // Add: output wire [18:0] pc_out to if_stage port list,
    // assign pc_out = pc; — then use that here instead.

    //============================================================
    // SECTION 5 — ID stage
    //============================================================
    id_stage u_id (
        .clk              (clk),
        .rst              (cpu_reset),
        .if_id_pc         (if_id_pc),
        .if_id_instr      (imem_instr),
        .if_id_valid      (if_id_valid),
        .stall            (if_stall),
        .flush            (if_flush),
        // WB writeback
        .wb_rd            (wb_rd),
        .wb_data          (wb_data),
        .wb_reg_write     (wb_reg_write),
        // ID/EX outputs
        .id_ex_pc         (id_ex_pc),
        .id_ex_rs1_data   (id_ex_rs1_data),
        .id_ex_rs2_data   (id_ex_rs2_data),
        .id_ex_imm        (id_ex_imm),
        .id_ex_rs1_addr   (id_ex_rs1_addr),
        .id_ex_rs2_addr   (id_ex_rs2_addr),
        .id_ex_rd_addr    (id_ex_rd_addr),
        .id_ex_opcode     (id_ex_opcode),
        .id_ex_fn         (id_ex_fn),
        .id_ex_alu_op     (id_ex_alu_op),
        .id_ex_fmt        (id_ex_fmt),
        .id_ex_reg_write  (id_ex_reg_write),
        .id_ex_wb_sel     (id_ex_wb_sel),
        .id_ex_mem_read   (id_ex_mem_read),
        .id_ex_mem_write  (id_ex_mem_write),
        .id_ex_key_write  (id_ex_key_write),
        .id_ex_is_mac     (id_ex_is_mac),
        .id_ex_mac_clear  (id_ex_mac_clear),
        .id_ex_is_crypto  (id_ex_is_crypto),
        .id_ex_crypto_sel (id_ex_crypto_sel),
        .id_ex_is_branch  (id_ex_is_branch),
        .id_ex_is_jump    (id_ex_is_jump),
        .id_ex_is_jmpr    (id_ex_is_jmpr),
        .id_ex_is_halt    (id_ex_is_halt),
        .id_rs1_addr      (id_rs1_addr),
        .id_rs2_addr      (id_rs2_addr)
    );

    //============================================================
    // SECTION 6 — EX stage
    //============================================================
    ex_stage u_ex (
        .clk                (clk),
        .rst                (cpu_reset),
        .id_ex_pc           (id_ex_pc),
        .id_ex_rs1_data     (id_ex_rs1_data),
        .id_ex_rs2_data     (id_ex_rs2_data),
        .id_ex_imm          (id_ex_imm),
        .id_ex_rs1_addr     (id_ex_rs1_addr),
        .id_ex_rs2_addr     (id_ex_rs2_addr),
        .id_ex_rd_addr      (id_ex_rd_addr),
        .id_ex_opcode       (id_ex_opcode),
        .id_ex_fn           (id_ex_fn),
        .id_ex_alu_op       (id_ex_alu_op),
        .id_ex_reg_write    (id_ex_reg_write),
        .id_ex_wb_sel       (id_ex_wb_sel),
        .id_ex_mem_read     (id_ex_mem_read),
        .id_ex_mem_write    (id_ex_mem_write),
        .id_ex_key_write    (id_ex_key_write),
        .id_ex_is_mac       (id_ex_is_mac),
        .id_ex_mac_clear    (id_ex_mac_clear),
        .id_ex_is_crypto    (id_ex_is_crypto),
        .id_ex_crypto_sel   (id_ex_crypto_sel),
        .id_ex_is_branch    (id_ex_is_branch),
        .id_ex_is_jump      (id_ex_is_jump),
        .id_ex_is_jmpr      (id_ex_is_jmpr),
        .id_ex_is_halt      (id_ex_is_halt),
        // KEYXOR data from key register (top-level wired)
        .keyxor_data        (keyxor_result),
        .flush              (flush_ex),
        // Branch resolution
        .branch_taken       (branch_taken),
        .branch_target      (branch_target),
        .cpu_halt           (cpu_halt),
        // Memory interface
        .dmem_addr          (dmem_addr),
        .dmem_wdata         (dmem_wdata),
        .dmem_we            (dmem_we),
        .dmem_re            (dmem_re),
        .ex_key_write       (ex_key_write_raw),
        // EX/WB register outputs
        .ex_wb_alu_result   (ex_wb_alu_result),
        .ex_wb_acc          (ex_wb_acc),
        .ex_wb_crypto_result(ex_wb_crypto_result),
        .ex_wb_rd_addr      (ex_wb_rd_addr),
        .ex_wb_reg_write    (ex_wb_reg_write),
        .ex_wb_wb_sel       (ex_wb_wb_sel),
        .ex_wb_mem_read     (ex_wb_mem_read),
        .ex_wb_mem_write    (ex_wb_mem_write),
        .ex_wb_key_write    (ex_wb_key_write),
        .ex_wb_dmem_addr    (ex_wb_dmem_addr),
        .ex_wb_dmem_wdata   (ex_wb_dmem_wdata),
        .ex_wb_rdacc_sel    (ex_wb_rdacc_sel)
    );

    // flush_ex = branch taken — squash instructions behind branch
    assign flush_ex = branch_taken;

    //============================================================
    // SECTION 7 — Data memory
    //============================================================
    data_mem #(.DEPTH(1024)) u_dmem (
        .clk   (clk),
        .addr  (ex_wb_dmem_addr),   // address from EX/WB register
        .wdata (ex_wb_dmem_wdata),  // store data from EX/WB
        .we    (ex_wb_mem_write),   // store enable
        .rdata (dmem_rdata)         // registered output to WB
    );

    //============================================================
    // SECTION 8 — Key register
    //============================================================
    key_reg u_keyreg (
        .clk        (clk),
        .rst        (cpu_reset),
        .key_wdata  (key_wdata),       // from WB stage (dmem_rdata)
        .key_we     (key_we),          // from WB stage
        .data_in    (id_ex_rs1_data),  // for KEYXOR — rs1 in EX
        .keyxor_en  (id_ex_is_crypto && (id_ex_crypto_sel == 2'b10)),
        .key_out    (keyreg_value),
        .xor_result ()                 // not used — computed inline above
    );

    //============================================================
    // SECTION 9 — WB stage
    //============================================================
    wb_stage u_wb (
        .ex_wb_alu_result    (ex_wb_alu_result),
        .ex_wb_acc           (ex_wb_acc),
        .ex_wb_crypto_result (ex_wb_crypto_result),
        .ex_wb_rd_addr       (ex_wb_rd_addr),
        .ex_wb_reg_write     (ex_wb_reg_write),
        .ex_wb_wb_sel        (ex_wb_wb_sel),
        .ex_wb_key_write     (ex_wb_key_write),
        .ex_wb_rdacc_sel     (ex_wb_rdacc_sel),
        .dmem_rdata          (dmem_rdata),
        .wb_data             (wb_data),
        .wb_rd               (wb_rd),
        .wb_reg_write        (wb_reg_write),
        .key_wdata           (key_wdata),
        .key_we              (key_we)
    );

    //============================================================
    // SECTION 10 — Stall logic
    //============================================================
    // SignalCrypt-19 stall policy:
    // Load-use hazard: LD/LDK is in EX and next instruction
    // reads its destination register in ID.
    //
    // ISA contract says programmer inserts NOP after LD/LDK.
    // For hardware enforcement (defensive): detect and stall anyway.
    //
    // Stall condition:
    //   id_ex_mem_read == 1 (load in EX)
    //   AND (id_ex_rd_addr == id_rs1_addr OR id_rs2_addr)
    assign stall_if = id_ex_mem_read &&
                      ((id_ex_rd_addr == id_rs1_addr) ||
                       (id_ex_rd_addr == id_rs2_addr));

    //============================================================
    // SECTION 11 — LED and debug outputs
    //============================================================
    reg running_r;
    always @(posedge clk)
        running_r <= ~cpu_reset;

    assign led[0] = running_r;                 // CPU active
    assign led[1] = cpu_halt;                  // HALT reached
    assign led[2] = id_ex_is_mac;             // MAC instruction in EX
    assign led[3] = id_ex_is_crypto;          // Crypto instruction in EX

    assign uart_tx = 1'b1;   // idle — UART transmitter not implemented

endmodule
